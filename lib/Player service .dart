import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:soundclock/audius_service.dart';
import 'package:soundclock/deezer_service.dart';
import 'package:soundclock/download_service.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/song.dart';

/// Poori app mein ek hi player. Queue, next/previous, recent history yahin hai.
class PlayerService {
  PlayerService._() {
    // Premium ki halat app shuru hote hi load ho, aur premium khatam hote hi
    // chalta hua sleep timer band ho jaye.
    PremiumService.instance.init();
    PremiumService.instance.addListener(() {
      if (!PremiumService.instance.isPremium) cancelSleepTimer();
    });

    // Gaana khatam hone par agla gaana chalao (ye skip count nahi hota).
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(_playIndex(_index + 1));
      }
    });
  }

  static final PlayerService instance = PlayerService._();

  final AudioPlayer player = AudioPlayer();

  final ValueNotifier<Song?> current = ValueNotifier<Song?>(null);

  final ValueNotifier<List<Song>> recent = ValueNotifier<List<Song>>([]);

  /// Playback error message (UI snackbar ke liye).
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// true = gaana device ki downloaded file se chal raha hai (internet nahi chahiye).
  final ValueNotifier<bool> isOffline = ValueNotifier<bool>(false);

  // ---------------------------------------------------------------------------
  // Premium: skip limit + sleep timer
  // ---------------------------------------------------------------------------

  /// Free user ke liye ek ghante me kitne manual skip.
  static const int freeSkipsPerHour = 6;

  final ValueNotifier<int> upgradeRequests = ValueNotifier<int>(0);
  String upgradeReason = '';

  /// Sleep timer me kitna waqt bacha hai (null = timer band).
  final ValueNotifier<Duration?> sleepRemaining =
      ValueNotifier<Duration?>(null);

  Timer? _sleepTimer;
  final List<DateTime> _skipTimes = [];

  void _requestUpgrade(String reason) {
    upgradeReason = reason;
    upgradeRequests.value++;
  }

  void _pruneSkips() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    _skipTimes.removeWhere((t) => t.isBefore(cutoff));
  }

  /// Free user ke kitne skip bache hain. Premium ke liye -1 (unlimited).
  int get skipsLeft {
    if (PremiumService.instance.isPremium) return -1;
    _pruneSkips();
    return (freeSkipsPerHour - _skipTimes.length).clamp(0, freeSkipsPerHour);
  }

  /// Sleep timer shuru karo. Premium na ho to false aur upgrade request.
  bool startSleepTimer(Duration duration) {
    if (!PremiumService.instance.isPremium) {
      _requestUpgrade('Sleep timer Premium me milta hai.');
      return false;
    }

    cancelSleepTimer();
    var left = duration;
    sleepRemaining.value = left;

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      left -= const Duration(seconds: 1);
      if (left <= Duration.zero) {
        cancelSleepTimer();
        unawaited(player.pause());
      } else {
        sleepRemaining.value = left;
      }
    });
    return true;
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepRemaining.value = null;
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  List<Song> _queue = const [];
  int _index = 0;

  int _failures = 0;
  static const int _maxFailures = 5;
  int _playToken = 0; // purane async calls ko ignore karne ke liye

  Future<void> playQueue(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    _queue = List<Song>.of(songs);
    _failures = 0;
    await _playIndex(index);
  }

  Future<void> _playIndex(int index) async {
    if (_queue.isEmpty) return;

    _index = (index % _queue.length + _queue.length) % _queue.length;
    final song = _queue[_index];
    final token = ++_playToken;

    current.value = song;
    error.value = null;

    debugPrint('Song title: ${song.title}');
    debugPrint('Audio URL: ${song.audioUrl}');

    if (song.audioUrl.trim().isEmpty) {
      debugPrint('ERROR: Audio URL is empty');
      await _safeStop();
      _handleFailure();
      return;
    }

    try {
      // Pehle purani awaz band karo, taake naya gaana load na ho to
      // purana gaana chalta na rahe.
      await player.stop();
      if (token != _playToken) return;

      // Audius ka redirect wala URL seedhe asal stream URL mein badlo.
      var url = song.audioUrl;
      final local = _localPathFor(song.id);
      isOffline.value = local != null;
      debugPrint(local != null
          ? 'PLAYING OFFLINE FILE: $local'
          : 'STREAMING (no local file for id ${song.id})');
      if (local != null) {
        // Downloaded hai: file se chalao, internet nahi chahiye.
        url = Uri.file(local).toString();
      } else if (url.contains('api.audius.co')) {
        url = await AudiusService.instance.resolveStreamUrl(song.id);
        if (token != _playToken) return;
      } else if (song.id.startsWith('deezer_') && url.startsWith('http')) {
        // Deezer ka URL expire ho sakta hai (saved gaanon ke liye), taaza lo.
        final fresh = await DeezerService.instance.freshPreview(song.id);
        if (token != _playToken) return;
        if (fresh != null && fresh.isNotEmpty) url = fresh;
      }
      debugPrint('Resolved URL: $url');

      await player.setUrl(url);
      if (token != _playToken) return;

      _failures = 0;
      _addRecent(song);

      // play() ka future gaana khatam hone tak complete nahi hota,
      // isliye ise await nahi karte.
      unawaited(player.play());
    } catch (e, st) {
      if (token != _playToken) return;

      debugPrint('PLAYBACK ERROR: $e');
      debugPrint('STACK TRACE: $st');

      await _safeStop();
      _handleFailure();
    }
  }

  /// Downloaded gaane ka local file path (na mile to null). Web par hamesha null.
  String? _localPathFor(String id) {
    if (kIsWeb) return null;
    for (final d in DownloadService.instance.items) {
      final p = d.path;
      if (d.song.id == id && p != null && File(p).existsSync()) return p;
    }
    return null;
  }

  Future<void> _safeStop() async {
    try {
      await player.stop();
    } catch (_) {}
  }

  void _handleFailure() {
    _failures++;
    if (_failures >= _maxFailures || _failures >= _queue.length) {
      _failures = 0;
      error.value =
          'Gaane nahi chal pa rahe. Internet check karein ya baad mein try karein.';
      return;
    }
    // Broken track skip karke agla chalao.
    unawaited(_playIndex(_index + 1));
  }

  void _addRecent(Song song) {
    final list = List<Song>.of(recent.value)
      ..removeWhere((s) => s.id == song.id)
      ..insert(0, song);
    recent.value = list.length > 15 ? list.sublist(0, 15) : list;
  }

  /// User ka manual "next" (button). Free user ke liye limit lagti hai.
  Future<void> next() async {
    debugPrint('NEXT pressed | premium=${PremiumService.instance.isPremium} '
        '| skips used=${_skipTimes.length}/$freeSkipsPerHour');
    if (!PremiumService.instance.isPremium) {
      _pruneSkips();
      if (_skipTimes.length >= freeSkipsPerHour) {
        _requestUpgrade(
          'Free plan me ek ghante me $freeSkipsPerHour skip milte hain. '
          'Unlimited skip ke liye Premium lein.',
        );
        return;
      }
      _skipTimes.add(DateTime.now());
    }
    await _playIndex(_index + 1);
  }

  Future<void> previous() async {
    // 3 second se zyada chal chuka ho to usi gaane ko shuru se chalao.
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
    } else {
      await _playIndex(_index - 1);
    }
  }

  void togglePlay() {
    if (player.playing) {
      unawaited(player.pause());
    } else {
      unawaited(player.play());
    }
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> stop() async {
    cancelSleepTimer();
    await player.stop();
    current.value = null;
  }
}