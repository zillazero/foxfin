import 'package:flutter/services.dart';

import '../util/platform_detection.dart';

import 'package:moonfin/fox/fox_errors.dart';
class IosStorage {
  static const _channel = MethodChannel('com.moonfin/ios_storage');

  static Future<void> excludeFromBackup(String path) async {
    if (!PlatformDetection.isIOS) return;
    try {
      await _channel.invokeMethod('excludeFromBackup', {'path': path});
    } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
  }
}
