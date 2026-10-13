// Foxfin: Trakt / Simkl / TMDB integration (GPL-2.0-or-later, see NOTICE).
//
// API keys are never committed. They are injected at build time with
//   flutter build apk --dart-define-from-file=foxfin-keys.json
// (foxfin-keys.json is git-ignored; see foxfin-keys.example.json).
// A service whose key is missing is hidden in the UI and never contacted.

class TrackingConfig {
  const TrackingConfig._();

  static const traktClientId = String.fromEnvironment('TRAKT_CLIENT_ID');
  static const traktClientSecret =
      String.fromEnvironment('TRAKT_CLIENT_SECRET');
  static const simklClientId = String.fromEnvironment('SIMKL_CLIENT_ID');
  static const tmdbApiKey = String.fromEnvironment('TMDB_API_KEY');

  static bool get traktAvailable =>
      traktClientId.isNotEmpty && traktClientSecret.isNotEmpty;
  static bool get simklAvailable => simklClientId.isNotEmpty;
  static bool get tmdbAvailable => tmdbApiKey.isNotEmpty;
  static bool get anyTrackerAvailable => traktAvailable || simklAvailable;
}
