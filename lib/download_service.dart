import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundclock/audius_service.dart';
import 'package:soundclock/deezer_service.dart';
import 'package:soundclock/premium_gate.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/premium_sheet.dart';
import 'package:soundclock/song.dart';
import 'package:soundclock/song_json.dart';

/// Ek downloaded gaana.
class DownloadedSong {
  final Song song;

  /// File ka naam (sirf naam, poora path nahi, taake iOS par app update ke
  /// baad bhi file mil jaye). Web par null.
  final String? fileName;

  /// File ka poora path (runtime par bana hua). Web par null.
  final String? path;

  final int bytes;
  final int savedAt;

  const DownloadedSong({
    required this.song,
    required this.fileName,
    required this.path,
    required this.bytes,
    required this.savedAt,
  });

  /// true = list mein hai (Google account ke cloud backup se aaya) lekin is
  /// device par file nahi hai (naya phone / app dobara install). Aise gaane
  /// online stream hote hain; [DownloadService.redownload] se file wapas aa jati hai.
  bool get isCloudOnly => !kIsWeb && path == null;

  /// Player ko ye Song do: local file ho to file se chalega (offline),
  /// warna original URL se.
  Song get playable {
    final p = path;
    if (p == null || kIsWeb) return song;

    return Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      imageUrl: song.imageUrl,
      audioUrl: Uri.file(p).toString(),
      durationSec: song.durationSec,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'song': songToMap(song),
        'fileName': fileName,
        'bytes': bytes,
        'savedAt': savedAt,
      };
}

/// Poori app ka download manager.
/// - Mobile/desktop: gaana file ban kar device par save hota hai (offline chalta hai).
/// - Web: browser app ke andar file save nahi kar sakta, isliye sirf list mein
///   save hota hai aur stream hota rehta hai.
///
/// CLOUD BACKUP (naya): login ke baad downloads ki list Firestore mein
/// users/{uid}/downloads par save hoti hai. Dobara login karne par (naye run,
/// web, naya phone, reinstall) wahi list wapas aa jati hai.
///
/// PREMIUM: Free user ke liye [PremiumService.freeDownloadLimit] tak downloads.
/// - UI se download karne ke liye [downloadWithGate] / [downloadAllWithGate]
///   use karein (limit par premium sheet khud khulti hai).
/// - Seedha [download] bhi limit ko bypass nahi kar sakta.
class DownloadService extends ChangeNotifier {
  // Pehli baar use hote hi saved downloads khud load ho jate hain.
  DownloadService._() {
    init();
  }

  static final DownloadService instance = DownloadService._();

  static const String _prefsKey = 'downloads_v1';

  /// Local list kis account ki hai (uid). Account badalne par list alag rakhne ke liye.
  static const String _ownerKey = 'downloads_owner_uid';

  final List<DownloadedSong> _items = [];
  final Map<String, double> _progress = {};
  final Map<String, Song> _activeSongs = {};
  bool _loaded = false;
  Directory? _dirCache;

  StreamSubscription<User?>? _authSub;
  String? _syncedUid;
  int _syncRetries = 0;

  /// true agar aakhri download() free limit ki wajah se roka gaya.
  bool lastBlockedByLimit = false;

  List<DownloadedSong> get items => List.unmodifiable(_items);
  Map<String, double> get active => Map.unmodifiable(_progress);
  int get totalBytes => _items.fold(0, (sum, e) => sum + e.bytes);

  /// Saved + abhi chal rahe downloads (limit isi par check hoti hai).
  int get usedSlots => _items.length + _progress.length;

  /// Free user ki limit poori ho chuki hai?
  bool get limitReached => !PremiumService.instance.canDownload(usedSlots);

  /// Free user ke kitne downloads baaki hain (premium ke liye bohot bada number).
  int get slotsLeft => PremiumService.instance.isPremium
      ? 1 << 30
      : (PremiumService.freeDownloadLimit - usedSlots)
          .clamp(0, PremiumService.freeDownloadLimit);

  /// Kitne gaane list mein hain lekin is device par file nahi (sirf cloud list).
  int get cloudOnlyCount => _items.where((e) => e.isCloudOnly).length;

