
  import 'dart:convert';

  import 'package:http/http.dart' as http;
  import 'package:flutter/foundation.dart';
import 'package:soundclock/Api%20client.dart';
  import 'package:soundclock/song.dart';

  class AudiusService {
    AudiusService._();

    static final AudiusService instance = AudiusService._();

    static const String _apiKey =
        '0x3a836f9c438dfaa1ba5e086854a4e41c6a50c52a';

    static const String _host = 'api.audius.co';
    static const String _appName = 'soundclock';

    bool get _hasDirectKey =>
        _apiKey.isNotEmpty &&
        _apiKey != 'YOUR_AUDIUS_API_KEY';

    /// Backend ho ya app ki apni key ho, dono surat mein true.
    bool get hasKey => ApiClient.instance.enabled || _hasDirectKey;

    String _streamUrl(String id) {
      return Uri.https(_host, '/v1/tracks/$id/stream', {
        'api_key': _apiKey,
        'app_name': _appName,
      }).toString();
    }

    /// Audius se playable audio URL resolve karo.
    Future<String> resolveStreamUrl(String id) async {
      final uri = Uri.https(_host, '/v1/tracks/$id/stream', {
        'no_redirect': 'true',
        if (_hasDirectKey) 'api_key': _apiKey,
        'app_name': _appName,
      });

      final response =
          await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(
          'Stream URL error: ${response.statusCode}',
        );
      }

      final decoded =
          jsonDecode(response.body) as Map<String, dynamic>;

      final url = (decoded['data'] ?? '').toString();

      if (url.isEmpty) {
        throw Exception('Audio stream URL nahi mila.');
      }

      return url;
    }

    /// Trending tracks.
    Future<List<Song>> fetchTrending({
      String? genre,
      String time = 'week',
      int limit = 30,
    }) async {
      // Pehle Python backend (key server par hoti hai).
      if (ApiClient.instance.enabled) {
        try {
          return await ApiClient.instance.songs('/audius/trending', {
            'time': time,
            'limit': '$limit',
            if (genre != null && genre.trim().isNotEmpty) 'genre': genre.trim(),
          });
        } on ApiException catch (e) {
          debugPrint('Backend audius failed: ${e.message}');
          if (!_hasDirectKey || !ApiClient.directFallback) return <Song>[];
        }
      }

      final params = <String, String>{
        'time': time,
        'limit': '$limit',
      };

      if (genre != null && genre.trim().isNotEmpty) {
        params['genre'] = genre.trim();
      }

      return _get('/v1/tracks/trending', params);
    }

    /// Song title, singer ya dono se search.
    ///
    /// Examples:
    /// search('Tum Hi Ho')
    /// search('Atif Aslam')
    /// search('Atif Aslam Tajdar-e-Haram')
    Future<List<Song>> search(
      String query, {
      int limit = 30,
    }) async {
      final term = query.trim();

      if (term.isEmpty) {
        return <Song>[];
      }

      final songs = await _get(
        '/v1/tracks/search',
        {
          'query': term,
          'limit': '$limit',
        },
      );

      final normalizedQuery = _normalize(term);

      // Exact title, title beginning with query, then other matches.
      songs.sort((a, b) {
        final aTitle = _normalize(a.title);
        final bTitle = _normalize(b.title);

        final aRank = _titleRank(aTitle, normalizedQuery);
        final bRank = _titleRank(bTitle, normalizedQuery);

        return aRank.compareTo(bRank);
      });

      // Instrumental/karaoke titles ko hata kar results do.
      return songs.where(_isLikelyVocalTrack).toList();
    }

    int _titleRank(String title, String query) {
      if (title == query) return 0;
      if (title.startsWith(query)) return 1;
      if (title.contains(query)) return 2;
      return 3;
    }

    String _normalize(String value) {
      return value
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    bool _isLikelyVocalTrack(Song song) {
      final title = song.title.toLowerCase();

      const excludedTerms = <String>[
        'instrumental',
        'karaoke',
        'backing track',
        'no vocals',
        'without vocals',
        'beat only',
        'type beat',
        'acapella instrumental',
      ];

      return !excludedTerms.any(title.contains);
    }

    /// Audius API se tracks hasil karo.
    Future<List<Song>> _get(
      String path,
      Map<String, String> params,
    ) async {
      if (!_hasDirectKey) {
        throw Exception('Audius API key configured nahi hai.');
      }

      final uri = Uri.https(_host, path, {
        ...params,
        'api_key': _apiKey,
        'app_name': _appName,
      });

      final response =
          await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(
          'Audius HTTP error: ${response.statusCode}',
        );
      }

      final decoded =
          jsonDecode(response.body) as Map<String, dynamic>;

      final raw = decoded['data'] as List<dynamic>? ?? [];

      return raw
          .whereType<Map<String, dynamic>>()
          .where((track) => track['is_streamable'] != false)
          .where((track) {
            final duration = track['duration'];
            return duration is num && duration >= 60;
          })
          .map(_toSong)
          .where((song) =>
              song.id.isNotEmpty &&
              song.title.trim().isNotEmpty)
          .toList();
    }

    Song _toSong(Map<String, dynamic> track) {
      final id = (track['id'] ?? '').toString();

      final user = track['user'] as Map<String, dynamic>?;
      final artwork = track['artwork'] as Map<String, dynamic>?;

      final image = (
        artwork?['480x480'] ??
        artwork?['150x150'] ??
        artwork?['1000x1000'] ??
        ''
      ).toString();

      return Song(
        id: id,
        title: (track['title'] ?? '').toString(),
        artist: (user?['name'] ?? 'Unknown').toString(),
        imageUrl: image,
        audioUrl: id.isEmpty ? '' : _streamUrl(id),
        durationSec: (track['duration'] as num?)?.toInt() ?? 0,
      );
    }
  }
