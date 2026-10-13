// Foxfin: FOX account (SSO via FOX Store) settings.  GPL-2.0-or-later.
import 'dart:async';

import 'package:flutter/material.dart';

import 'fox_sync_service.dart';

class FoxAccountScreen extends StatefulWidget {
  const FoxAccountScreen({super.key});
  @override
  State<FoxAccountScreen> createState() => _FoxAccountScreenState();
}

class _FoxAccountScreenState extends State<FoxAccountScreen> {
  final s = FoxSyncService.instance;
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(s.refreshStatus());
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FOX-Konto')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.loggedIn
                ? 'Angemeldet über den FOX Store.'
                : s.storeAvailable
                    ? (s.storeLoggedIn
                        ? 'FOX Store gefunden – du kannst dich mit einem Klick anmelden.'
                        : 'Im FOX Store ist niemand angemeldet. Melde dich dort zuerst an.')
                    : 'FOX Store nicht gefunden.'),
            const SizedBox(height: 8),
            const Text(
              'Synchronisiert werden Design, Favoriten und Wiedergabe-Fortschritt – '
              'nur für Inhalte von watch.pk187.site, nie von privaten Servern – '
              'sowie der Verbindungsstatus von Trakt/Simkl (ohne Zugangsdaten).',
            ),
            const SizedBox(height: 16),
            if (!s.loggedIn)
              FilledButton.icon(
                autofocus: true,
                onPressed: s.busy ? null : () async => _toast(await s.signInViaStore()),
                icon: const Icon(Icons.login),
                label: const Text('Über FOX Store anmelden'),
              ),
            if (!s.loggedIn) ...[
              const SizedBox(height: 24),
              const Text('Oder mit Shop-Zugangsdaten anmelden:'),
              TextField(controller: _user, decoration: const InputDecoration(labelText: 'Benutzername oder E-Mail')),
              TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Passwort')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: s.busy
                    ? null
                    : () async {
                        final m = await s.signInPassword(_user.text.trim(), _pass.text);
                        _pass.clear();
                        _toast(m);
                      },
                child: const Text('Mit Passwort anmelden'),
              ),
            ]
            else ...[
              FilledButton.icon(
                autofocus: true,
                onPressed: s.busy ? null : () async => _toast(await s.syncAll()),
                icon: const Icon(Icons.sync),
                label: Text(s.busy ? 'Synchronisiere …' : 'Jetzt synchronisieren'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => s.signOut(),
                child: const Text('In Foxfin abmelden'),
              ),
              OutlinedButton(
                onPressed: () => s.signOut(all: true),
                child: const Text('Überall abmelden (alle FOX-Apps)'),
              ),
            ],
            if (s.lastMessage != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(s.lastMessage!)),
          ],
        ),
      ),
    );
  }
}
