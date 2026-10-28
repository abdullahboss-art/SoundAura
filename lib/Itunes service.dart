import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:soundclock/jsonp.dart';
import 'package:soundclock/song.dart';

/// Apple iTunes API.
/// API key ki zaroorat nahi.
/// Note: iTunes aam tor par 30-second previews deta hai.
class ItunesService {
  ItunesService._();

  static final ItunesService instance = ItunesService._();

  static const Duration _timeout = Duration(seconds: 20);

  /// Songs search karne ke liye.
  /// Example: search('Arijit Singh', country: 'IN')
  Future<List<Song>> search(
    String term, {
    int limit = 20,
    String country = 'IN',
  }) async {
    final query = term.trim();

    if (query.isEmpty) return [];

    final safeLimit = limit.clamp(1, 200);

    final uri = Uri.https(
      'itunes.apple.com',
      '/search',
      {
        'term': query,
        'media': 'music',
        'entity': 'song',
        'country': country.toLowerCase(),
        'limit': '$safeLimit',
      },
    );

    try {
      final Object? decoded;

      if (kIsWeb) {
        // Web par iTunes CORS block karta hai, isliye JSONP.
        decoded = await jsonpGet(uri);
      } else {
        final response = await http
            .get(
              uri,
              headers: {'Accept': 'application/json'},
            )
            .timeout(_timeout);

        if (response.statusCode != 200) {
          debugPrint(
            'iTunes search HTTP error: ${response.statusCode}',
          );
          return [];
        }

        decoded = jsonDecode(response.body);
      }

      if (decoded is! Map) return [];

      final results = decoded['results'];

      if (results is! List) return [];

      final songs = <Song>[];

      for (final item in results) {
        if (item is! Map) continue;

        final track = Map<String, dynamic>.from(item);
        final preview = (track['previewUrl'] ?? '').toString();

        if (preview.isEmpty) continue;

        songs.add(_toSong(track));
      }

      return _uniqueSongs(songs);
    } catch (e) {
      debugPrint('iTunes search failed: $e');
      return [];
    }
  }

  /// Country-wise iTunes Top Songs chart.
  ///
  /// 'in' = India
  /// 'us' = United States
  /// 'gb' = United Kingdom
  /// 'pk' = Pakistan
  ///
  /// Important:
  /// Ye country charts hain, pure Bollywood/Hollywood genre charts nahi.
  Future<List<Song>> fetchTopChart({
    String country = 'in',
    int limit = 50,
  }) async {
    final code = country.trim().toLowerCase();

    if (code.isEmpty) return [];

    final safeLimit = limit.clamp(1, 200);

    final uri = Uri.https(
      'itunes.apple.com',
      '/$code/rss/topsongs/limit=$safeLimit/json',
    );

    try {
      final response = await http
          .get(
            uri,
            headers: {'Accept': 'application/json'},
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          'iTunes chart HTTP error ($code): '
          '${response.statusCode}',
        );
        return [];
      }

      final decoded =
          jsonDecode(response.body) as Map<String, dynamic>;

      final feed = decoded['feed'];

      if (feed is! Map) return [];

      final rawEntries = feed['entry'];

      final List<dynamic> entries;

      if (rawEntries is List) {
        entries = rawEntries;
      } else if (rawEntries is Map) {
        entries = [rawEntries];
      } else {
        return [];
      }

      final songs = <Song>[];

      for (final item in entries) {
        if (item is! Map) continue;

        final entry = Map<String, dynamic>.from(item);

        // Preview audio URL.
        final preview = _getPreviewUrl(entry);

        // Preview available na ho to skip.
        if (preview.isEmpty) continue;

        // Album artwork.
        final image = _getArtwork(entry);

        // Track ID.
        final idData = entry['id'];
        String trackId = '';

        if (idData is Map) {
          final attributes = idData['attributes'];

          if (attributes is Map) {
            trackId = (attributes['im:id'] ?? '').toString();
          }
        }

        if (trackId.isEmpty) {
          trackId = preview;
        }

        // Song title.
        final nameData = entry['im:name'];
        String title = 'Unknown';

        if (nameData is Map) {
          title = (nameData['label'] ?? 'Unknown').toString();
        }

        // Artist name.
        final artistData = entry['im:artist'];
        String artist = 'Unknown';

        if (artistData is Map) {
          artist = (artistData['label'] ?? 'Unknown').toString();
        }

        songs.add(
          Song(
            id: 'itunes_$trackId',
            title: title,
            artist: '$artist â€¢ Preview',
            imageUrl: _upgradeArtwork(image),
            audioUrl: preview,
            durationSec: 30,
          ),
        );
      }

      return _uniqueSongs(songs);
    } catch (e) {
      debugPrint('iTunes chart failed ($code): $e');
      return [];
    }
  }

  /// RSS chart entry se preview URL nikalta hai.
  String _getPreviewUrl(Map<String, dynamic> entry) {
    final links = entry['link'];

    if (links is! List) return '';

    for (final item in links) {
      if (item is! Map) continue;

      final attributes = item['attributes'];

      if (attributes is! Map) continue;

      final type = (attributes['type'] ?? '').toString();
      final href = (attributes['href'] ?? '').toString();

      if (type.startsWith('audio/') && href.isNotEmpty) {
        return href;
      }
    }

    return '';
  }

  /// RSS chart entry se cover artwork nikalta hai.
  String _getArtwork(Map<String, dynamic> entry) {
    final images = entry['im:image'];

    if (images is! List || images.isEmpty) return '';

    // Usually last image is the largest.
    for (final item in images.reversed) {
      if (item is! Map) continue;

      final label = (item['label'] ?? '').toString();

      if (label.isNotEmpty) return label;
    }

    return '';
  }

  /// Small artwork ko larger artwork URL mein convert karta hai.
  String _upgradeArtwork(String url) {
    if (url.isEmpty) return '';

    return url.replaceAll(
      RegExp(r'\d+x\d+bb'),
      '300x300bb',
    );
  }

  /// iTunes Search API response ko Song model mein convert karta hai.
  Song _toSong(Map<String, dynamic> track) {
    final artwork = (track['artworkUrl100'] ?? '').toString();

    return Song(
      id: 'itunes_${track['trackId'] ?? ''}',
      title: (track['trackName'] ?? 'Unknown').toString(),
      artist: '${track['artistName'] ?? 'Unknown'} â€¢ Preview',
      imageUrl: _upgradeArtwork(artwork),
      audioUrl: (track['previewUrl'] ?? '').toString(),
      durationSec: 30,
    );
  }

  /// Duplicate IDs aur duplicate titles remove karta hai.
  List<Song> _uniqueSongs(List<Song> songs) {
    final ids = <String>{};
    final titles = <String>{};
    final output = <Song>[];

    for (final song in songs) {
      final id = song.id.trim();
      final title = song.title.trim().toLowerCase();

      if (id.isEmpty || title.isEmpty || song.audioUrl.trim().isEmpty) {
        continue;
      }

      if (ids.contains(id) || titles.contains(title)) continue;

      ids.add(id);
      titles.add(title);
      output.add(song);
    }

    return output;
  }
}
