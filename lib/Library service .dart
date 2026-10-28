import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundclock/song.dart';
import 'package:soundclock/song_json.dart';

/// Liked songs, user playlists aur recent searches.
///
/// - Phone me bhi save hote hain (offline chalne ke liye).
/// - Login hone par Firestore (users/{uid}/data/library) se sync hote hain,
///   to naye phone ya naye app me wahi Google account se login karne par
///   data wapas aa jata hai.
/// - Har account ka local data alag rehta hai (account badalne par mix nahi hota).
class LibraryService extends ChangeNotifier {
  // Pehli baar use hote hi login ki halat sun'na shuru ho jata hai.
  LibraryService._() {
    init();
  }

  static final LibraryService instance = LibraryService._();

  /// Purani (login se pehle wali) key. Pehle login par iska data cloud par
  /// chala jata hai, phir ye hat jati hai.
  static const String _legacyKey = 'library_v1';

  final List<Song> _liked = [];
  final Map<String, List<Song>> _playlists = {};
  final List<String> _recent = [];

  bool _inited = false;
  String? _uid;
  int _gen = 0; // account badalne par purane async kaam ko rokne ke liye

  List<Song> get liked => List.unmodifiable(_liked);
  Map<String, List<Song>> get playlists => Map.unmodifiable(_playlists);
  List<String> get recentSearches => List.unmodifiable(_recent);

  bool isLiked(String id) => _liked.any((s) => s.id == id);

  bool get _isEmpty => _liked.isEmpty && _playlists.isEmpty && _recent.isEmpty;

  // ---------------------------------------------------------------------------
  // Start / account badalna
  // ---------------------------------------------------------------------------

  /// Dobara call karne se koi masla nahi, ek hi baar chalta hai.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      FirebaseAuth.instance
          .authStateChanges()
          .listen((user) => _switchUser(user?.uid));
    } catch (e) {
      debugPrint('Library auth listen failed: $e');
      await _switchUser(null);
    }
  }

  Future<void> _switchUser(String? uid) async {
    final gen = ++_gen;
    _uid = uid;

    _clearAll();
    await _loadLocal(uid);
    if (gen != _gen) return;
    notifyListeners();

    if (uid != null) await _syncFromCloud(uid, gen);
  }

  void _clearAll() {
    _liked.clear();
    _playlists.clear();
    _recent.clear();
  }

  // ---------------------------------------------------------------------------
  // Map <-> lists
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _toMap() => <String, dynamic>{
        'liked': _liked.map(songToMap).toList(),
        'playlists': [
          for (final e in _playlists.entries)
            {'name': e.key, 'songs': e.value.map(songToMap).toList()},
        ],
        'recent': List<String>.from(_recent),
      };

  void _applyMap(Map data) {
    final liked = data['liked'];
    if (liked is List) {
      for (final e in liked) {
        if (e is Map) _liked.add(songFromMap(e));
      }
    }

    final playlists = data['playlists'];
    if (playlists is List) {
      // Naya format: [{name, songs}]
      for (final p in playlists) {
        if (p is! Map) continue;
        final name = p['name']?.toString() ?? '';
        final songs = p['songs'];
        if (name.isEmpty || songs is! List) continue;
        _playlists[name] = [
          for (final e in songs)
            if (e is Map) songFromMap(e),
        ];
      }
    } else if (playlists is Map) {
      // Purana format: {name: [songs]}
      playlists.forEach((name, songs) {
        if (songs is! List) return;
        _playlists[name.toString()] = [
          for (final e in songs)
            if (e is Map) songFromMap(e),
        ];
      });
    }

    final recent = data['recent'];
    if (recent is List) {
      _recent.addAll(recent.map((e) => e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Local save / load (phone)
  // ---------------------------------------------------------------------------

  String _localKey(String? uid) =>
      uid == null ? _legacyKey : 'library_v2_$uid';

  Future<void> _loadLocal(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localKey(uid));
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) _applyMap(data);
      }
    } catch (e) {
      debugPrint('Library local load failed: $e');
    }
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localKey(_uid), jsonEncode(_toMap()));
    } catch (e) {
      debugPrint('Library local save failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud (Firestore)
  // ---------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _doc(String uid) => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('data')
      .doc('library');

  Future<void> _syncFromCloud(String uid, int gen) async {
    try {
      final snap = await _doc(uid).get();
      if (gen != _gen) return;

      final data = snap.data();
      if (snap.exists && data != null) {
        // Cloud me data hai: wahi sahi maana jata hai.
        _clearAll();
        _applyMap(data);
        await _saveLocal();
        if (gen != _gen) return;
        notifyListeners();
      } else {
        // Is account ka pehla sync: login se pehle ka phone ka data cloud par bhej do.
        if (_isEmpty) await _importLegacy();
        if (gen != _gen) return;
        if (!_isEmpty) {
          await _pushCloud(uid);
          await _removeLegacy();
          await _saveLocal();
          notifyListeners();
        }
      }
    } catch (e) {
      // Internet na ho to phone wala data hi chalta rahega.
      debugPrint('Library cloud sync failed: $e');
    }
  }

  Future<void> _pushCloud(String uid) async {
    try {
      await _doc(uid).set(_toMap());
    } catch (e) {
      debugPrint('Library cloud save failed: $e');
    }
  }

  Future<void> _importLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) _applyMap(data);
      }
    } catch (e) {
      debugPrint('Library legacy import failed: $e');
    }
  }

  Future<void> _removeLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyKey);
    } catch (_) {}
  }

  void _changed() {
    notifyListeners();
    _saveLocal();
    final uid = _uid;
    if (uid != null) _pushCloud(uid);
  }

  // ---------------------------------------------------------------------------
  // Liked songs
  // ---------------------------------------------------------------------------

  void toggleLike(Song song) {
    if (isLiked(song.id)) {
      _liked.removeWhere((s) => s.id == song.id);
    } else {
      _liked.insert(0, song);
    }
    _changed();
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  /// false = naam khali hai ya pehle se maujood hai.
  bool createPlaylist(String name) {
    final n = name.trim();
    if (n.isEmpty || _playlists.containsKey(n)) return false;

    _playlists[n] = [];
    _changed();
    return true;
  }

  void deletePlaylist(String name) {
    if (_playlists.remove(name) != null) _changed();
  }

  /// false = gaana pehle se playlist mein hai.
  bool addToPlaylist(String name, Song song) {
    final list = _playlists[name];
    if (list == null) return false;
    if (list.any((s) => s.id == song.id)) return false;

    list.add(song);
    _changed();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Recent searches
  // ---------------------------------------------------------------------------

  void addRecentSearch(String query) {
    final q = query.trim();
    if (q.length < 2) return;

    _recent.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    _recent.insert(0, q);
    if (_recent.length > 10) _recent.removeRange(10, _recent.length);
    _changed();
  }

  void removeRecentSearch(String query) {
    _recent.remove(query);
    _changed();
  }

  void clearRecentSearches() {
    if (_recent.isEmpty) return;
    _recent.clear();
    _changed();
  }
}