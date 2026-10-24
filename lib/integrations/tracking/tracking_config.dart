// Foxfin: Trakt / Simkl / TMDB integration (GPL-2.0-or-later, see NOTICE).
//
// Foxfin 2.10.0: Es sind KEINE API-Schlüssel mehr im APK. Jede:r Nutzer:in trägt
// eigene Schlüssel ein (Einrichtung oder Einstellungen › Dienste › Eigene API-Schlüssel).
// Sie liegen verschlüsselt in FlutterSecureStorage (Android Keystore) und werden nie geloggt.
// Leer = Dienst aus und in der Oberfläche ausgeblendet.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TrackingConfig {
  const TrackingConfig._();

  static const _storage = FlutterSecureStorage();
  static const kTraktId = 'fox_key_trakt_id';
  static const kTraktSecret = 'fox_key_trakt_secret';
  static const kSimklId = 'fox_key_simkl_id';
  static const kTmdb = 'fox_key_tmdb';

  static const hintTrakt =
      'trakt.tv › Settings › Your API Apps › New Application (Redirect-URI: urn:ietf:wg:oauth:2.0:oob). Client-ID und Client-Secret eintragen.';
  static const hintSimkl = 'simkl.com/settings/developer › neue App anlegen, Client-ID eintragen.';
  static const hintTmdb = 'themoviedb.org › Einstellungen › API › API-Schlüssel (v3) beantragen.';

  static String traktClientId = '';
  static String traktClientSecret = '';
  static String simklClientId = '';
  static String tmdbApiKey = '';

  /// Beim Start einmal laden (vor dem Aufbau der Dienste).
  static Future<void> load() async {
    try {
      final all = await _storage.readAll();
      traktClientId = all[kTraktId] ?? '';
      traktClientSecret = all[kTraktSecret] ?? '';
      simklClientId = all[kSimklId] ?? '';
      tmdbApiKey = all[kTmdb] ?? '';
    } catch (_) {
      // Speicher nicht lesbar -> alle Dienste aus.
    }
  }

  static Future<void> save(String key, String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: v);
    }
    await load();
  }

  static bool get traktAvailable =>
      traktClientId.isNotEmpty && traktClientSecret.isNotEmpty;
  static bool get simklAvailable => simklClientId.isNotEmpty;
  static bool get tmdbAvailable => tmdbApiKey.isNotEmpty;
  static bool get anyTrackerAvailable => traktAvailable || simklAvailable;
}
