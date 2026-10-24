// Foxfin 2.10.0: zentrale Fehlererfassung statt stiller leerer catch-Bloecke.
// Netzwerkfehler erscheinen als Hinweis mit "Erneut versuchen" (gedrosselt),
// alle anderen werden nur protokolliert.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FoxErrors {
  FoxErrors._();

  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Wird bei "Erneut versuchen" hochgezaehlt; Bildschirme koennen lauschen
  /// und neu laden.
  static final retryTick = ValueNotifier<int>(0);
  static final _retryCallbacks = <VoidCallback>{};
  static void onRetry(VoidCallback cb) => _retryCallbacks.add(cb);
  static void offRetry(VoidCallback cb) => _retryCallbacks.remove(cb);

  static DateTime _lastShown = DateTime.fromMillisecondsSinceEpoch(0);
  static int count = 0;

  static bool isNetwork(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HttpException ||
      e is HandshakeException ||
      (e is DioException &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout));

  static void report(Object e, [StackTrace? st]) {
    count++;
    if (kDebugMode) debugPrint('FoxErrors: $e');
    if (!isNetwork(e)) return;
    final now = DateTime.now();
    if (now.difference(_lastShown) < const Duration(seconds: 8)) return;
    _lastShown = now;
    final m = messengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: const Text('Verbindungsproblem – Server nicht erreichbar.'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Erneut versuchen', onPressed: retry),
    ));
  }

  static void retry() {
    retryTick.value++;
    for (final cb in List.of(_retryCallbacks)) {
      try {
        cb();
      } catch (e, st) {
        report(e, st);
      }
    }
  }
}

/// Leerzustand / Fehleranzeige mit "Erneut versuchen" fuer Listen und Seiten.
class FoxErrorState extends StatelessWidget {
  const FoxErrorState({super.key, this.message, required this.onRetry, this.icon = Icons.cloud_off_rounded});
  final String? message;
  final VoidCallback onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant, semanticLabel: 'Fehler'),
          const SizedBox(height: 16),
          Text(message ?? 'Inhalte konnten nicht geladen werden.',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          FilledButton.icon(
            autofocus: true,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Erneut versuchen'),
          ),
        ]),
      ),
    );
  }
}
