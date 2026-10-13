// Foxfin: settings screen for Trakt / Simkl.  GPL-2.0-or-later, see NOTICE.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'tracker.dart';
import 'tracking_service.dart';

TrackingService _service() {
  if (!GetIt.instance.isRegistered<TrackingService>()) {
    GetIt.instance.registerSingleton<TrackingService>(TrackingService());
  }
  return GetIt.instance<TrackingService>();
}

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final TrackingService _t = _service();

  @override
  void initState() {
    super.initState();
    unawaited(_t.load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trakt & Simkl')),
      body: ListenableBuilder(
        listenable: _t,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Foxfin scrobbelt deine Wiedergabe und gleicht „Gesehen“, '
                'Merkliste (↔ Favoriten) und Weiterschauen mit deinem Server ab. '
                'Läuft auf dem Server bereits das Trakt- oder Simkl-Plugin, '
                'schalte hier „Scrobbeln“ aus, damit nichts doppelt gezählt wird.',
              ),
            ),
            for (final tr in _t.trackers.values) ..._trackerSection(tr),
            const SizedBox(height: 8),
            FilledButton.icon(
              autofocus: true,
              onPressed: _t.syncing || !_t.trackers.keys.any(_t.isLinked)
                  ? null
                  : () async {
                      final r = await _t.syncAll();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(r)));
                      }
                    },
              icon: _t.syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(_t.syncing ? 'Synchronisiere …' : 'Jetzt synchronisieren'),
            ),
            if (_t.lastReport != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_t.lastReport!),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _trackerSection(Tracker tr) {
    final linked = _t.isLinked(tr.id);
    final s = _t.settingsFor(tr.id);
    Widget sw(String title, bool v, void Function(bool) set) => SwitchListTile(
          title: Text(title),
          value: v,
          onChanged: linked
              ? (nv) {
                  set(nv);
                  unawaited(_t.saveSettings(tr.id));
                }
              : null,
        );
    return [
      ListTile(
        leading: Icon(linked ? Icons.link : Icons.link_off),
        title: Text(tr.displayName),
        subtitle: Text(linked ? 'Verbunden' : 'Nicht verbunden'),
        trailing: Text(linked ? 'Trennen' : 'Verbinden'),
        onTap: () => linked ? _t.storeToken(tr.id, null) : _connect(tr),
      ),
      sw('Scrobbeln', s.scrobble, (v) => s.scrobble = v),
      sw('Gesehen-Status synchronisieren (beide Richtungen)', s.syncWatched,
          (v) => s.syncWatched = v),
      sw('Merkliste ↔ Favoriten', s.syncWatchlist, (v) => s.syncWatchlist = v),
      sw('Weiterschauen übernehmen (nur Jellyfin)', s.syncResume,
          (v) => s.syncResume = v),
      const Divider(),
    ];
  }

  Future<void> _connect(Tracker tr) async {
    DeviceCode code;
    try {
      code = await tr.startDeviceAuth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${tr.displayName}: $e')));
      }
      return;
    }
    if (!mounted) return;
    var cancelled = false;
    final dialog = showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tr.displayName} verbinden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Öffne ${code.verificationUrl} und gib diesen Code ein:'),
            const SizedBox(height: 12),
            SelectableText(code.userCode,
                style: Theme.of(ctx).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: code.verificationUrl, size: 160),
            ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () {
              cancelled = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    unawaited(dialog.then((_) => cancelled = true));
    while (!cancelled && DateTime.now().isBefore(code.expiresAt)) {
      await Future<void>.delayed(code.interval);
      if (cancelled) break;
      try {
        final tok = await tr.pollDeviceAuth(code);
        if (tok != null) {
          await _t.storeToken(tr.id, tok);
          if (mounted) Navigator.of(context).pop();
          break;
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${tr.displayName}: $e')));
        }
        break;
      }
    }
  }
}
