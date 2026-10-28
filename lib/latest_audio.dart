import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:soundclock/Api%20client.dart';
import 'package:soundclock/jsonp.dart';
import 'package:soundclock/song.dart';

/// Home screen ke liye: audio ke latest Bollywood / Pakistani / English gaane.
class LatestAudio {
  final List<Song> bollywood;
  final List<Song> pakistani;
  final List<Song> english;

  const LatestAudio({
    required this.bollywood,
    required this.pakistani,
    this.english = const [],
  });

  bool get isEmpty => bollywood.isEmpty && pakistani.isEmpty && english.isEmpty;
}

class _Dated {
  final Song song;
  final DateTime released;
  const _Dated(this.song, this.released);
}

class LatestAudioService {
  LatestAudioService._();

  static final LatestAudioService instance = LatestAudioService._();

  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _cacheTtl = Duration(minutes: 30);

  LatestAudio? _cache;
  DateTime? _cacheTime;

  String? lastError;

  static const List<String> _pakistaniArtists = [
    'atif aslam',
    'rahat fateh ali khan',
    'asim azhar',
    'ali zafar',
    'nusrat fateh ali khan',
    'abida parveen',
    'hasan raheem',
    'ali sethi',
    'shae gill',
    'talha anjum',
    'farhan saeed',
    'momina mustehsan',
    'bilal saeed',
    'junaid jamshed',
    'kaifi khalil',
    'young stunners',
  ];

  static const List<String> _bollywoodArtists = [
    'arijit singh',
    'jubin nautiyal',
    'shreya ghoshal',
    'sonu nigam',
    'neha kakkar',
    'badshah',
    'armaan malik',
    'darshan raval',
    'b praak',
    'vishal mishra',
    'kk',
    'sunidhi chauhan',
  ];

  // Agar backend kabhi English artists bhi de, to wo English tab mein jayenge.
  static const List<String> _englishArtists = [
    'taylor swift',
    'the weeknd',
    'dua lipa',
    'ed sheeran',
    'billie eilish',
    'ariana grande',
    'bruno mars',
    'post malone',
    'sabrina carpenter',
    'olivia rodrigo',
    'justin bieber',
    'harry styles',
  ];

  // ---------------------------------------------------------------------------
  // Public
  // ---------------------------------------------------------------------------

  Future<LatestAudio> fetch({bool force = false}) async {
    final c = _cache;
    final t = _cacheTime;
    if (!force &&
        c != null &&
        t != null &&
        DateTime.now().difference(t) < _cacheTtl) {
      return c;
    }

    LatestAudio data = const LatestAudio(bollywood: [], pakistani: []);
    lastError = null;

    // 1. Backend (Bollywood / Pakistani)
    if (ApiClient.instance.enabled) {
      try {
        data = await _fromBackend();
        if (data.isEmpty) {
          lastError =
              'Backend ne 0 gaane diye (ya sab artist-filter se hat gaye). '
              'Backend terminal ki warnings dekho.';
        }
      } catch (e) {
        debugPrint('LatestAudio backend failed: $e');
        lastError = 'Backend call fail: $e';
      }
    } else {
      lastError = 'ApiClient.instance.enabled = false (backend URL set nahi).';
    }

    // 2. Bollywood / Pakistani ka purana iTunes fallback
    if ((data.bollywood.isEmpty && data.pakistani.isEmpty) &&
        ApiClient.directFallback &&
        !kIsWeb) {
      final it = await _fromItunes();
      data = LatestAudio(
        bollywood: it.bollywood,
        pakistani: it.pakistani,
        english: data.english,
      );
    }

    // 3. English: backend se kam mile to iTunes (US store) se.
    if (data.english.length < 8) {
      try {
        final en = await _collect(_englishTerms, country: 'us');
        data = LatestAudio(
          bollywood: data.bollywood,
          pakistani: data.pakistani,
          english: en,
        );
      } catch (e) {
        debugPrint('LatestAudio english failed: $e');
      }
    }

    if (!data.isEmpty) {
      lastError = null;
      _cache = data;
      _cacheTime = DateTime.now();
    }
    return data;
  }

  // ---------------------------------------------------------------------------
  // Backend
  // ---------------------------------------------------------------------------

