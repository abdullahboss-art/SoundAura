  import 'dart:convert';

  import 'package:flutter/foundation.dart';
  import 'package:http/http.dart' as http;
  import 'package:soundclock/Api%20client.dart';

  import 'package:soundclock/jsonp.dart';
  import 'package:soundclock/song.dart';

  /// Deezer public API: key ki zaroorat nahi, 30 second preview milta hai.
  /// iTunes fail ho ya rate-limit ho jaye to fallback ke tor par use hota hai.
  class DeezerService {
    DeezerService._();

    static final DeezerService instance = DeezerService._();

    static const String _host = 'api.deezer.com';

    /// Global top tracks chart (zyada tar English / Hollywood).
    Future<List<Song>> chart({int limit = 50}) {
      return _tracks(Uri.https(_host, '/chart/0/tracks', {'limit': '$limit'}));
    }

    Future<List<Song>> search(String query, {int limit = 25}) {
      final q = query.trim();
      if (q.isEmpty) return Future.value(<Song>[]);

      return _tracks(
        Uri.https(_host, '/search', {'q': q, 'limit': '$limit'}),
      );
    }

    /// Deezer ke preview URL kuch ghanton mein expire ho jate hain. Saved
    /// (liked / playlist / download) gaane ke liye taaza URL yahan se milta hai.
    Future<String?> freshPreview(String songId) async {
      final id = songId.replaceFirst('deezer_', '');
      if (id.isEmpty) return null;

      // Pehle backend se taaza URL lo.
      if (ApiClient.instance.enabled) {
        try {
          final j = await ApiClient.instance.getJson('/deezer/preview/$id');
          final url = (j['url'] ?? '').toString();
          if (url.isNotEmpty) return url;
        } catch (_) {}
      }

      try {
        final Object? decoded;

        if (kIsWeb) {
          // Web par Deezer CORS block karta hai, isliye JSONP.
          decoded = await jsonpGet(
            Uri.https(_host, '/track/$id', {'output': 'jsonp'}),
          );
        } else {
          final response = await http
              .get(Uri.https(_host, '/track/$id'))
              .timeout(const Duration(seconds: 10));

          if (response.statusCode != 200) return null;
          decoded = jsonDecode(response.body);
        }

        if (decoded is! Map) return null;

        final preview = (decoded['preview'] ?? '').toString();
        return preview.isEmpty ? null : preview;
      } catch (e) {
        debugPrint('Deezer fresh preview failed: $e');
        return null;
      }
    }

    Future<List<Song>> _tracks(Uri uri) async {
      try {
        final Object? decoded;

        if (kIsWeb) {
          // Web par Deezer CORS block karta hai, isliye JSONP.
          decoded = await jsonpGet(
            uri.replace(
              queryParameters: {...uri.queryParameters, 'output': 'jsonp'},
            ),
          );
        } else {
          final response =
              await http.get(uri).timeout(const Duration(seconds: 20));

          if (response.statusCode != 200) {
            debugPrint('Deezer HTTP error: ${response.statusCode}');
            return [];
          }
          decoded = jsonDecode(response.body);
        }

        if (decoded is! Map) return [];

        final data = decoded['data'];
        if (data is! List) return [];

        final songs = <Song>[];

        for (final item in data) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);

          final preview = (m['preview'] ?? '').toString();
          final title = (m['title'] ?? '').toString();
          if (preview.isEmpty || title.trim().isEmpty) continue;

          final artist = (m['artist'] is Map)
              ? ((m['artist'] as Map)['name'] ?? 'Unknown').toString()
              : 'Unknown';
          final cover = (m['album'] is Map)
              ? ((m['album'] as Map)['cover_medium'] ?? '').toString()
              : '';

          songs.add(
            Song(
              id: 'deezer_${m['id']}',
              title: title,
              artist: '$artist • Preview',
              imageUrl: cover,
              audioUrl: preview,
              durationSec: 30,
            ),
          );
        }

        return songs;
      } catch (e) {
        debugPrint('Deezer failed: $e');
        return [];
      }
    }
  }
