import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/user_views_repository.dart';
import '../../../fox/fox_errors.dart';

/// Foxfin 2.10.0: oeffnet eine Bibliothek anhand ihres Namens (z. B. "Aufnahmen"
/// aus dem FOX-Player). Der Name kommt nur aus der Allowlist des DeepLinkService.
class FoxLibraryByNameScreen extends StatefulWidget {
  const FoxLibraryByNameScreen({super.key, required this.name});
  final String name;

  @override
  State<FoxLibraryByNameScreen> createState() => _FoxLibraryByNameScreenState();
}

class _FoxLibraryByNameScreenState extends State<FoxLibraryByNameScreen> {
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final libs = await GetIt.instance<UserViewsRepository>().getAllViewsIncludingHidden();
      final want = widget.name.toLowerCase();
      for (final l in libs) {
        if (l.name.toLowerCase() == want) {
          if (!mounted) return;
          context.go('/library/${l.id}?serverId=${Uri.encodeQueryComponent(l.serverId)}');
          return;
        }
      }
    } catch (e, st) {
      FoxErrors.report(e, st);
    }
    if (mounted) setState(() => _notFound = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _notFound
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Bibliothek „${widget.name}“ nicht gefunden.',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                      'Fertige Aufnahmen erscheinen hier, sobald der FOX-Player sie hochgeladen '
                      'und Jellyfin die Bibliothek gescannt hat.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    autofocus: true,
                    onPressed: () => context.go('/'),
                    child: const Text('Zur Startseite'),
                  ),
                ]),
              )
            : const CircularProgressIndicator(semanticsLabel: 'Bibliothek wird geladen'),
      ),
    );
  }
}
