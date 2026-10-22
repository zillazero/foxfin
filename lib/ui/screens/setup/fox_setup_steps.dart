// FOX additions to the Moonfin setup wizard (Foxfin 2.8.1). GPL-3.0, see NOTICE.
part of 'setup_wizard_screen.dart';


TrackingService _tracking() {
  if (!GetIt.instance.isRegistered<TrackingService>()) {
    GetIt.instance.registerSingleton<TrackingService>(TrackingService());
  }
  return GetIt.instance<TrackingService>();
}


class _FoxCard extends StatelessWidget {
  const _FoxCard({required this.order, required this.onPressed, required this.child, this.selected = false, this.autofocus = false, this.accent});
  final int order;
  final VoidCallback onPressed;
  final Widget child;
  final bool selected;
  final bool autofocus;
  final Color? accent;

  @override
  Widget build(BuildContext context) => _Focusable(
        order: order,
        autofocus: autofocus,
        onPressed: onPressed,
        builder: (focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.spaceLg, vertical: AppSpacing.spaceMd),
          decoration: BoxDecoration(
            color: (accent ?? AppColorScheme.accent).withValues(alpha: selected ? 0.22 : 0.06),
            borderRadius: AppRadius.circular(12),
            border: Border.all(
              color: focused ? AppColorScheme.onSurface : (selected ? (accent ?? AppColorScheme.accent) : AppColorScheme.onSurface.withValues(alpha: 0.16)),
              width: focused ? 2 : 1,
            ),
          ),
          child: child,
        ),
      );
}

Widget _foxText(String s, {bool muted = false, bool bold = false, double? size}) => Text(s,
    style: TextStyle(
      color: AppColorScheme.onSurface.withValues(alpha: muted ? 0.62 : 1),
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      fontSize: size ?? AppTypography.fontSizeSm,
    ));

Widget _foxStatus(String label, bool ok, String detail) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? AppColorScheme.accent : AppColorScheme.onSurface.withValues(alpha: 0.4)),
        const SizedBox(width: 10),
        SizedBox(width: 150, child: _foxText(label, bold: true)),
        Expanded(child: _foxText(detail, muted: true)),
      ]),
    );

// ---------------------------------------------------------------- 1 Theme
class _FoxThemeStep extends StatelessWidget {
  const _FoxThemeStep({required this.prefs});
  final UserPreferences prefs;
  @override
  Widget build(BuildContext context) {
    final controller = AppThemeScope.of(context);
    final active = controller.activeSpec.id;
    final themes = ThemeRegistry.availableThemes;
    return Wrap(spacing: AppSpacing.spaceMd, runSpacing: AppSpacing.spaceMd, alignment: WrapAlignment.center, children: [
      for (var i = 0; i < ThemeRegistry.foxThemeOrder.length; i++)
        if (themes[ThemeRegistry.foxThemeOrder[i]] case final spec?)
          _FoxCard(
            order: i,
            autofocus: spec.id == active,
            selected: spec.id == active,
            accent: spec.colors.accent,
            onPressed: () => controller.applyThemeById(prefs, spec.id),
            child: SizedBox(width: 150, child: Column(children: [
              Container(height: 46, decoration: BoxDecoration(
                gradient: LinearGradient(colors: [spec.colors.background, spec.colors.accent]),
                borderRadius: AppRadius.circular(8))),
              const SizedBox(height: 8),
              _foxText(spec.displayName, bold: true),
            ])),
          ),
    ]);
  }
}

// ---------------------------------------------------------------- 2 FOX-Konto
class _FoxAccountStep extends StatefulWidget {
  const _FoxAccountStep();
  @override
  State<_FoxAccountStep> createState() => _FoxAccountStepState();
}

class _FoxAccountStepState extends State<_FoxAccountStep> {
  final _fox = FoxSyncService.instance;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _msg;

  @override
  void initState() {
    super.initState();
    _fox.refreshStatus().then((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _user.dispose(); _pass.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_fox.supported) return _foxText('Das FOX-Konto ist nur unter Android verfügbar. Weiter mit „Weiter“.', muted: true);
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _foxText('Optional: Mit deinem FOX-Konto werden Theme, Favoriten und Fortschritt zwischen den FOX-Apps abgeglichen.', muted: true),
      const SizedBox(height: 12),
      if (_fox.loggedIn)
        _foxStatus('FOX-Konto', true, 'Angemeldet.')
      else ...[
        _FoxCard(order: 1, autofocus: true, onPressed: () async {
          final m = await _fox.signInViaStore();
          if (mounted) setState(() => _msg = m);
        }, child: _foxText(_fox.storeAvailable ? 'Über den FOX Store anmelden (SSO)' : 'FOX Store nicht installiert – unten mit Passwort anmelden', bold: true)),
        const SizedBox(height: 12),
        SizedBox(width: 420, child: TextField(controller: _user, decoration: const InputDecoration(labelText: 'Benutzername oder E-Mail'))),
        SizedBox(width: 420, child: TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Passwort'))),
        const SizedBox(height: 8),
        _FoxCard(order: 4, onPressed: () async {
          if (_user.text.trim().isEmpty || _pass.text.isEmpty) { setState(() => _msg = 'Bitte Benutzername und Passwort eingeben.'); return; }
          final m = await _fox.signInPassword(_user.text.trim(), _pass.text);
          _pass.clear();
          if (mounted) setState(() => _msg = m);
        }, child: _foxText('Anmelden', bold: true)),
      ],
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: _foxText(_msg!)),
    ]));
  }
}

