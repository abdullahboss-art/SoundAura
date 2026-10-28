import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

int _counter = 0;

/// <script> tag se JSONP request. Browser ke CORS block se bachata hai.
/// Server ko `callback=<naam>` milta hai; jawab Map/List ban kar wapas aata hai.
/// Fail / timeout par null.
Future<Object?> jsonpGet(
  Uri uri, {
  Duration timeout = const Duration(seconds: 15),
}) {
  final completer = Completer<Object?>();
  final name = '_melodyJsonp${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  Timer? timer;

  void finish(Object? value) {
    if (completer.isCompleted) return;
    timer?.cancel();
    script.remove();
    globalContext[name] = null;
    completer.complete(value);
  }

  globalContext[name] = ((JSAny? data) {
    finish(data.dartify());
  }).toJS;

  script.addEventListener(
    'error',
    ((web.Event e) {
      finish(null);
    }).toJS,
  );

  timer = Timer(timeout, () => finish(null));

  script.src = uri.replace(
    queryParameters: {...uri.queryParameters, 'callback': name},
  ).toString();

  web.document.head?.appendChild(script);

  return completer.future;
}