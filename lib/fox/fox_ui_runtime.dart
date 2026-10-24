// Foxfin 2.8.2: bindet FoxUiPrefs an die Laufzeit. GPL-3.0, see NOTICE.
import 'dart:async';

import '../preference/fox_ui_prefs.dart';
import '../preference/user_preferences.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../preference/preference_constants.dart';
import '../util/device_performance.dart';
import '../util/platform_detection.dart';
import '../util/tv_image_cache_stub.dart'
    if (dart.library.io) '../util/tv_image_cache_io.dart';

/// "auto" resolves by device class: a low-memory device (e.g. waipu.tv 4K
/// Stick, ~2 GB) gets small images and reduced animations, a strong one
/// (e.g. Shield Pro) medium images and full animations.
/// Erststart: Navigation passend zum Gerät – Seitenleiste auf TV und Tablet,
/// untere Leiste auf dem Handy. Eine eigene Wahl wird nie überschrieben.
void _foxSeedNavbar(UserPreferences p) {
  try {
    if (p.containsPreferenceKey(UserPreferences.navbarPosition.key)) return;
    NavbarPosition pos;
    if (PlatformDetection.isTV) {
      pos = NavbarPosition.left;
    } else if (PlatformDetection.useMobileUi && !PlatformDetection.isWeb) {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final v = views.first;
      final size = v.physicalSize / v.devicePixelRatio;
      pos = size.shortestSide >= 600 ? NavbarPosition.left : NavbarPosition.bottom;
    } else {
      return;
    }
    p.set(UserPreferences.navbarPosition, pos);
  } catch (_) {}
}

void foxUiLoad(UserPreferences p) {
  _foxSeedNavbar(p);
  // Foxfin 2.9.0: Variante "klein" (Stick) erzwingt das sparsame Profil.
  const foxKlein = bool.fromEnvironment('FOX_KLEIN');
  final weak = foxKlein ||
      p.resolveDevicePerformanceTier() == DevicePerformanceTier.reduced;
  FoxUi.lowMemoryDevice = weak;
  final size = p.get(FoxUiPrefs.imageSize);
  final anim = p.get(FoxUiPrefs.animationLevel);
  FoxUi.apply(
      imageSizeName: size == 'auto' ? (weak ? 'klein' : 'mittel') : size,
      hideEffects: p.get(FoxUiPrefs.hideEffects),
      animationName: anim == 'auto' ? (weak ? 'reduziert' : 'normal') : anim,
      pageTransitions: p.get(FoxUiPrefs.pageTransitions),
      preload: p.get(FoxUiPrefs.preload),
      apiCacheMinutes: p.get(FoxUiPrefs.apiCacheMinutes),
      cacheMaxAgeDays: p.get(FoxUiPrefs.cacheMaxAgeDays),
      upscaler: weak ? 'aus' : p.get(FoxUiPrefs.upscaler),
    );
}

Timer? _foxCacheTimer;

/// Auf schwachen Geräten (waipu.tv Stick) gilt statt des Standards 350 MB
/// ein kleineres Limit von 150 MB, solange der Nutzer nichts anderes wählt.
int foxEffectiveCacheMb(UserPreferences p) {
  final mb = p.get(UserPreferences.imageCacheLimitMb);
  return (FoxUi.lowMemoryDevice && mb == 350) ? 150 : mb;
}

/// Automatische Cache-Bereinigung: beim Start und alle 20 Minuten werden
/// alte Einträge (älter als cacheMaxAgeDays) entfernt und danach das
/// Größenlimit per LRU (älteste zuerst) durchgesetzt.
void foxStartCacheJanitor(UserPreferences p) {
  Future<void> run() async {
    await purgeOldImageCacheEntries(Duration(days: FoxUi.cacheMaxAgeDays));
    final mb = foxEffectiveCacheMb(p);
    await enforceImageCacheBudget(mb * 1024 * 1024);
  }

  unawaited(Future<void>.delayed(const Duration(seconds: 20), run));
  _foxCacheTimer?.cancel();
  _foxCacheTimer = Timer.periodic(const Duration(minutes: 20), (_) => unawaited(run()));
}
