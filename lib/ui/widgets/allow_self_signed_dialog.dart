import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/insecure_certificates.dart';
import 'adaptive/adaptive_dialog.dart';
import 'overlay_sheet.dart';

/// German texts for certificate pinning (Trust on First Use).
abstract final class CertPinTexts {
  static const title = 'Unbekanntes Serverzertifikat';
  static const changedTitle = 'Serverzertifikat hat sich geändert!';
  static const intro =
      'Der Server verwendet ein Zertifikat, dem dein Gerät nicht vertraut '
      '(z. B. selbstsigniert). Vergleiche den SHA-256-Fingerabdruck mit dem '
      'deines Servers. Nach der Bestätigung akzeptiert Foxfin genau dieses '
      'Zertifikat – und nur für diesen Server.';
  static const changedIntro =
      'Achtung: Für diesen Server ist ein anderes Zertifikat gespeichert. '
      'Die Verbindung wurde blockiert. Das kann ein erneuertes Zertifikat '
      'sein – oder ein Angriff. Bestätige nur, wenn du das Zertifikat selbst '
      'erneuert hast.';
  static const server = 'Server';
  static const fingerprint = 'SHA-256-Fingerabdruck';
  static const previous = 'Bisher gespeichert';
  static const subject = 'Ausgestellt für';
  static const issuer = 'Aussteller';
  static const validUntil = 'Gültig bis';
  static const trust = 'Vertrauen';
  static const reconfirm = 'Neu bestätigen';
  static const cancel = 'Abbrechen';
  static const block = 'Blockieren';
  static const noChallenge =
      'Es wurde noch kein Zertifikat dieses Servers erfasst. Bitte erneut '
      'verbinden und es dann noch einmal versuchen.';
  static const ok = 'OK';
  static const settingsTitle = 'Gespeicherte Zertifikate';
  static const settingsSubtitle =
      'Bestätigte Server-Fingerabdrücke anzeigen oder zurücksetzen';
  static const managerEmpty = 'Keine Zertifikate gespeichert.';
  static const remove = 'Entfernen';
  static const resetAll = 'Alle zurücksetzen';
  static const resetAllConfirm =
      'Alle gespeicherten Zertifikate löschen? Beim nächsten Verbinden '
      'musst du sie erneut bestätigen.';
  static const close = 'Schließen';
  static const copied = 'Fingerabdruck kopiert';
  static const pinnedAt = 'Bestätigt am';
  static const checkCertificate = 'Zertifikat prüfen';
}

/// Called from the sign-in screens when a server's certificate was refused.
/// Shows the certificate captured for [address] (or the latest refused one)
/// and pins it once confirmed. Returns true when it was pinned.
Future<bool> confirmAllowSelfSignedCertificates(
  BuildContext context, [
  String? address,
]) async {
  final registry = CertPinRegistry.instance;
  final uri = address == null ? null : Uri.tryParse(address);
  final challenge =
      (uri != null && uri.host.isNotEmpty
          ? registry.lastRejectionFor(uri)
          : null) ??
      registry.latestRejection;
  if (challenge == null) {
    await showFocusRestoringDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text(CertPinTexts.title),
        content: const Text(CertPinTexts.noChallenge),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(CertPinTexts.ok),
          ),
        ],
      ),
    );
    return false;
  }
  return showCertPinDialog(context, challenge);
}

/// The FOX dialog that shows a certificate's fingerprint and pins it.
Future<bool> showCertPinDialog(
  BuildContext context,
  CertPinChallenge challenge,
) async {
  final changed = challenge.isChange;
  final confirmed = await showFocusRestoringDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final mono = theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        letterSpacing: 0.5,
      );
      Widget row(String label, String value, {TextStyle? style}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            SelectableText(value, style: style ?? theme.textTheme.bodySmall),
          ],
        ),
      );
      return AlertDialog.adaptive(
        icon: Icon(
          changed ? Icons.gpp_bad : Icons.gpp_maybe,
          color: changed ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        title: Text(changed ? CertPinTexts.changedTitle : CertPinTexts.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(changed ? CertPinTexts.changedIntro : CertPinTexts.intro),
              row(CertPinTexts.server, challenge.key),
              row(CertPinTexts.fingerprint, challenge.sha256, style: mono),
              if (changed)
                row(
                  CertPinTexts.previous,
                  challenge.previousSha256!,
                  style: mono,
                ),
              if (challenge.subject.isNotEmpty)
                row(CertPinTexts.subject, challenge.subject),
              if (challenge.issuer.isNotEmpty)
                row(CertPinTexts.issuer, challenge.issuer),
              if (challenge.validUntil != null)
                row(CertPinTexts.validUntil, _date(challenge.validUntil!)),
            ],
          ),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(changed ? CertPinTexts.block : CertPinTexts.cancel),
          ),
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(true),
            isDestructive: changed,
            child: Text(changed ? CertPinTexts.reconfirm : CertPinTexts.trust),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return false;
  await CertPinRegistry.instance.confirm(challenge);
  return true;
}

/// Settings: lists the pinned fingerprints and lets them be reset.
Future<void> showCertPinManager(BuildContext context) {
  return showFocusRestoringDialog<void>(
    context: context,
    builder: (ctx) => const _CertPinManager(),
  );
}

class _CertPinManager extends StatefulWidget {
  const _CertPinManager();

  @override
  State<_CertPinManager> createState() => _CertPinManagerState();
}

class _CertPinManagerState extends State<_CertPinManager> {
  final _registry = CertPinRegistry.instance;

  Future<void> _resetAll() async {
    final ok = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text(CertPinTexts.resetAll),
        content: const Text(CertPinTexts.resetAllConfirm),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(CertPinTexts.cancel),
          ),
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(true),
            isDestructive: true,
            child: const Text(CertPinTexts.resetAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _registry.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pins = _registry.pins;
    return AlertDialog.adaptive(
      title: const Text(CertPinTexts.settingsTitle),
      content: SizedBox(
        width: 520,
        child: pins.isEmpty
            ? const Text(CertPinTexts.managerEmpty)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final pin in pins)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user),
                      title: Text(pin.key),
                      subtitle: Text(
                        '${pin.sha256}'
                        '${pin.pinnedAt == null ? '' : '\n${CertPinTexts.pinnedAt}: ${_date(pin.pinnedAt!)}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      isThreeLine: pin.pinnedAt != null,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: pin.sha256));
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(content: Text(CertPinTexts.copied)),
                        );
                      },
                      trailing: IconButton(
                        tooltip: CertPinTexts.remove,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _registry.remove(pin.key);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        if (pins.isNotEmpty)
          adaptiveDialogAction(
            onPressed: _resetAll,
            isDestructive: true,
            child: const Text(CertPinTexts.resetAll),
          ),
        adaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(CertPinTexts.close),
        ),
      ],
    );
  }
}

String _date(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year}';
}
