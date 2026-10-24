// Foxfin 2.9.1: Seerr in den Hauptbibliotheken und Seerr-Bereich (eigene Umsetzung).
// GPL-2.0, see NOTICE.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/seerr_repository.dart';
import '../data/services/plugin_sync_service.dart';
import '../data/services/seerr/seerr_api_models.dart';
import '../ui/navigation/destinations.dart';
import '../ui/widgets/seerr/seerr_image_urls.dart';

import 'package:moonfin/fox/fox_errors.dart';
/// Schalter pro Bibliothek (lokal, keine Secrets).
class FoxSeerrLib {
  static const _key = 'fox_seerr_lib_off_v1';
  static final Map<String, String> _off = {}; // id -> Name
  static final changes = ValueNotifier<int>(0);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _off.clear();
    for (final e in p.getStringList(_key) ?? const <String>[]) {
      final i = e.indexOf('|');
      if (i > 0) {
        _off[e.substring(0, i)] = e.substring(i + 1);
      } else if (e.isNotEmpty) {
        _off[e] = e;
      }
    }
  }

  static bool enabledFor(String libraryId) => !_off.containsKey(libraryId);
  static Map<String, String> get disabled => Map.unmodifiable(_off);

  static Future<void> setEnabled(String libraryId, bool on, [String name = '']) async {
    on ? _off.remove(libraryId) : _off[libraryId] = name;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, [for (final e in _off.entries) '${e.key}|${e.value}']);
    changes.value++;
  }

  static bool get seerrReady {
    try {
      return GetIt.instance<PluginSyncService>().seerrAvailable;
    } catch (_) {
      return false;
    }
  }
}

/// Seerr-Status → Abzeichen. null = vorhanden (nicht zeigen).
String? foxSeerrBadge(SeerrDiscoverItem it) {
  final s = it.mediaInfo?.status;
  if (s == null || s <= 1) return 'Anfragen';
  if (s == 2) return 'Angefragt';
  if (s == 3) return 'In Arbeit';
  return null; // 4 teilweise / 5 vorhanden
}

enum FoxSeerrKind { film, serie, anime }

FoxSeerrKind? foxSeerrKindFor(String? collectionType, String libraryName) {
  final n = libraryName.toLowerCase();
  if (n.contains('anime')) return FoxSeerrKind.anime;
  return switch (collectionType) {
    'movies' => FoxSeerrKind.film,
    'tvshows' => FoxSeerrKind.serie,
    _ => null,
  };
}

/// Reihe "Bei Seerr anfragbar" am Ende einer Film-/Serien-/Anime-Bibliothek.
/// Lädt nur eine Seite (≈20 Titel) – klein für den Stick.
class FoxSeerrLibraryRow extends StatefulWidget {
  final String libraryId;
  final String libraryName;
  final FoxSeerrKind kind;
  final double cardWidth;
  final EdgeInsets padding;

  const FoxSeerrLibraryRow({
    super.key,
    required this.libraryId,
    this.libraryName = '',
    required this.kind,
    this.cardWidth = 130,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  State<FoxSeerrLibraryRow> createState() => _FoxSeerrLibraryRowState();
}

class _FoxSeerrLibraryRowState extends State<FoxSeerrLibraryRow> {
  List<SeerrDiscoverItem>? _items;

  @override
  void initState() {
    super.initState();
    FoxSeerrLib.changes.addListener(_onPrefs);
    unawaited(_load());
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FoxSeerrLib.changes.removeListener(_onPrefs);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      final page = switch (widget.kind) {
        FoxSeerrKind.film => await repo.discoverMovies(),
        FoxSeerrKind.serie => await repo.discoverTv(),
        FoxSeerrKind.anime =>
          await repo.discoverTv(genre: '16', language: 'ja'),
      };
      final list = page.results.where((e) => foxSeerrBadge(e) != null).toList();
      if (mounted) setState(() => _items = list);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null ||
        items.isEmpty ||
        !FoxSeerrLib.enabledFor(widget.libraryId)) {
      return const SizedBox.shrink();
    }
    final w = widget.cardWidth;
    final h = w * 1.5;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: widget.padding,
          child: Row(children: [
            const Icon(Icons.add_circle_outline_rounded, size: 20),
            const SizedBox(width: 8),
            const Text('Nicht vorhanden – bei Seerr anfragen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await FoxSeerrLib.setEnabled(widget.libraryId, false, widget.libraryName);
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                      content: Text(
                          'Seerr-Titel hier ausgeblendet – wieder einschalten unter FOX-Einstellungen.')));
                }
              },
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              label: const Text('Ausblenden'),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: h + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => FoxSeerrCard(item: items[i], width: w),
          ),
        ),
      ]),
    );
  }
}

