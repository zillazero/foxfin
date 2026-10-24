// Foxfin 2.8.2: Einstellungen „Oberfläche“ und „Cache & Bilder“. GPL-3.0, see NOTICE.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../../fox/fox_hidden_items.dart';
import '../../../fox/fox_settings_backup.dart';
import '../../../util/platform_detection.dart';
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

  int _crashCount = 0;

  Future<void> _measure() async {
    _crashCount = await foxCrashReportCount();
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
    final limit = foxEffectiveCacheMb(p);
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
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.auto_awesome),
            title: const Text('GPU-Upscaling (mpv)'),
            subtitle: Text(FoxUi.lowMemoryDevice
                ? 'Auf diesem Gerät automatisch aus (zu schwache GPU)'
                : switch (p.get(FoxUiPrefs.upscaler)) {
                    'fsr' => 'AMD FSR – schärfere Hochskalierung für Filme/Serien',
                    'anime4k' => 'Anime4K – optimiert für Anime',
                    _ => 'Aus',
                  }),
            onTap: FoxUi.lowMemoryDevice
                ? null
                : () => _pick<String>('GPU-Upscaling (nur mpv-Player)', const [
                      ('aus', 'Aus', null),
                      ('fsr', 'AMD FSR 1.0', 'Für Realfilm, wenig GPU-Last'),
                      ('anime4k', 'Anime4K (Mode A, schnell)', 'Für Anime, höhere GPU-Last'),
                    ], p.get(FoxUiPrefs.upscaler), (v) => _set(FoxUiPrefs.upscaler, v)),
          ),
          const SettingsSectionHeader('Cache'),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.schedule),
            title: const Text('Metadaten-Cache (Startseite)'),
            subtitle: Text('Gespeicherte Startseiten-Reihen bis zu ${_dur(p.get(FoxUiPrefs.apiCacheMinutes))} anzeigen, danach neu laden'),
            onTap: () => _pick<int>('Metadaten-Cache-Dauer', const [
              (60, '1 Stunde', null), (1440, '1 Tag', null),
              (4320, '3 Tage', 'Standard'), (10080, '7 Tage', null),
            ], p.get(FoxUiPrefs.apiCacheMinutes), (v) => _set(FoxUiPrefs.apiCacheMinutes, v)),
          ),
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
          const SettingsSectionHeader('Wiedergabe'),
          if (PlatformDetection.isAndroid)
            DpadSwitchListTile(
              useSettingsIconShell: true,
              secondary: const Icon(Icons.graphic_eq_rounded),
              title: const Text('FFmpeg-Audiodecoder bevorzugen'),
              subtitle: const Text('Software-Decoder für Formate, die das Gerät nicht kann (z. B. DTS/TrueHD ohne Passthrough)'),
              value: p.get(UserPreferences.preferExoPlayerFfmpeg),
              onChanged: (v) async => _set(UserPreferences.preferExoPlayerFfmpeg, v),
            ),
          if (PlatformDetection.isAndroid && PlatformDetection.isTV)
            DpadSwitchListTile(
              useSettingsIconShell: true,
              secondary: const Icon(Icons.settings_input_hdmi_rounded),
              title: const Text('Tunneling'),
              subtitle: const Text('Audio/Video-Tunnel des TV-Geräts – flüssiger auf manchen Boxen, bei Problemen ausschalten'),
              value: !p.get(UserPreferences.media3TunnelingDisabled),
              onChanged: (v) async => _set(UserPreferences.media3TunnelingDisabled, !v),
            ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.hide_source_rounded),
            title: const Text('Ausgeblendete Titel'),
            subtitle: Text(FoxHidden.isEmpty
                ? 'Keine – über das Kontextmenü eines Titels ausblenden'
                : '${FoxHidden.items.length} ausgeblendet – zum Wiederherstellen öffnen'),
            onTap: FoxHidden.isEmpty ? null : _showHidden,
          ),
          const SettingsSectionHeader('FOX-Apps'),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Absturzberichte (lokal)'),
            subtitle: Text(_crashCount == 0
                ? 'Keine gespeichert – Berichte bleiben auf dem Gerät'
                : '$_crashCount gespeichert – exportieren (Server-Adressen und Tokens entfernt)'),
            onTap: _crashCount == 0
                ? null
                : () async {
                    final r = await foxExportCrashReports();
                    if (!mounted) return;
                    if (r == 'saved') {
                      _foxSnack('Absturzberichte exportiert.');
                      await foxClearCrashReports();
                      _crashCount = 0;
                      setState(() {});
                    }
                  },
          ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.live_tv_rounded),
            title: const Text('Im FOX-Player öffnen'),
            subtitle: const Text('Live-TV im FOX-Player – sonst Installation über den FOX Store'),
            onTap: () async {
              final r = await foxOpenFoxPlayer();
              if (!mounted) return;
              _foxSnack(switch (r) {
                'player' => 'FOX-Player wird geöffnet …',
                'store' => 'FOX-Player nicht installiert – FOX Store wird geöffnet.',
                'web' => 'FOX-Player nicht installiert – Download-Seite wird geöffnet.',
                _ => 'FOX-Player und FOX Store konnten nicht geöffnet werden.',
              });
            },
          ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.save_alt_rounded),
            title: const Text('Einstellungen sichern'),
            subtitle: const Text('Als JSON-Datei – ohne Server, Konten, Tokens oder Passwörter'),
            onTap: () async {
              try {
                final r = await foxExportSettings();
                if (mounted && r == 'saved') _foxSnack('Einstellungen gesichert.');
              } catch (e) {
                if (mounted) _foxSnack('Sichern fehlgeschlagen.');
              }
            },
          ),
          DpadListTile(
            useSettingsIconShell: true,
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: const Text('Einstellungen wiederherstellen'),
            subtitle: const Text('Foxfin-Sicherung laden – danach App neu starten'),
            onTap: () async {
              try {
                final n = await foxImportSettings();
                if (mounted && n >= 0) {
                  _foxSnack('$n Einstellungen übernommen – bitte App neu starten.');
                }
              } catch (e) {
                if (mounted) _foxSnack('Datei ist keine gültige Foxfin-Sicherung.');
              }
            },
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Future<void> _showHidden() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => SimpleDialog(
          title: const Text('Ausgeblendete Titel'),
          children: [
            for (final e in FoxHidden.items.entries)
              SimpleDialogOption(
                onPressed: () async {
                  await FoxHidden.unhide(e.key);
                  setD(() {});
                  if (FoxHidden.isEmpty && ctx.mounted) Navigator.of(ctx).pop();
                },
                child: Row(children: [
                  const Icon(Icons.undo_rounded, size: 18),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.value.isEmpty ? e.key : e.value)),
                ]),
              ),
            SimpleDialogOption(
              onPressed: () async {
                await FoxHidden.clear();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Alle wieder anzeigen'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _foxSnack(String t) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  static String _dur(int m) => m < 1440 ? '${m ~/ 60} Std.' : '${m ~/ 1440} Tage';
}
