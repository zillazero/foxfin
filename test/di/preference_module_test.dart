import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/di/modules/preference_module.dart';
import 'package:moonfin/util/insecure_certificates.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await GetIt.instance.reset();
    CertPinRegistry.instance.resetForTest();
  });

  test('an old global opt-in no longer trusts any certificate', () async {
    SharedPreferences.setMockInitialValues({
      'pref_allow_self_signed_certs': true,
    });
    final store = PreferenceStore();
    await store.init();
    registerPreferenceModule(store);

    expect(CertPinRegistry.instance.pins, isEmpty);
    expect(
      CertPinRegistry.instance.check([1, 2, 3], 'server.lan', 8920),
      isFalse,
    );
  });
}
