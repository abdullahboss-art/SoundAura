
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:soundclock/song.dart';

class JamendoService {
  JamendoService._();

  static final JamendoService instance = JamendoService._();

  static const String _clientId = 'f7301f55';

  bool get hasKey =>
      _clientId.isNotEmpty &&
      _clientId != 'YOUR_JAMENDO_CLIENT_ID';

  Future<List<Song>> fetchTracks({
    String order = 'releasedate_desc',
    String? tags,
    String? search,
    int limit = 30,
  }) async {
    final query = search?.trim();

    final params = <String, String>{
      'client_id': _clientId,
      'format': 'json',
      'limit': '$limit',
      'audioformat': 'mp32',
      'imagesize': '300',

      // Vocals wale tracks; instrumental-only tracks nahi.
      'vocalinstrumental': 'vocal',

      // Latest releases pehle; search mein relevance.
      'order': query != null && query.isNotEmpty
          ? 'relevance'
          : order,

      // Singles aur album tracks dono include karo.
      'type': 'single albumtrack',
    };

    if (tags != null && tags.trim().isNotEmpty) {
      params['fuzzytags'] = tags.trim();
    }

    if (query != null && query.isNotEmpty) {
      params['search'] = query;
    }

    final uri = Uri.https(
      'api.jamendo.com',
      '/v3.0/tracks/',
      params,
    );

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'Jamendo HTTP error: ${response.statusCode}',
      );
    }

    final decoded =
        jsonDecode(response.body) as Map<String, dynamic>;

    final headers =
        decoded['headers'] as Map<String, dynamic>?;

    if (headers != null && headers['status'] != 'success') {
      throw Exception(
        headers['error_message'] ?? 'Jamendo API error',
      );
    }

    final rawResults =
        (decoded['results'] as List<dynamic>? ?? []);

    final songs = rawResults
        .whereType<Map<String, dynamic>>()
        .map(Song.fromJson)
        .where((song) =>
            song.audioUrl.trim().isNotEmpty &&
            song.title.trim().isNotEmpty)
        .toList();

    for (final song in songs) {
      print(
        'SONG: ${song.title} | '
        'ARTIST: ${song.artist} | '
        'URL: ${song.audioUrl}',
      );
    }

    return songs;
  }
}
