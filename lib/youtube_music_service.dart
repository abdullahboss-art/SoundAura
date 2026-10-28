import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:soundclock/Api%20client.dart';

String _decodeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

class YouTubeSong {
  final String videoId;
  final String title;
  final String channel;
  final String thumbnailUrl;

  const YouTubeSong({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.thumbnailUrl,
  });

  /// Search result (id = {videoId: ..}) aur videos.list (id = "abc") dono ke liye.
  factory YouTubeSong.fromJson(Map<String, dynamic> json) {
    final snippet = json['snippet'] as Map<String, dynamic>? ?? {};

    final rawId = json['id'];
    String videoId = '';
    if (rawId is Map<String, dynamic>) {
      videoId = (rawId['videoId'] ?? '').toString();
    } else if (rawId is String) {
      videoId = rawId;
    }

    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
    final thumbnail = (thumbnails['high'] ??
            thumbnails['medium'] ??
            thumbnails['default']) as Map<String, dynamic>? ??
        {};

    return YouTubeSong(
      videoId: videoId,
      title: _decodeHtml((snippet['title'] ?? 'Unknown title').toString()),
      channel:
          _decodeHtml((snippet['channelTitle'] ?? 'Unknown artist').toString()),
      thumbnailUrl: (thumbnail['url'] ?? '').toString(),
    );
  }
}

/// Home screen ke liye: India chart = Bollywood, Pakistan = Pakistani songs.
class LatestMusic {
  final List<YouTubeSong> bollywood;
  final List<YouTubeSong> pakistani;

  const LatestMusic({required this.bollywood, required this.pakistani});

  bool get isEmpty => bollywood.isEmpty && pakistani.isEmpty;
}

/// UI mein seedha dikhane layak error message.
class YouTubeApiException implements Exception {
  final String message;
  const YouTubeApiException(this.message);

  @override
  String toString() => message;
}

class _CacheEntry {
  final List<YouTubeSong> value;
  final DateTime time;
  _CacheEntry(this.value) : time = DateTime.now();
}

class YouTubeMusicService {
  YouTubeMusicService._();

  static final YouTubeMusicService instance = YouTubeMusicService._();

  // Key ko code mein hardcode mat karo. Run karte waqt do:
  //   flutter run --dart-define=YOUTUBE_API_KEY=your_new_key
  static const String _envKey = String.fromEnvironment('YOUTUBE_API_KEY');

  // Sirf testing ke liye: apni NAYI key yahan paste kar sakte ho
  // (git mein commit mat karna).
  static const String _fallbackKey = 'AIzaSyDmFyYaw0RN3YIKRh1V0MOhboUnzAGKM7c';

  String get _key => _envKey.isNotEmpty ? _envKey : _fallbackKey;

  static const String _host = 'www.googleapis.com';

  final Map<String, _CacheEntry> _cache = {};

