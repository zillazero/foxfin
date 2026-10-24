import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:moonfin/fox/fox_errors.dart';
/// Foxfin: credentials for a directly connected Jellyseerr/Seerr server.
///
/// The server URL is not secret; the API key and the session cookie live in
/// the platform keystore (Android Keystore backed) and are never logged.
/// Nothing is preconfigured: every value comes from the user.
class SeerrDirectStore {
  static const _storage = FlutterSecureStorage();

  static String _k(String userId, String name) => 'fox_seerr_${name}_$userId';

  static Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
  }

  static Future<String?> url(String userId) => _read(_k(userId, 'url'));
  static Future<void> setUrl(String userId, String? v) =>
      _write(_k(userId, 'url'), v?.trim());

  static Future<String?> apiKey(String userId) => _read(_k(userId, 'api_key'));
  static Future<void> setApiKey(String userId, String? v) =>
      _write(_k(userId, 'api_key'), v?.trim());

  static Future<String?> cookie(String userId) => _read(_k(userId, 'cookie'));
  static Future<void> setCookie(String userId, String? v) =>
      _write(_k(userId, 'cookie'), v);

  static Future<void> clear(String userId) async {
    await setUrl(userId, null);
    await setApiKey(userId, null);
    await setCookie(userId, null);
  }

  /// Masks a secret for display, e.g. "abcd••••••••wxyz".
  static String mask(String? secret) {
    final s = secret ?? '';
    if (s.isEmpty) return '';
    if (s.length <= 8) return '••••••••';
    return '${s.substring(0, 4)}••••••••${s.substring(s.length - 4)}';
  }
}
