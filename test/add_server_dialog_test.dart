import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/auth/server_select_screen.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/ui/widgets/overlay_sheet.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/auth/models/server_addition_state.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/util/insecure_certificates.dart';
import 'package:moonfin/ui/widgets/allow_self_signed_dialog.dart';

class _MockServerRepository extends Mock implements ServerRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    ThemeRegistry.setActiveById(ThemeRegistry.moonfinId);
  });

  tearDown(() async {
    await GetIt.instance.reset();
    CertPinRegistry.instance.resetForTest();
  });

  Future<({TextEditingController controller, Future<void> closed})> openDialog(
    WidgetTester tester, {
    ServerRepository? serverRepo,
  }) async {
    final controller = TextEditingController(text: 'http://localhos');
    late Future<void> closed;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                // Same presentation path as the real screen: the dialog is
                // wrapped by showFocusRestoringDialog's back-key handler.
                closed = showFocusRestoringDialog<void>(
                  context: context,
                  builder: (ctx) => AddServerDialog(
                    l10n: AppLocalizations.of(ctx),
                    controller: controller,
                    serverRepo: serverRepo ?? _MockServerRepository(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return (controller: controller, closed: closed);
  }

  testWidgets('backspace deletes text instead of closing the dialog', (
    tester,
  ) async {
    final (:controller, :closed) = await openDialog(tester);
    var didClose = false;
    closed.then((_) => didClose = true);

    // Desktop branch: plain TextField, autofocused on open.
    expect(find.byType(TextField), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(find.byType(AddServerDialog), findsOneWidget);
    expect(didClose, isFalse);
    expect(controller.text, 'http://localho');
  });

  testWidgets('backspace still closes the dialog when not editing text', (
    tester,
  ) async {
    final (:controller, :closed) = await openDialog(tester);
    var didClose = false;
    closed.then((_) => didClose = true);

    // Move focus off the field onto the Cancel button: backspace is now
    // "back", not text editing.
    tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
        .focusNode
        ?.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(didClose, isTrue);
    expect(controller.text, 'http://localhos');
  });

  testWidgets('an untrusted certificate offers to pin its fingerprint', (
    tester,
  ) async {
    final repo = _MockServerRepository();
    when(() => repo.addServer(any())).thenAnswer((_) async => null);
    when(() => repo.lastFailure).thenReturn(
      const ServerUnableToConnect(
        candidatesTried: ['https://localhos', 'http://localhos'],
        untrustedCandidate: 'https://localhos',
      ),
    );
    // What the failed handshake would have recorded.
    CertPinRegistry.instance.check([1, 2, 3], 'localhos', 443);
    await openDialog(tester, serverRepo: repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.untrustedServerCertificate), findsOneWidget);

    await tester.tap(
      find.widgetWithText(OutlinedButton, CertPinTexts.checkCertificate),
    );
    await tester.pumpAndSettle();
    expect(find.text(CertPinTexts.title), findsOneWidget);
    await tester.tap(find.text(CertPinTexts.trust));
    await tester.pumpAndSettle();

    expect(CertPinRegistry.instance.pinFor('localhos', 443), isNotNull);
    expect(CertPinRegistry.instance.check([1, 2, 3], 'localhos', 443), isTrue);
    expect(CertPinRegistry.instance.check([1, 2, 3], 'other', 443), isFalse);
    verify(() => repo.addServer('https://localhos')).called(1);
  });
}