  bool isDownloaded(String id) => _items.any((e) => e.song.id == id);
  double? progressOf(String id) => _progress[id];
  Song? activeSong(String id) => _activeSongs[id];

  // ---------------------------------------------------------------------------
  // Load / save
  // ---------------------------------------------------------------------------

  Future<Directory> _dir() async {
    final cached = _dirCache;
    if (cached != null) return cached;

    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/melodyhub_downloads');
    if (!await d.exists()) await d.create(recursive: true);
    _dirCache = d;
    return d;
  }

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);

      if (raw != null && raw.isNotEmpty) {
        final dir = kIsWeb ? null : await _dir();
        final list = jsonDecode(raw);

        if (list is List) {
          for (final e in list) {
            if (e is! Map) continue;

            final songMap = e['song'];
            if (songMap is! Map) continue;

            final fileName = e['fileName'] as String?;
            String? path;

            if (!kIsWeb && fileName != null && dir != null) {
              path = '${dir.path}/$fileName';
              // File delete ho chuki ho to list se hata do.
              if (!File(path).existsSync()) continue;
            }

            _items.add(
              DownloadedSong(
                song: songFromMap(songMap),
                fileName: fileName,
                path: path,
                bytes: (e['bytes'] as num?)?.toInt() ?? 0,
                savedAt: (e['savedAt'] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Downloads load failed: $e');
    }

    notifyListeners();

    // Login / logout par cloud sync khud chalega.
    try {
      _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    } catch (e) {
      debugPrint('Downloads auth listen failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_items.map((e) => e.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('Downloads save failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud backup (Firestore: users/{uid}/downloads/{songId})
  // ---------------------------------------------------------------------------

  /// Guest (anonymous) ke liye cloud backup nahi.
  String? get _uid {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null || u.isAnonymous) return null;
      return u.uid;
    } catch (_) {
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('downloads');

  Future<void> _cloudPut(DownloadedSong item) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _col(uid).doc(_safeName(item.song.id)).set(<String, dynamic>{
        'song': songToMap(item.song),
        'bytes': item.bytes,
        'savedAt': item.savedAt,
      });
    } catch (e) {
      debugPrint('Cloud save failed: $e');
    }
  }

  Future<void> _cloudDelete(String id) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _col(uid).doc(_safeName(id)).delete();
    } catch (e) {
      debugPrint('Cloud delete failed: $e');
    }
  }

  void _onAuth(User? user) {
    if (user == null) {
      // Logout: list/files ko haath nahi lagate. Dobara login par sync phir chalega.
      _syncedUid = null;
      return;
    }
    if (user.isAnonymous) return;
    if (_syncedUid == user.uid) return;

    _syncedUid = user.uid;
    unawaited(_syncWithCloud(user.uid));
  }

  /// Device par us user ki file dhoondta hai (naam: <safeId>.<ext>).
  File? _findFile(Directory dir, String id) {
    final prefix = '${_safeName(id)}.';
    try {
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (name.startsWith(prefix) && e.lengthSync() > 0) return e;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _syncWithCloud(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(_ownerKey);

      // Dusra account login hua: purane account ki local list hata do
      // (files disk par rehti hain, aur us account ki list uske cloud mein hai).
      // owner == null matlab purana data (cloud se pehle ka): pehle login karne
      // wale account ka maan lete hain, kuch delete nahi hota.
      if (owner != null && owner != uid) {
        _items.clear();
        await _save();
        notifyListeners();
      }
      await prefs.setString(_ownerKey, uid);

      final snap = await _col(uid).get();
      _syncRetries = 0; // cloud se baat ho gayi
      final dir = kIsWeb ? null : await _dir();
      final cloudIds = <String>{};
      var changed = false;

      for (final d in snap.docs) {
        final data = d.data();
        final songMap = data['song'];
        if (songMap is! Map) continue;

        final song = songFromMap(songMap);
        cloudIds.add(song.id);
        if (isDownloaded(song.id)) continue;

        String? fileName;
        String? path;

        // Is device par file pehle se hai to seedha jod do (offline chalega).
        if (dir != null) {
          final f = _findFile(dir, song.id);
          if (f != null) {
            fileName = f.uri.pathSegments.last;
            path = f.path;
          }
        }

        _items.add(
          DownloadedSong(
            song: song,
            fileName: fileName,
            path: path,
            bytes: (data['bytes'] as num?)?.toInt() ?? 0,
            savedAt: (data['savedAt'] as num?)?.toInt() ?? 0,
          ),
        );
        changed = true;
      }

      // Jo gaane sirf local hain (cloud se pehle ke), unhein cloud par daal do.
      for (final item in List<DownloadedSong>.of(_items)) {
        if (!cloudIds.contains(item.song.id)) {
          await _cloudPut(item);
        }
      }

      if (changed) {
        _items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
        await _save();
        notifyListeners();
      }
    } catch (e) {
      // Offline ya rules ka masla: app normal chalti rahe, agle login par phir try hoga.
      _syncedUid = null;
      debugPrint('Downloads cloud sync failed: $e');
      _scheduleSyncRetry(uid);
    }
  }

  /// Sync fail ho (offline / rules) to thori der baad khud dobara koshish (3 baar tak).
  void _scheduleSyncRetry(String uid) {
    if (_syncRetries >= 3) return;
    _syncRetries++;
    Future<void>.delayed(Duration(seconds: 10 * _syncRetries), () {
      if (_uid != uid || _syncedUid != null) return;
      _syncedUid = uid;
      unawaited(_syncWithCloud(uid));
    });
  }

  /// Haath se cloud se dobara list mangwane ke liye (jaise Refresh button).
  Future<void> refreshFromCloud() async {
    final uid = _uid;
    if (uid == null) return;
    _syncRetries = 0;
    _syncedUid = uid;
    await _syncWithCloud(uid);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _safeName(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  String _ext(String url) {
    try {
      final path = Uri.parse(url).path;
      final dot = path.lastIndexOf('.');
      if (dot != -1) {
        final ext = path.substring(dot + 1).toLowerCase();
        if (const ['mp3', 'm4a', 'aac', 'ogg', 'wav'].contains(ext)) return ext;
      }
    } catch (_) {}
    return 'mp3';
  }

  /// Download ke liye asal, taaza URL nikalta hai.
  Future<String> _resolveUrl(Song song) async {
    var url = song.audioUrl;

    if (url.contains('api.audius.co')) {
      url = await AudiusService.instance.resolveStreamUrl(song.id);
    } else if (song.id.startsWith('deezer_')) {
      final fresh = await DeezerService.instance.freshPreview(song.id);
      if (fresh != null && fresh.isNotEmpty) url = fresh;
    }

    return url;
  }

  // ---------------------------------------------------------------------------
  // Premium gate (UI se ye use karein)
  // ---------------------------------------------------------------------------

  /// Download button par ye call karein:
  ///   DownloadService.instance.downloadWithGate(context, song)
  /// Limit poori ho to premium sheet khulti hai aur false milta hai.
  Future<bool> downloadWithGate(BuildContext context, Song song) async {
    if (isDownloaded(song.id)) return true;
    if (!PremiumGate.download(context, usedSlots)) return false;
    return download(song);
  }

  /// "Download all" button par:
  ///   DownloadService.instance.downloadAllWithGate(context, songs)
  /// Jitne free slots hain utne download hote hain, phir premium sheet khulti hai.
  Future<int> downloadAllWithGate(BuildContext context, List<Song> songs) async {
    var ok = 0;

    for (final s in songs) {
      if (isDownloaded(s.id)) continue;

      if (limitReached) {
        if (context.mounted) {
          showPremiumSheet(context, reason: PremiumReason.downloads);
        }
        break;
      }

      if (await download(s)) ok++;
    }

    return ok;
  }

  // ---------------------------------------------------------------------------
  // Download / delete
  // ---------------------------------------------------------------------------

  /// true = download ho gaya.
  /// NOTE: Free limit yahan bhi check hoti hai, taake koi screen bypass na kar sake.
  Future<bool> download(Song song) async {
    final id = song.id;
    lastBlockedByLimit = false;

    if (id.isEmpty) return false;
    if (isDownloaded(id)) return true;
    if (_progress.containsKey(id)) return false; // pehle se chal raha hai

    // Free limit: saved + abhi chal rahe downloads gin kar check.
    if (!PremiumService.instance.canDownload(usedSlots)) {
      lastBlockedByLimit = true;
      return false;
    }

    _progress[id] = 0;
    _activeSongs[id] = song;
    notifyListeners();

    try {
      final url = await _resolveUrl(song);
      if (url.trim().isEmpty) throw Exception('Audio URL nahi mila');

      String? fileName;
      String? path;
      var bytes = 0;

      if (!kIsWeb) {
        final dir = await _dir();
        fileName = '${_safeName(id)}.${_ext(url)}';
        final file = File('${dir.path}/$fileName');

        final client = http.Client();
        try {
          final res = await client
              .send(http.Request('GET', Uri.parse(url)))
              .timeout(const Duration(seconds: 30));

          if (res.statusCode != 200) {
            throw Exception('HTTP ${res.statusCode}');
          }

          final total = res.contentLength ?? 0;
          var received = 0;
          final sink = file.openWrite();

          try {
            await for (final chunk in res.stream) {
              sink.add(chunk);
              received += chunk.length;

              if (total > 0) {
                _progress[id] = received / total;
                notifyListeners();
              }
            }
          } finally {
            await sink.close();
          }

          bytes = received;
        } catch (e) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          rethrow;
        } finally {
          client.close();
        }

        if (bytes == 0) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          throw Exception('Khali file mili');
        }

        path = file.path;
      }

      _items.removeWhere((e) => e.song.id == id);
      final item = DownloadedSong(
        song: song,
        fileName: fileName,
        path: path,
        bytes: bytes,
        savedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _items.insert(0, item);

      await _save();
      unawaited(_cloudPut(item)); // cloud backup (fail ho to bhi download theek hai)
      return true;
    } catch (e) {
      debugPrint('Download failed (${song.title}): $e');
      return false;
    } finally {
      _progress.remove(id);
      _activeSongs.remove(id);
      notifyListeners();
    }
  }

  /// Poori list download karo (ek ek karke). Kitne successful hue wo return.
  /// Free limit par ruk jata hai. UI se [downloadAllWithGate] behtar hai.
  Future<int> downloadAll(List<Song> songs) async {
    var ok = 0;
    for (final s in songs) {
      if (isDownloaded(s.id)) continue;
      if (await download(s)) {
        ok++;
      } else if (lastBlockedByLimit) {
        break;
      }
    }
    return ok;
  }

  /// Cloud list se aaye hue gaane (file nahi) ko is device par dobara download karo.
  /// Fail ho to list mein wahi purani entry wapas aa jati hai.
  Future<bool> redownload(String id) async {
    final i = _items.indexWhere((e) => e.song.id == id);
    if (i == -1) return false;

    final old = _items[i];
    if (!old.isCloudOnly) return true;

    _items.removeAt(i);
    notifyListeners();

    final ok = await download(old.song);
    if (!ok && !isDownloaded(id)) {
      _items.insert(math.min(i, _items.length), old);
      notifyListeners();
    }
    return ok;
  }

  /// Saare cloud-only gaane dobara download karo. Kitne hue wo return.
  Future<int> redownloadAll() async {
    final ids = _items.where((e) => e.isCloudOnly).map((e) => e.song.id).toList();
    var ok = 0;
    for (final id in ids) {
      if (await redownload(id)) ok++;
    }
    return ok;
  }

  Future<void> remove(String id) async {
    final index = _items.indexWhere((e) => e.song.id == id);
    if (index == -1) return;

    final item = _items.removeAt(index);

    if (!kIsWeb && item.path != null) {
      try {
        final f = File(item.path!);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('File delete failed: $e');
      }
    }

    await _save();
    unawaited(_cloudDelete(id));
    notifyListeners();
  }

  Future<void> clearAll() async {
    final ids = _items.map((e) => e.song.id).toList();
    for (final id in ids) {
      await remove(id);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}