  Future<LatestAudio> _fromBackend() async {
    final songs = await ApiClient.instance.songs('/home/fresh');

    final bolly = <Song>[];
    final pak = <Song>[];
    final eng = <Song>[];
    var dropped = 0;

    for (final s in songs) {
      final artist = s.artist.split(' • ').first.trim().toLowerCase();

      if (_pakistaniArtists.any((a) => artist.contains(a))) {
        pak.add(s);
      } else if (_bollywoodArtists.any((a) => artist.contains(a))) {
        bolly.add(s);
      } else if (_englishArtists.any((a) => artist.contains(a))) {
        eng.add(s);
      } else {
        dropped++;
        debugPrint('LatestAudio dropped (unknown artist): ${s.artist}');
      }
    }

    debugPrint(
      'LatestAudio backend: ${songs.length} songs '
      '(Bollywood ${bolly.length}, Pakistani ${pak.length}, '
      'English ${eng.length}, dropped $dropped)',
    );

    return LatestAudio(bollywood: bolly, pakistani: pak, english: eng);
  }

  // ---------------------------------------------------------------------------
  // iTunes
  // ---------------------------------------------------------------------------

  static List<String> get _bollywoodTerms {
    final y = DateTime.now().year;
    return [
      'new hindi songs $y',
      'bollywood $y',
      'new bollywood songs',
      'arijit singh',
      'pritam',
      'shreya ghoshal',
      'sachet parampara',
      'vishal mishra',
      'jubin nautiyal',
    ];
  }

  static List<String> get _pakistaniTerms {
    final y = DateTime.now().year;
    return [
      'new pakistani songs $y',
      'coke studio pakistan',
      'atif aslam',
      'asim azhar',
      'hasan raheem',
      'talha anjum',
      'abdul hannan',
      'rahat fateh ali khan',
      'ali zafar',
    ];
  }

  static List<String> get _englishTerms {
    final y = DateTime.now().year;
    return [
      'new english songs $y',
      'top pop hits $y',
      'taylor swift',
      'the weeknd',
      'dua lipa',
      'ed sheeran',
      'billie eilish',
      'ariana grande',
      'sabrina carpenter',
      'bruno mars',
    ];
  }

  Future<LatestAudio> _fromItunes() async {
    final res = await Future.wait([
      _collect(_bollywoodTerms),
      _collect(_pakistaniTerms),
    ]);
    return LatestAudio(bollywood: res[0], pakistani: res[1]);
  }

  Future<List<Song>> _collect(
    List<String> terms, {
    int max = 25,
    String country = 'in',
  }) async {
    final batches = await Future.wait(terms.map((t) => _search(t, country)));

    final seenIds = <String>{};
    final seenTitles = <String>{};
    final all = <_Dated>[];

    for (final batch in batches) {
      for (final d in batch) {
        final title = d.song.title.trim().toLowerCase();
        if (seenIds.contains(d.song.id) || seenTitles.contains(title)) {
          continue;
        }
        seenIds.add(d.song.id);
        seenTitles.add(title);
        all.add(d);
      }
    }

    all.sort((a, b) => b.released.compareTo(a.released));

    final now = DateTime.now();
    var recent =
        all.where((d) => now.difference(d.released).inDays <= 120).toList();

    if (recent.length < 8) {
      recent =
          all.where((d) => now.difference(d.released).inDays <= 365).toList();
    }

    return recent.take(max).map((d) => d.song).toList();
  }

  Future<List<_Dated>> _search(String term, String country) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': 'song',
      'country': country,
      'limit': '50',
    });

    try {
      final Object? decoded;

      if (kIsWeb) {
        decoded = await jsonpGet(uri);
      } else {
        final response = await http
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(_timeout);

        if (response.statusCode != 200) {
          debugPrint('LatestAudio HTTP ${response.statusCode} ($term)');
          return [];
        }
        decoded = jsonDecode(response.body);
      }

      if (decoded is! Map) return [];
      final results = decoded['results'];
      if (results is! List) return [];

      final out = <_Dated>[];

      for (final item in results) {
        if (item is! Map) continue;

        final preview = (item['previewUrl'] ?? '').toString();
        final title = (item['trackName'] ?? '').toString();
        final released =
            DateTime.tryParse((item['releaseDate'] ?? '').toString());

        if (preview.isEmpty || title.trim().isEmpty || released == null) {
          continue;
        }
        if (released.isAfter(DateTime.now().add(const Duration(days: 1)))) {
          continue;
        }

        final art = (item['artworkUrl100'] ?? '').toString();

        out.add(
          _Dated(
            Song(
              id: 'itunes_${item['trackId'] ?? ''}',
              title: title,
              artist: '${item['artistName'] ?? 'Unknown'} • Preview',
              imageUrl: art.replaceAll(RegExp(r'\d+x\d+bb'), '300x300bb'),
              audioUrl: preview,
              durationSec: 30,
            ),
            released,
          ),
        );
      }

      return out;
    } catch (e) {
      debugPrint('LatestAudio failed ($term): $e');
      return [];
    }
  }
}