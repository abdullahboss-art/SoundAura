/// Mobile/desktop par JSONP ki zaroorat nahi (normal http chalta hai).
Future<Object?> jsonpGet(
  Uri uri, {
  Duration timeout = const Duration(seconds: 15),
}) async =>
    null;