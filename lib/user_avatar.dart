import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundclock/Api%20client.dart' show ApiClient;
import 'package:soundclock/sc_theme.dart';

/// User ki photo ka link. Pehle user.photoURL, na ho to Google provider wali.
String userPhotoUrl(User? user, {int size = 300}) {
  if (user == null) return '';

  var url = user.photoURL ?? '';

  if (url.isEmpty) {
    for (final p in user.providerData) {
      final u = p.photoURL ?? '';
      if (u.isNotEmpty) {
        url = u;
        break;
      }
    }
  }

  if (url.isEmpty) return '';

  // Google ki chhoti (s96-c) photo ko apne size mein badal do.
  if (url.contains('googleusercontent.com')) {
    final sizeRegex = RegExp(r'=s\d+(-c)?$');
    if (sizeRegex.hasMatch(url)) {
      return url.replaceFirst(sizeRegex, '=s$size-c');
    }
  }
  return url;
}

/// User ka gol avatar.
///  1. Neeche naam ka pehla harf (ya person icon) hamesha rehta hai.
///  2. Photo ek baar download hoke phone/browser mein SAVE ho jati hai,
///     aglay baar seedha save wali photo dikhti hai.
///  3. Web par download Python server (proxy) se hota hai, mobile par seedha.
///  4. Sab fail ho jaye to harf hi dikhta rehta hai.
class UserAvatar extends StatefulWidget {
  final String photoUrl;

  /// Harf yahan se aata hai. Khali ya "Unknown User" ho to person icon.
  final String name;
  final double size;

  const UserAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.size = 48,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  static const String _kUrl = 'avatar_cache_url';
  static const String _kData = 'avatar_cache_data';

  // Memory cache: ek hi photo kai jagah (profile + bottom nav) ho to dobara load nahi hoti.
  static String? _memUrl;
  static Uint8List? _memBytes;

  // Ek hi waqt mein ek hi download.
  static String? _loadingUrl;
  static Future<Uint8List?>? _loading;

  static bool _loggedEmpty = false;

  Uint8List? _bytes;
  bool _networkFallback = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _bytes = null;
      _networkFallback = false;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.photoUrl;
    if (url.isEmpty) return;

    // 1. Memory
    if (_memUrl == url && _memBytes != null) {
      _bytes = _memBytes;
      return;
    }

    // 2. Save ki hui photo (phone / browser storage)
    final saved = await _readSaved(url);
    if (!mounted || url != widget.photoUrl) return;
    if (saved != null) {
      _memUrl = url;
      _memBytes = saved;
      setState(() => _bytes = saved);
      return;
    }

    // 3. Download karke save karo
    if (_loadingUrl != url || _loading == null) {
      _loadingUrl = url;
      _loading = _download(url);
    }
    final bytes = await _loading;
    if (!mounted || url != widget.photoUrl) return;

    if (bytes != null) {
      _memUrl = url;
      _memBytes = bytes;
      _save(url, bytes);
      setState(() => _bytes = bytes);
    } else {
      // Aakhri koshish: seedha <img> tag se.
      setState(() => _networkFallback = true);
    }
  }

  Future<Uint8List?> _readSaved(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kUrl) != url) return null;
      final b64 = prefs.getString(_kData);
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (e) {
      debugPrint('Avatar: save wali photo nahi padh saka ($e)');
      return null;
    }
  }

  Future<void> _save(String url, Uint8List bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUrl, url);
      await prefs.setString(_kData, base64Encode(bytes));
    } catch (e) {
      debugPrint('Avatar: photo save nahi hui ($e)');
    }
  }

  Future<Uint8List?> _download(String url) async {
    final candidates = <String>[];

    if (kIsWeb) {
      // Web par Google ki photo seedha fetch nahi hoti (CORS), proxy se lo.
      if (ApiClient.instance.enabled) {
        candidates.add(ApiClient.instance.proxyUrl(url));
      }
    } else {
      candidates.add(url);
      if (ApiClient.instance.enabled) {
        candidates.add(ApiClient.instance.proxyUrl(url));
      }
    }

    for (final c in candidates) {
      try {
        final res =
            await http.get(Uri.parse(c)).timeout(const Duration(seconds: 15));
        final type = res.headers['content-type'] ?? '';
        if (res.statusCode == 200 &&
            res.bodyBytes.isNotEmpty &&
            type.startsWith('image/')) {
          return res.bodyBytes;
        }
        debugPrint('Avatar: download fail (${res.statusCode}) $c');
      } catch (e) {
        debugPrint('Avatar: download error ($e)');
      }
    }
    return null;
  }

  Widget _fallback() {
    final size = widget.size;
    final n = widget.name.trim();
    final showIcon = n.isEmpty || n == 'Unknown User';

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SC.primary, SC.violet],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: showIcon
          ? Icon(Icons.person_rounded, size: size * 0.55, color: Colors.white)
          : Text(
              n.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  Widget _photo() {
    final size = widget.size;

    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (c, e, s) => const SizedBox.shrink(),
      );
    }

    if (_networkFallback) {
      return Image.network(
        widget.photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (c, e, s) {
          debugPrint('Avatar: seedhi photo bhi load nahi hui ($e)');
          return const SizedBox.shrink();
        },
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photoUrl.isEmpty && !_loggedEmpty) {
      _loggedEmpty = true;
      debugPrint('Avatar: user ki photoURL khali hai, harf dikhaya ja raha hai.');
    }

    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _fallback(),
            if (widget.photoUrl.isNotEmpty) _photo(),
          ],
        ),
      ),
    );
  }
}