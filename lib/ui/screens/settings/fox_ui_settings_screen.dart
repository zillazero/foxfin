// Foxfin 2.8.2: Einstellungen „Oberfläche“ und „Cache & Bilder“. GPL-3.0, see NOTICE.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../../fox/fox_ui_runtime.dart';
import '../../../preference/fox_ui_prefs.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/tv_image_cache_stub.dart'
    if (dart.library.io) '../../../util/tv_image_cache_io.dart';
import '../../widgets/focus/dpad_list_tile.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import '../../widgets/settings/settings_section_header.dart';
import 'settings_app_bar.dart';

class FoxUiSettingsScreen extends StatefulWidget {
  const FoxUiSettingsScreen({super.key});

  @override
  State<FoxUiSettingsScreen> createState() => _FoxUiSettingsScreenState();
}

class _FoxUiSettingsScreenState extends State<FoxUiSettingsScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  int? _cacheBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final b = await imageDiskCacheBytes();
    if (mounted) setState(() => _cacheBytes = b);
  }

  Future<void> _set<T>(Preference<T> p, T v) async {
    await _prefs.set(p, v);
    foxUiLoad(_prefs);
    if (mounted) setState(() {});
  }

  String _fmt(int bytes) => bytes >= 1 << 30
      ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB'
      : '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

  Future<void> _pick<T>(String title, List<(T, String, String?)> options, T current, void Function(T) onPick) {
    return showFocusRestoringModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: DpadRadioGroup<T>(
            groupValue: current,
            onChanged: (v) {
              if (v != null) onPick(v);
              Navigator.pop(ctx);
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              for (final (v, label, hint) in options)
                DpadRadioListTile<T>(
                  autofocus: v == current,
                  value: v,
                  title: Text(label),
                  subtitle: hint == null ? null : Text(hint),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    await clearImageDiskCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await _measure();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache geleert')));
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    final limit = p.get(UserPreferences.imageCacheLimitMb);
    final size = FoxUi.imageSize;
    final anim = FoxUi.animations;
    final age = p.get(FoxUiPrefs.cacheMaxAgeDays);
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, const Text('Oberfläche & Leistung')),
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(FoxUi.lowMemoryDevice
                ? 'Gerät erkannt: wenig Arbeitsspeicher – sparsames Profil ist voreingestellt.'
                : 'Gerät erkannt: leistungsstark – volles Profil ist voreingestellt.'),
          ),
          const SettingsSectionHeader('Oberfläche'),
          DpadSwitchListTile(
            autofocus: true,
            useSettingsIconShell: true,
            secondary: const Icon(Icons.blur_off),
            title: const Text('Effekte ausblenden'),
            subtitle: const Text('Glow, Unschärfe (Glas) und Parallax aus – deutlich flüssiger auf TV-Boxen'),
            value: FoxUi.hideEffects,
            onChanged: (v) async {
              await _set(FoxUiPrefs.hideEffects, v);
              await p.set(UserPreferences.glassQuality, v ? GlassQualityMode.reduced : GlassQualityMode.auto);
            },
          ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.animation),
            title: const Text('Animationen'),
            subtitle: Text(switch (anim) {
              FoxAnimationLevel.normal => 'Normal (System „Bewegung reduzieren“ wird beachtet)',
              FoxAnimationLevel.reduziert => 'Reduziert – kürzer und ruhiger',
              FoxAnimationLevel.aus => 'Aus',
            }),
            onTap: () => _pick<FoxAnimationLevel>('Animationen', const [
              (FoxAnimationLevel.normal, 'Normal', null),
              (FoxAnimationLevel.reduziert, 'Reduziert', 'Kürzere, ruhigere Bewegungen'),
              (FoxAnimationLevel.aus, 'Aus', 'Keine Animationen'),
            ], anim, (v) => _set(FoxUiPrefs.animationLevel, v.name)),
          ),
          DpadSwitchListTile(
            useSettingsIconShell: true,
            secondary: const Icon(Icons.swap_horiz),
            title: const Text('Übergangseffekte'),
            subtitle: const Text('Weiche Übergänge beim Seitenwechsel'),
            value: FoxUi.pageTransitions,
            onChanged: (v) => _set(FoxUiPrefs.pageTransitions, v),
          ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.speed),
            title: const Text('Leistungsmodus'),
            subtitle: Text(switch (p.get(UserPreferences.performanceMode)) {
              DevicePerformanceMode.auto => 'Automatisch',
              DevicePerformanceMode.standard => 'Standard',
              DevicePerformanceMode.reduced => 'Sparsam (schwache Geräte) – wirkt nach Neustart',
            }),
            onTap: () => _pick<DevicePerformanceMode>('Leistungsmodus', const [
              (DevicePerformanceMode.auto, 'Automatisch', 'Gerät wird gemessen'),
              (DevicePerformanceMode.standard, 'Standard', null),
              (DevicePerformanceMode.reduced, 'Sparsam', 'Weniger Speicher, weniger parallele Bilder'),
            ], p.get(UserPreferences.performanceMode), (v) => _set(UserPreferences.performanceMode, v)),
          ),
          DpadSwitchListTile(
            useSettingsIconShell: true,
            secondary: const Icon(Icons.fast_forward),
            title: const Text('Vorladen'),
            subtitle: const Text('Nächste Seiten und Bilder im Voraus laden, damit Umschalten sofort geht'),
            value: FoxUi.preload,
            onChanged: (v) => _set(FoxUiPrefs.preload, v),
          ),
          const SettingsSectionHeader('Bilder'),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.photo_size_select_large),
            title: const Text('Bildgröße der Metadaten'),
            subtitle: Text('${size.label} – ${size.hint}'),
            onTap: () => _pick<FoxImageSize>('Bildgröße (Poster, Backdrops, Thumbs)', [
              for (final s in FoxImageSize.values) (s, s.label, s.hint),
            ], size, (v) async {
              await _set(FoxUiPrefs.imageSize, v.name);
              PaintingBinding.instance.imageCache.clear();
            }),
          ),
          const SettingsSectionHeader('Cache'),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.storage),
            title: const Text('Bild-Cache Limit'),
            subtitle: Text(limit == 0 ? 'Kein Limit' : (limit >= 1024 ? '${limit ~/ 1024} GB' : '$limit MB')),
            onTap: () => _pick<int>('Bild-Cache Limit', const [
              (100, '100 MB', null), (200, '200 MB', null), (350, '350 MB', 'Standard'),
              (500, '500 MB', null), (1024, '1 GB', null), (2048, '2 GB', null),
            ], limit, (v) async {
              await _set(UserPreferences.imageCacheLimitMb, v);
              await enforceImageCacheBudget(v * 1024 * 1024);
              await _measure();
            }),
          ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.auto_delete),
            title: const Text('Automatische Bereinigung'),
            subtitle: Text('Bilder entfernen, die $age Tage nicht genutzt wurden (beim Start und alle 20 Min.)'),
            onTap: () => _pick<int>('Ungenutzte Bilder entfernen nach', const [
              (7, '7 Tagen', null), (14, '14 Tagen', null), (30, '30 Tagen', 'Standard'), (90, '90 Tagen', null),
            ], age, (v) async {
              await _set(FoxUiPrefs.cacheMaxAgeDays, v);
              unawaited(purgeOldImageCacheEntries(Duration(days: v)).then((_) => _measure()));
            }),
          ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Cache leeren'),
            subtitle: Text(_clearing
                ? 'Wird geleert …'
                : 'Belegt: ${_cacheBytes == null ? '…' : _fmt(_cacheBytes!)}'
                    '${limit > 0 ? ' von ${limit >= 1024 ? '${limit ~/ 1024} GB' : '$limit MB'}' : ''}'),
            onTap: _clearing ? null : _clearCache,
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}
