import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:soundclock/song.dart';
import 'package:soundclock/song_json.dart';

/// Backend se aaya error (message seedha UI mein dikha sakte ho).
class ApiException implements Exception {
  final String message;
  final int? status; // null = server tak pahunche hi nahi
  const ApiException(this.message, [this.status]);

  @override
  String toString() => message;
}

/// SoundClock Python backend se baat karta hai.
///
/// Chrome / web (abhi):
///   flutter run -d chrome
///   (URL apne aap http://localhost:8000 hota hai)
///
/// Android emulator (debug):
///   flutter run
///   (URL apne aap http://10.0.2.2:8000 hota hai)
///
/// Asli phone / release APK (backend online deploy karke, https):
///   flutter build apk --release \
///     --dart-define=BACKEND_URL=https://aapka-server.onrender.com \
///     --dart-define=DIRECT_FALLBACK=false
///
/// Web live par:
///   flutter build web --release --dart-define=BACKEND_URL=https://aapka-server.onrender.com
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  // Agar --dart-define=BACKEND_URL=... diya ho to wohi chalega,
  // warna platform ke hisaab se default:
  //   web     -> http://localhost:8000
  //   android -> http://10.0.2.2:8000 (emulator)
  static const String _defaultUrl =
      kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';

  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: _defaultUrl,
  );

  /// true: backend na chale to purana seedha tareeqa (Deezer/YouTube direct) chalega.
  /// Live par false kar do taake keys app mein na rahen:
  ///   --dart-define=DIRECT_FALLBACK=false
  static const bool directFallback =
      bool.fromEnvironment('DIRECT_FALLBACK', defaultValue: true);

  bool get enabled => baseUrl.isNotEmpty;

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('$_root$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  /// Kisi bhi image URL ko backend se guzaar kar laata hai
  /// (web par CORS / block ka hal).
  String proxyUrl(String url) =>
      _uri('/proxy/image', {'url': url}).toString();

  Future<Map<String, dynamic>> getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final http.Response res;

    try {
      res = await http.get(_uri(path, query)).timeout(
            const Duration(seconds: 30),
          );
    } catch (e) {
      debugPrint('Backend connect failed ($_root$path): $e');
      // URL bhi dikhate hain, taake pata chale app kis address par ja rahi hai.
      throw ApiException('Server se connect nahi ho pa raha ($_root).');
    }

    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}

    if (res.statusCode != 200) {
      String msg = 'Server error (${res.statusCode}).';
      if (body is Map && body['detail'] is String) {
        msg = body['detail'] as String;
      }
      throw ApiException(msg, res.statusCode);
    }

    if (body is! Map) {
      throw ApiException('Server ka jawab samajh nahi aaya.', res.statusCode);
    }

    return Map<String, dynamic>.from(body);
  }

  /// {"songs": [...]} wale endpoint se Song list.
  /// "/audius/stream/.." jaise relative links ko backend ka poora address laga deta hai.
  Future<List<Song>> songs(
    String path, [
    Map<String, String>? query,
  ]) async {
    final json = await getJson(path, query);
    final raw = json['songs'];
    if (raw is! List) return [];

    final out = <Song>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);

      final audio = (m['audioUrl'] ?? '').toString();
      if (audio.startsWith('/')) m['audioUrl'] = '$_root$audio';

      final song = songFromMap(m);
      if (song.id.isNotEmpty &&
          song.title.trim().isNotEmpty &&
          song.audioUrl.trim().isNotEmpty) {
        out.add(song);
      }
    }
    return out;
  }
}