// Foxfin 2.8.2: Oberfläche-, Bild- und Cache-Einstellungen. GPL-3.0, see NOTICE.
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:server_core/server_core.dart' as sc;

/// Bildgröße für Metadaten-Bilder (Poster, Backdrops, Thumbs).
enum FoxImageSize { klein, mittel, gross, original }

extension FoxImageSizeX on FoxImageSize {
  String get label => switch (this) {
        FoxImageSize.klein => 'Klein',
        FoxImageSize.mittel => 'Mittel',
        FoxImageSize.gross => 'Groß',
        FoxImageSize.original => 'Original',
      };
  String get hint => switch (this) {
        FoxImageSize.klein => 'Schnellste Variante, spart Speicher und Daten',
        FoxImageSize.mittel => 'Empfohlen für TV-Boxen',
        FoxImageSize.gross => 'Scharf auf großen Displays',
        FoxImageSize.original => 'Volle Auflösung, langsamer',
      };
  /// Faktor auf die angefragte Breite.
  double get scale => switch (this) {
        FoxImageSize.klein => 0.6,
        FoxImageSize.mittel => 0.8,
        FoxImageSize.gross => 1.0,
        FoxImageSize.original => 2.0,
      };
  /// JPEG-Qualität für die Server-Anfrage.
  int get quality => switch (this) {
        FoxImageSize.klein => 70,
        FoxImageSize.mittel => 80,
        FoxImageSize.gross => 90,
        FoxImageSize.original => 96,
      };
}

enum FoxAnimationLevel { normal, reduziert, aus }

class FoxUiPrefs {
  static final imageSize = Preference(key: 'fox_image_size', defaultValue: 'auto');
  static final apiCacheMinutes = Preference(key: 'fox_api_cache_minutes', defaultValue: 4320);
  static final cacheMaxAgeDays = Preference(key: 'fox_cache_max_age_days', defaultValue: 30);
  static final hideEffects = Preference(key: 'fox_hide_effects', defaultValue: false);
  static final animationLevel = Preference(key: 'fox_animation_level', defaultValue: 'auto');
  static final pageTransitions = Preference(key: 'fox_page_transitions', defaultValue: true);
  static final preload = Preference(key: 'fox_preload', defaultValue: true);
  /// mpv-Upscaler: 'aus', 'fsr', 'anime4k'. Auf schwachen Geräten immer aus.
  static final upscaler = Preference(key: 'fox_upscaler', defaultValue: 'aus');
  /// Foxfin 2.9.1: Karten-Eckenradius in px, -1 = Theme-Standard.
  static final cardRadius = Preference(key: 'fox_card_radius', defaultValue: -1);
  /// Foxfin 2.9.1: Kompaktmodus (engere Raster, kleinere Karten).
  static final compact = Preference(key: 'fox_compact', defaultValue: false);
}

/// Laufzeitwerte, die ohne Kontext gelesen werden (z. B. in der Bildgrößen-Berechnung).
class FoxUi {
  static FoxImageSize imageSize = FoxImageSize.mittel;
  static bool hideEffects = false;
  static bool lowMemoryDevice = false;
  static FoxAnimationLevel animations = FoxAnimationLevel.normal;
  static bool pageTransitions = true;
  static bool preload = true;
  static int apiCacheMinutes = 4320;
  static String upscaler = 'aus';
  static int cacheMaxAgeDays = 30;
  static bool compact = false;
  static final changes = ValueNotifier<int>(0);

  static T _enum<T extends Enum>(List<T> values, String name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  static void apply({
    required String imageSizeName,
    required bool hideEffects,
    required String animationName,
    required bool pageTransitions,
    required bool preload,
    required int apiCacheMinutes,
    required int cacheMaxAgeDays,
    String upscaler = 'aus',
  }) {
    FoxUi.upscaler = upscaler;
    imageSize = _enum(FoxImageSize.values, imageSizeName, FoxImageSize.mittel);
    FoxUi.hideEffects = hideEffects;
    animations = _enum(FoxAnimationLevel.values, animationName, FoxAnimationLevel.normal);
    FoxUi.pageTransitions = pageTransitions;
    FoxUi.preload = preload;
    FoxUi.apiCacheMinutes = apiCacheMinutes;
    FoxUi.cacheMaxAgeDays = cacheMaxAgeDays;
    sc.artworkQualityParam = imageSize.quality.toString();
    // "Reduziert" = kurze, schnelle Animationen (doppeltes Tempo),
    // "Aus" = keine Animationen (MediaQuery.disableAnimations im App-Builder).
    timeDilation = animations == FoxAnimationLevel.reduziert ? 0.5 : 1.0;
    changes.value++;
  }
}
