import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:server_core/server_core.dart';

/// Keeps the pinned server certificates (Trust on First Use) in secure
/// storage and mirrors them to the native stacks (media3, transmux, artwork),
/// which connect without the Dart client.
class CertPinStore {
  CertPinStore._();

  static const _key = 'fox_cert_pins_v1';
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _media3 = MethodChannel('moonfin/media3_video_control');
  static bool _loaded = false;
  static StreamSubscription<void>? _sub;

  /// Loads the pins once per isolate. Safe to call more than once.
  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    final registry = CertPinRegistry.instance;
    if (!kIsWeb) {
      try {
        registry.loadJson(await _storage.read(key: _key));
      } catch (e) {
        debugPrint('CertPinStore: Laden fehlgeschlagen: $e');
      }
    }
    registry.setPersistence((json) async {
      if (kIsWeb) return;
      try {
        await _storage.write(key: _key, value: json);
      } catch (e) {
        debugPrint('CertPinStore: Speichern fehlgeschlagen: $e');
      }
    });
    _sub ??= registry.changes.listen((_) => unawaited(syncNative()));
    unawaited(syncNative());
  }

  /// `host:port` -> fingerprint, the shape the native side expects.
  static Map<String, String> nativePins() =>
      CertPinRegistry.instance.toIsolateMap();

  static Future<void> syncNative() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _media3.invokeMethod<void>('setPinnedCertificates', {
        'pins': nativePins(),
      });
    } catch (_) {
      // No native player in this build or isolate.
    }
  }
}
