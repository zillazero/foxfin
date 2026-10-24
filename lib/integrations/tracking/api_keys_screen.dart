import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'tracking_config.dart';
import 'tracking_service.dart';

/// Foxfin 2.10.0: eigene API-Schlüssel (verschlüsselt gespeichert, nie geloggt).
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});
  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  late final _c = {
    TrackingConfig.kTraktId: TextEditingController(text: TrackingConfig.traktClientId),
    TrackingConfig.kTraktSecret: TextEditingController(text: TrackingConfig.traktClientSecret),
    TrackingConfig.kSimklId: TextEditingController(text: TrackingConfig.simklClientId),
    TrackingConfig.kTmdb: TextEditingController(text: TrackingConfig.tmdbApiKey),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    for (final e in _c.entries) {
      await TrackingConfig.save(e.key, e.value.text);
    }
    if (GetIt.instance.isRegistered<TrackingService>()) {
      GetIt.instance<TrackingService>().refreshTrackers();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schlüssel gespeichert.')));
    Navigator.of(context).maybePop();
  }

  Widget _field(String label, String key, {bool secret = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: _c[key],
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget _hint(String title, String hint) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Eigene API-Schlüssel')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Optional. Leer = Dienst aus und ausgeblendet. Schlüssel werden verschlüsselt auf diesem Gerät gespeichert.'),
          _hint('Trakt', TrackingConfig.hintTrakt),
          _field('Trakt Client-ID', TrackingConfig.kTraktId),
          _field('Trakt Client-Secret', TrackingConfig.kTraktSecret, secret: true),
          _hint('Simkl', TrackingConfig.hintSimkl),
          _field('Simkl Client-ID', TrackingConfig.kSimklId),
          _hint('TMDB', TrackingConfig.hintTmdb),
          _field('TMDB API-Schlüssel (v3)', TrackingConfig.kTmdb, secret: true),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Speichern')),
        ]),
      );
}
