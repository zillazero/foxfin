// Foxfin 2.8.2: bindet FoxUiPrefs an die Laufzeit. GPL-3.0, see NOTICE.
import 'dart:async';

import '../preference/fox_ui_prefs.dart';
import '../preference/user_preferences.dart';
import '../util/device_performance.dart';
import '../util/tv_image_cache_stub.dart'
    if (dart.library.io) '../util/tv_image_cache_io.dart';

/// "auto" resolves by device class: a low-memory device (e.g. waipu.tv 4K
/// Stick, ~2 GB) gets small images and reduced animations, a strong one
/// (e.g. Shield Pro) medium images and full animations.
void foxUiLoad(UserPreferences p) {
  final weak = p.resolveDevicePerformanceTier() == DevicePerformanceTier.reduced;
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
    );
}

Timer? _foxCacheTimer;

/// Automatische Cache-Bereinigung: beim Start und alle 20 Minuten werden
/// alte Einträge (älter als cacheMaxAgeDays) entfernt und danach das
/// Größenlimit per LRU (älteste zuerst) durchgesetzt.
void foxStartCacheJanitor(UserPreferences p) {
  Future<void> run() async {
    await purgeOldImageCacheEntries(Duration(days: FoxUi.cacheMaxAgeDays));
    final mb = p.get(UserPreferences.imageCacheLimitMb);
    await enforceImageCacheBudget(mb * 1024 * 1024);
  }

  unawaited(Future<void>.delayed(const Duration(seconds: 20), run));
  _foxCacheTimer?.cancel();
  _foxCacheTimer = Timer.periodic(const Duration(minutes: 20), (_) => unawaited(run()));
}
