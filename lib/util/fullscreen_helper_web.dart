import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:moonfin/fox/fox_errors.dart';
Future<bool> isFullscreen() async => web.document.fullscreenElement != null;

Future<void> setFullscreen(bool value) async {
  try {
    if (value) {
      final el = web.document.documentElement;
      if (el != null) {
        await el.requestFullscreen().toDart;
      }
    } else if (web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
}
