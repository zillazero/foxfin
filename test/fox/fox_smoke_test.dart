// Foxfin 2.9.0: kurzer UI-Smoke-Test (Fokus per D-Pad, Zurück schließt Dialog,
// lokal ausgeblendete Titel, Backup-Filter für Geheimnisse).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/fox/fox_hidden_items.dart';
import 'package:moonfin/fox/fox_settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('D-Pad bewegt Fokus, Zurück schließt Dialog', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Column(children: [
          TextButton(autofocus: true, onPressed: () {}, child: const Text('A')),
          TextButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => const AlertDialog(content: Text('Dialog')),
            ),
            child: const Text('B'),
          ),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    expect(focused, isNotNull);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Dialog'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Dialog'), findsNothing);
  });

  test('Ausblenden + Backup-Filter', () async {
    SharedPreferences.setMockInitialValues({});
    await FoxHidden.load();
    await FoxHidden.hide('x1', 'Film');
    expect(FoxHidden.isHidden('x1'), isTrue);
    await FoxHidden.unhide('x1');
    expect(FoxHidden.isHidden('x1'), isFalse);
    for (final k in ['access_token', 'server_url', 'user_id', 'parental_pin', 'device_id']) {
      expect(foxBackupKeyAllowed(k), isFalse, reason: k);
    }
    for (final k in ['fox_image_size', 'pref_screensaver_enabled', 'media3_tunneling_disabled']) {
      expect(foxBackupKeyAllowed(k), isTrue, reason: k);
    }
  });
}
