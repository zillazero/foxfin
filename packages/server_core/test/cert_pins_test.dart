import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

void main() {
  final registry = CertPinRegistry.instance;
  tearDown(registry.resetForTest);

  test('fingerprint is colon separated upper-case SHA-256', () {
    final fp = certFingerprint([1, 2, 3]);
    expect(fp.split(':'), hasLength(32));
    expect(fp, fp.toUpperCase());
    expect(normalizeFingerprint(fp.toLowerCase().replaceAll(':', '')), fp);
  });

  test('unknown certificate is refused and recorded', () {
    expect(registry.check([1, 2, 3], 'Server.lan', 8920), isFalse);
    final c = registry.lastRejection('server.lan', 8920)!;
    expect(c.isChange, isFalse);
    expect(c.sha256, certFingerprint([1, 2, 3]));
  });

  test(
    'confirmed certificate is accepted only for its host and port',
    () async {
      registry.check([1, 2, 3], 'server.lan', 8920);
      await registry.confirm(registry.lastRejection('server.lan', 8920)!);
      expect(registry.check([1, 2, 3], 'server.lan', 8920), isTrue);
      expect(registry.check([1, 2, 3], 'server.lan', 443), isFalse);
      expect(registry.check([1, 2, 3], 'other.lan', 8920), isFalse);
    },
  );

  test('changed certificate is refused and flagged as change', () async {
    registry.check([1, 2, 3], 'server.lan', 8920);
    await registry.confirm(registry.lastRejection('server.lan', 8920)!);
    final events = <CertPinChallenge>[];
    final sub = registry.challenges.listen(events.add);
    expect(registry.check([9, 9, 9], 'server.lan', 8920), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.isChange, isTrue);
    expect(events.single.previousSha256, certFingerprint([1, 2, 3]));
    await sub.cancel();
  });

  test('persists and reloads, remove and clear', () async {
    String? saved;
    registry.setPersistence((json) async => saved = json);
    registry.check([1], 'a', 1);
    await registry.confirm(registry.lastRejection('a', 1)!);
    registry.check([2], 'b', 2);
    await registry.confirm(registry.lastRejection('b', 2)!);
    registry.loadJson(saved);
    expect(registry.pins.map((p) => p.key), ['a:1', 'b:2']);
    await registry.remove('a:1');
    expect(registry.pins.map((p) => p.key), ['b:2']);
    registry.loadJson(saved);
    expect(registry.pins, hasLength(1));
    await registry.clear();
    expect(registry.pins, isEmpty);
  });

  test('isolate map round trip', () async {
    await registry.pin(const CertPin(host: 'h', port: 5, sha256: 'AA:BB'));
    final map = registry.toIsolateMap();
    registry.resetForTest();
    registry.loadIsolateMap(map);
    expect(registry.pinFor('h', 5)!.sha256, 'AA:BB');
  });

  test('corrupt storage yields no pins', () {
    registry.loadJson('{nope');
    expect(registry.pins, isEmpty);
  });
}