class FoxSeerrCard extends StatefulWidget {
  final SeerrDiscoverItem item;
  final double width;
  const FoxSeerrCard({super.key, required this.item, this.width = 130});

  @override
  State<FoxSeerrCard> createState() => _FoxSeerrCardState();
}

class _FoxSeerrCardState extends State<FoxSeerrCard> {
  bool _focus = false;

  void _open() {
    final it = widget.item;
    final type = it.mediaType ?? (it.title != null ? 'movie' : 'tv');
    context.push(Destinations.seerrMedia('${it.id}',
        mediaType: type, title: it.title ?? it.name));
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final badge = foxSeerrBadge(it) ?? '';
    final accent = Theme.of(context).colorScheme.primary;
    final w = widget.width;
    return Focus(
      onFocusChange: (f) => setState(() => _focus = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          _open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _open,
        child: SizedBox(
          width: w,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: w,
              height: w * 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _focus ? accent : Colors.transparent, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                Opacity(
                  opacity: _focus ? 0.85 : 0.5, // leicht abgedunkelt
                  child: it.posterPath == null
                      ? const ColoredBox(color: Colors.black26)
                      : Image.network('$seerrPosterBase${it.posterPath}',
                          fit: BoxFit.cover,
                          cacheWidth: (w * 2).round(),
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Colors.black26)),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badge == 'Anfragen' ? accent : Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Text(it.title ?? it.name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ]),
        ),
      ),
    );
  }
}

/// Seerr als eigene "Bibliothek": Entdecken / Meine Anfragen / Freigaben.
class FoxSeerrHubScreen extends StatefulWidget {
  const FoxSeerrHubScreen({super.key});
  static const path = '/seerr/hub';

  @override
  State<FoxSeerrHubScreen> createState() => _FoxSeerrHubScreenState();
}

class _FoxSeerrHubScreenState extends State<FoxSeerrHubScreen> {
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final repo = await GetIt.instance.getAsync<SeerrRepository>();
        final u = await repo.getCurrentUser();
        final a = u.hasPermission(SeerrPermission.manageRequests);
        if (mounted) setState(() => _admin = a);
      } catch (fxE, fxSt) {
  FoxErrors.report(fxE, fxSt);
}
    }());
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <(IconData, String, String, String)>[
      (Icons.explore_rounded, 'Entdecken', 'Trends, Beliebt, Demnächst',
          Destinations.seerrDiscover),
      (Icons.playlist_add_check_rounded, 'Meine Anfragen', 'Status deiner Wünsche',
          Destinations.seerrRequests),
      if (_admin)
        (Icons.verified_rounded, 'Freigaben', 'Offene Anfragen genehmigen oder ablehnen',
            '${Destinations.seerrRequests}?tab=pending'),
    ];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Anfragen',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            Wrap(spacing: 20, runSpacing: 20, children: [
              for (var i = 0; i < tiles.length; i++)
                _HubTile(
                  autofocus: i == 0,
                  icon: tiles[i].$1,
                  title: tiles[i].$2,
                  subtitle: tiles[i].$3,
                  onTap: () => context.push(tiles[i].$4),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _HubTile extends StatefulWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool autofocus;
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_HubTile> createState() => _HubTileState();
}

class _HubTileState extends State<_HubTile> {
  bool _f = false;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _f = f),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 280,
        height: 150,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _f ? accent.withValues(alpha: 0.22) : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _f ? accent : Colors.white24, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(widget.icon, size: 36, color: _f ? accent : Colors.white),
          const Spacer(),
          Text(widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text(widget.subtitle,
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
        ]),
      ),
    );
  }
}