// ---------------------------------------------------------------- 3 Jellyfin
class _FoxServerStep extends StatelessWidget {
  const _FoxServerStep({required this.client});
  final MediaServerClient? client;
  @override
  Widget build(BuildContext context) {
    final c = client;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _foxText('Pflicht: Foxfin braucht einen Jellyfin-Server. Server-Adresse und Anmeldung hast du beim Start eingegeben und sie wurden vom Server geprüft.', muted: true),
      const SizedBox(height: 12),
      _foxStatus('Server', c != null, c?.baseUrl ?? 'nicht verbunden'),
      _foxStatus('Anmeldung', c?.userId != null, c?.userId != null ? 'angemeldet' : 'fehlt'),
      _foxStatus('FOX-Shop', c?.baseUrl.contains('watch.pk187.site') ?? false, 'watch.pk187.site = FOX-Filmverleih; jeder andere eigene Server ist ebenfalls erlaubt'),
      const SizedBox(height: 12),
      _foxText('Anderen Server nutzen: Einstellungen › Konto › Server wechseln.', muted: true),
    ]);
  }
}

// ---------------------------------------------------------------- 4 Jellyseerr
class _FoxSeerrStep extends StatefulWidget {
  const _FoxSeerrStep({required this.prefs});
  final UserPreferences prefs;
  @override
  State<_FoxSeerrStep> createState() => _FoxSeerrStepState();
}

class _FoxSeerrStepState extends State<_FoxSeerrStep> {
  @override
  Widget build(BuildContext context) {
    final on = widget.prefs.get(UserPreferences.seerrEnabled);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _foxText('Optional: Jellyseerr für Film- und Serienanfragen. Anmeldung per URL + API-Schlüssel oder mit deinem Jellyfin-Login. Schlüssel werden verschlüsselt gespeichert und nie angezeigt.', muted: true),
      const SizedBox(height: 12),
      _foxStatus('Jellyseerr', on, on ? 'eingerichtet' : 'nicht eingerichtet – überspringbar'),
      const SizedBox(height: 12),
      _FoxCard(order: 1, autofocus: true, onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SeerrConfigScreen()));
        if (mounted) setState(() {});
      }, child: _foxText(on ? 'Jellyseerr bearbeiten' : 'Jellyseerr einrichten', bold: true)),
    ]);
  }
}

// ---------------------------------------------------------------- 5 Trakt / Simkl / TMDB
class _FoxServicesStep extends StatefulWidget {
  const _FoxServicesStep();
  @override
  State<_FoxServicesStep> createState() => _FoxServicesStepState();
}

class _FoxServicesStepState extends State<_FoxServicesStep> {
  final _svc = _tracking();
  @override
  void initState() { super.initState(); _svc.load().then((_) { if (mounted) setState(() {}); }); }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _foxText('Optional: Trakt und Simkl koppeln (Code am Handy eingeben) für Merkliste, Gesehen-Abgleich und Scrobble. TMDB liefert deutsche Beschreibungen und Bewertungen.', muted: true),
        const SizedBox(height: 12),
        _foxStatus('Trakt', _svc.isLinked('trakt'), TrackingConfig.traktAvailable ? (_svc.isLinked('trakt') ? 'gekoppelt' : 'nicht gekoppelt') : 'in diesem Build nicht verfügbar'),
        _foxStatus('Simkl', _svc.isLinked('simkl'), TrackingConfig.simklAvailable ? (_svc.isLinked('simkl') ? 'gekoppelt' : 'nicht gekoppelt') : 'in diesem Build nicht verfügbar'),
        _foxStatus('TMDB', TrackingConfig.tmdbAvailable, TrackingConfig.tmdbAvailable ? 'aktiv (de-DE)' : 'in diesem Build nicht verfügbar'),
        const SizedBox(height: 12),
        if (TrackingConfig.traktAvailable || TrackingConfig.simklAvailable)
          _FoxCard(order: 1, autofocus: true, onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TrackingScreen()));
            await _svc.load();
            if (mounted) setState(() {});
          }, child: _foxText('Trakt / Simkl koppeln', bold: true)),
      ]);
}

// ---------------------------------------------------------------- 6 Zusammenfassung
class _FoxSummaryStep extends StatelessWidget {
  const _FoxSummaryStep({required this.prefs, required this.client});
  final UserPreferences prefs;
  final MediaServerClient? client;
  @override
  Widget build(BuildContext context) {
    final theme = ThemeRegistry.availableThemes[AppThemeScope.of(context).activeSpec.id]?.displayName ?? '–';
    final fox = FoxSyncService.instance;
    final t = _tracking();
    final seerr = prefs.get(UserPreferences.seerrEnabled);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _foxStatus('Theme', true, theme),
      _foxStatus('FOX-Konto', fox.loggedIn, fox.loggedIn ? 'angemeldet' : 'übersprungen'),
      _foxStatus('Jellyfin', client?.userId != null, client?.baseUrl ?? '–'),
      _foxStatus('Jellyseerr', seerr, seerr ? 'eingerichtet' : 'übersprungen'),
      _foxStatus('Trakt', t.isLinked('trakt'), t.isLinked('trakt') ? 'gekoppelt' : 'übersprungen'),
      _foxStatus('Simkl', t.isLinked('simkl'), t.isLinked('simkl') ? 'gekoppelt' : 'übersprungen'),
      _foxStatus('TMDB', TrackingConfig.tmdbAvailable, TrackingConfig.tmdbAvailable ? 'aktiv' : 'nicht verfügbar'),
      const SizedBox(height: 12),
      _foxText('Alles änderbar unter Einstellungen. „Einrichtung erneut starten“ findest du unter Einstellungen › Über.', muted: true),
    ]);
  }
}