  List<YouTubeSong>? _fromCache(String key, Duration ttl) {
    final e = _cache[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.time) > ttl) return null;
    return e.value;
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params,
  ) async {
    final key = _key;
    if (key.isEmpty) {
      throw const YouTubeApiException(
        'YouTube API key set nahi hai. --dart-define=YOUTUBE_API_KEY=... use karein.',
      );
    }

    final uri = Uri.https(_host, path, {...params, 'key': key});

    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        _throwApiError(response);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } on YouTubeApiException {
      rethrow;
    } catch (e) {
      debugPrint('YouTube network error: $e');
      throw const YouTubeApiException(
        'YouTube se connect nahi ho pa raha. Internet check karein.',
      );
    }
  }

  Never _throwApiError(http.Response r) {
    final body = r.body;
    debugPrint('YouTube API error ${r.statusCode}: $body');

    final String msg;
    if (body.contains('quotaExceeded') || body.contains('dailyLimitExceeded')) {
      msg = 'YouTube ka daily quota khatam ho gaya. Kal dobara chalega '
          '(ya Google Cloud mein quota badhwayein).';
    } else if (body.contains('BLOCKED')) {
      msg = 'API key ki restriction request ko block kar rahi hai. '
          'Google Cloud mein key ki Application restriction check karein.';
    } else if (body.contains('accessNotConfigured') ||
        body.contains('SERVICE_DISABLED')) {
      msg = 'Google Cloud project mein "YouTube Data API v3" enable nahi hai.';
    } else if (body.contains('API_KEY_INVALID') ||
        body.contains('keyInvalid')) {
      msg = 'YouTube API key galat hai.';
    } else {
      msg = 'YouTube API error (${r.statusCode}).';
    }

    throw YouTubeApiException(msg);
  }

  bool _valid(YouTubeSong s) =>
      s.videoId.isNotEmpty && s.title.trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // TRENDING / LATEST  (videos.list = sirf 1 quota unit, search = 100 units)
  // ---------------------------------------------------------------------------

  Future<List<YouTubeSong>> _mostPopular(String region,
      {int limit = 25}) async {
    final cacheKey = 'popular:$region:$limit';
    final cached = _fromCache(cacheKey, const Duration(minutes: 30));
    if (cached != null) return cached;

    final data = await _get('/youtube/v3/videos', {
      'part': 'snippet,status',
      'chart': 'mostPopular',
      'videoCategoryId': '10', // Music
      'regionCode': region,
      'maxResults': '$limit',
    });

    final items = data['items'] as List<dynamic>? ?? [];

    final videos = items
        .whereType<Map<String, dynamic>>()
        // Sirf wahi videos jo app ke andar embed ho sakti hain.
        .where((v) =>
            (v['status'] as Map<String, dynamic>?)?['embeddable'] != false)
        .map(YouTubeSong.fromJson)
        .where(_valid)
        .toList();

    _cache[cacheKey] = _CacheEntry(videos);
    return videos;
  }

  static const List<String> _skipTitleWords = [
    'reaction',
    'reacts',
    'karaoke',
    'instrumental',
    'tutorial',
    'status',
  ];

  /// Pakistani gaane: pichle ~4 mahine ke sabse zyada dekhe gaye music videos.
  /// (search = 100 quota units, isliye 60 minute cache.) Search na chale to
  /// Pakistan ka Music chart (1 unit) fallback hai.
  Future<List<YouTubeSong>> _pakistaniLatest({int limit = 25}) async {
    final cacheKey = 'pk-latest:$limit';
    final cached = _fromCache(cacheKey, const Duration(minutes: 60));
    if (cached != null) return cached;

    List<YouTubeSong> videos = [];

    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 45));
      final publishedAfter = '${since.toIso8601String().split('.').first}Z';

      final data = await _get('/youtube/v3/search', {
        'part': 'snippet',
        'type': 'video',
        'q': 'new pakistani song official music video',
        'maxResults': '$limit',
        'videoCategoryId': '10',
        'videoEmbeddable': 'true',
        'videoSyndicated': 'true',
        'regionCode': 'PK',
        'relevanceLanguage': 'ur',
        'order': 'viewCount',
        'publishedAfter': publishedAfter,
      });

      final items = data['items'] as List<dynamic>? ?? [];
      final seen = <String>{};

      videos = items
          .whereType<Map<String, dynamic>>()
          .map(YouTubeSong.fromJson)
          .where(_valid)
          .where((v) {
            final t = v.title.toLowerCase();
            return !_skipTitleWords.any(t.contains);
          })
          .where((v) => seen.add(v.videoId))
          .toList();
    } catch (e) {
      debugPrint('Pakistani search failed, chart fallback: $e');
    }

    if (videos.isEmpty) {
      videos = await _mostPopular('PK', limit: limit);
    }

    _cache[cacheKey] = _CacheEntry(videos);
    return videos;
  }

  List<YouTubeSong> _parseApi(Object? raw) {
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is Map)
          YouTubeSong(
            videoId: (e['videoId'] ?? '').toString(),
            title: (e['title'] ?? '').toString(),
            channel: (e['channel'] ?? '').toString(),
            thumbnailUrl: (e['thumbnailUrl'] ?? '').toString(),
          ),
    ].where(_valid).toList();
  }

  /// Pehle Python backend, wo na chale to seedha YouTube.
  Future<LatestMusic> fetchLatestMusic() async {
    if (ApiClient.instance.enabled) {
      try {
        final data = await ApiClient.instance.getJson('/videos/latest');
        return LatestMusic(
          bollywood: _parseApi(data['bollywood']),
          pakistani: _parseApi(data['pakistani']),
        );
      } on ApiException catch (e) {
        debugPrint('Backend latest failed: ${e.message}');
        if (!ApiClient.directFallback) throw YouTubeApiException(e.message);
      }
    }
    return _fetchLatestDirect();
  }

  /// Bollywood = India Music chart, Pakistani = Pakistani music videos.
  Future<LatestMusic> _fetchLatestDirect() async {
    Object? firstError;

    Future<List<YouTubeSong>> guarded(
      Future<List<YouTubeSong>> Function() load,
    ) async {
      try {
        return await load();
      } catch (e) {
        firstError ??= e;
        return <YouTubeSong>[];
      }
    }

    final res = await Future.wait([
      guarded(() => _mostPopular('IN')),
      guarded(() => _pakistaniLatest()),
    ]);

    if (res[0].isEmpty && res[1].isEmpty && firstError != null) {
      throw firstError!;
    }

    debugPrint(
      'Latest Music: Bollywood ${res[0].length}, Pakistani ${res[1].length}',
    );

    return LatestMusic(bollywood: res[0], pakistani: res[1]);
  }

  // ---------------------------------------------------------------------------
  // SEARCH  (100 quota units per search, isliye cache + debounce zaroori hai)
  // ---------------------------------------------------------------------------

  Future<List<YouTubeSong>> searchSongs(String query) async {
    final term = query.trim();
    if (term.length < 2) return [];

    if (ApiClient.instance.enabled) {
      try {
        final data =
            await ApiClient.instance.getJson('/videos/search', {'q': term});
        return _parseApi(data['videos']);
      } on ApiException catch (e) {
        debugPrint('Backend video search failed: ${e.message}');
        if (!ApiClient.directFallback) throw YouTubeApiException(e.message);
      }
    }

    return _searchDirect(term);
  }

  Future<List<YouTubeSong>> _searchDirect(String term) async {

    final cacheKey = 'search:${term.toLowerCase()}';
    final cached = _fromCache(cacheKey, const Duration(minutes: 15));
    if (cached != null) return cached;

    final data = await _get('/youtube/v3/search', {
      'part': 'snippet',
      'type': 'video',
      'q': term,
      'maxResults': '20',
      'videoCategoryId': '10',
      'videoEmbeddable': 'true', // app ke andar chalne wali videos
      'videoSyndicated': 'true',
    });

    final items = data['items'] as List<dynamic>? ?? [];

    final seen = <String>{};
    final videos = items
        .whereType<Map<String, dynamic>>()
        .map(YouTubeSong.fromJson)
        .where(_valid)
        .where((v) => seen.add(v.videoId))
        .toList();

    _cache[cacheKey] = _CacheEntry(videos);
    return videos;
  }
}