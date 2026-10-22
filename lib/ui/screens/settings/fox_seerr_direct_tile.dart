// Foxfin: direct Jellyseerr/Seerr connection (no Moonfin server plugin needed).
// No server URL or credential is preconfigured; everything comes from the user.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../../../auth/repositories/session_repository.dart';
import '../../../data/repositories/seerr_repository.dart';
import '../../../preference/seerr_direct_store.dart';

String _t(BuildContext c, String de, String en) =>
    Localizations.localeOf(c).languageCode == 'de' ? de : en;

class FoxSeerrDirectTile extends StatefulWidget {
  final Future<void> Function() onChanged;
  const FoxSeerrDirectTile({super.key, required this.onChanged});

  @override
  State<FoxSeerrDirectTile> createState() => _FoxSeerrDirectTileState();
}

class _FoxSeerrDirectTileState extends State<FoxSeerrDirectTile> {
  String? _url;
  String? _key;

  String? get _uid => GetIt.instance<SessionRepository>().activeUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    final url = await SeerrDirectStore.url(uid);
    final key = await SeerrDirectStore.apiKey(uid);
    if (mounted) setState(() {
      _url = url;
      _key = key;
    });
  }

  Future<void> _edit() async {
    final result = await showDialog<_DirectResult>(
      context: context,
      builder: (_) => _FoxSeerrDirectDialog(initialUrl: _url ?? '', hasKey: (_key ?? '').isNotEmpty),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      final st = await repo.configureDirect(
        url: result.remove ? '' : result.url,
        apiKey: result.remove ? null : result.apiKey,
      );
      await _load();
      await widget.onChanged();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(result.remove
            ? _t(context, 'Direkte Verbindung entfernt', 'Direct connection removed')
            : st.authenticated
                ? _t(context, 'Verbunden als ${st.displayName ?? ''}', 'Connected as ${st.displayName ?? ''}')
                : _t(context, 'Server gespeichert – bitte unten anmelden', 'Server saved – please sign in below')),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(_t(context, 'Verbindung fehlgeschlagen', 'Connection failed')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final configured = (_url ?? '').isNotEmpty;
    final subtitle = configured
        ? '${_url!}${(_key ?? '').isNotEmpty ? '  ·  API-Key ${SeerrDirectStore.mask(_key)}' : ''}'
        : _t(context, 'Jellyseerr-Server direkt verbinden (ohne Server-Plugin)',
            'Connect a Jellyseerr server directly (no server plugin)');
    return ListTile(
      leading: Icon(configured ? Icons.link : Icons.add_link, color: cs.primary),
      title: Text(_t(context, 'Jellyseerr-Server', 'Jellyseerr server')),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: _edit,
    );
  }
}

class _DirectResult {
  final String url;
  final String? apiKey; // null = keep stored key
  final bool remove;
  const _DirectResult(this.url, this.apiKey, {this.remove = false});
}

class _FoxSeerrDirectDialog extends StatefulWidget {
  final String initialUrl;
  final bool hasKey;
  const _FoxSeerrDirectDialog({required this.initialUrl, required this.hasKey});

  @override
  State<_FoxSeerrDirectDialog> createState() => _FoxSeerrDirectDialogState();
}

class _FoxSeerrDirectDialogState extends State<_FoxSeerrDirectDialog> {
  late final _url = TextEditingController(text: widget.initialUrl);
  final _key = TextEditingController();
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  void _save() {
    final u = _url.text.trim();
    final p = Uri.tryParse(u);
    if (p == null || !(p.isScheme('http') || p.isScheme('https')) || p.host.isEmpty) {
      setState(() => _error = _t(context, 'Bitte eine gültige http(s)-Adresse eingeben', 'Please enter a valid http(s) URL'));
      return;
    }
    final k = _key.text.trim();
    Navigator.pop(context, _DirectResult(u, k.isEmpty ? null : k));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      title: Text(_t(context, 'Jellyseerr verbinden', 'Connect Jellyseerr')),
      content: SizedBox(
        width: 460,
        child: FocusTraversalGroup(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              decoration: InputDecoration(
                labelText: _t(context, 'Server-Adresse', 'Server URL'),
                hintText: 'https://…',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: !_show,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: _t(context, 'API-Key (optional)', 'API key (optional)'),
                helperText: widget.hasKey
                    ? _t(context, 'Gespeichert – leer lassen zum Behalten', 'Stored – leave empty to keep')
                    : _t(context, 'Ohne Key: unten mit Jellyfin- oder lokalem Konto anmelden',
                        'Without key: sign in below with Jellyfin or local account'),
                suffixIcon: IconButton(
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        if (widget.initialUrl.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, const _DirectResult('', null, remove: true)),
            child: Text(_t(context, 'Entfernen', 'Remove'), style: TextStyle(color: cs.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_t(context, 'Abbrechen', 'Cancel'))),
        FilledButton(onPressed: _save, child: Text(_t(context, 'Speichern', 'Save'))),
      ],
    );
  }
}
