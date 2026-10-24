import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Trust-on-first-use certificate pinning.
///
/// Replaces the old global "allow self-signed certificates" switch. A
/// certificate the system trusts never reaches this code, because dart:io and
/// the native stacks only ask about certificates that failed normal
/// validation. For those, exactly one certificate per `host:port` is accepted:
/// the one the user confirmed by its SHA-256 fingerprint. Every other host
/// keeps normal validation, and a changed certificate is rejected until the
/// user confirms the new fingerprint.
class CertPin {
  const CertPin({
    required this.host,
    required this.port,
    required this.sha256,
    this.derBase64,
    this.pinnedAt,
  });

  final String host;
  final int port;

  /// Upper-case hex with colons, `AA:BB:...`.
  final String sha256;

  /// The pinned certificate itself, so engines that can only be given a trust
  /// anchor (not a fingerprint) can still be restricted to it.
  final String? derBase64;
  final DateTime? pinnedAt;

  String get key => certPinKey(host, port);

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'sha256': sha256,
    if (derBase64 != null) 'der': derBase64,
    if (pinnedAt != null) 'pinnedAt': pinnedAt!.toUtc().toIso8601String(),
  };

  static CertPin? fromJson(Object? json) {
    if (json is! Map) return null;
    final host = json['host'];
    final port = json['port'];
    final sha = json['sha256'];
    if (host is! String || port is! int || sha is! String) return null;
    return CertPin(
      host: host.toLowerCase(),
      port: port,
      sha256: normalizeFingerprint(sha),
      derBase64: json['der'] as String?,
      pinnedAt: DateTime.tryParse('${json['pinnedAt'] ?? ''}'),
    );
  }
}

/// A handshake that was refused because its certificate isn't pinned.
class CertPinChallenge {
  CertPinChallenge({
    required this.host,
    required this.port,
    required this.sha256,
    required this.derBase64,
    required this.subject,
    required this.issuer,
    required this.validUntil,
    this.previousSha256,
  });

  final String host;
  final int port;
  final String sha256;
  final String derBase64;
  final String subject;
  final String issuer;
  final DateTime? validUntil;

  /// Set when a different certificate was pinned for this host before, which
  /// is the case a user has to be warned about.
  final String? previousSha256;

  bool get isChange => previousSha256 != null;
  String get key => certPinKey(host, port);
}

String certPinKey(String host, int port) => '${host.toLowerCase()}:$port';

int defaultPortFor(Uri uri) {
  if (uri.hasPort && uri.port != 0) return uri.port;
  return (uri.isScheme('https') || uri.isScheme('wss')) ? 443 : 80;
}

String certFingerprint(List<int> der) {
  final digest = sha256.convert(der).bytes;
  return digest
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}

String normalizeFingerprint(String value) {
  final hex = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
  final parts = <String>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    parts.add(hex.substring(i, i + 2));
  }
  return parts.join(':');
}

/// Writes the pins somewhere durable (FlutterSecureStorage in the app).
typedef CertPinPersist = Future<void> Function(String json);

class CertPinRegistry {
  CertPinRegistry._();

  static final CertPinRegistry instance = CertPinRegistry._();

  final Map<String, CertPin> _pins = {};
  final Map<String, CertPinChallenge> _rejections = {};
  String? _latestKey;
  final _challenges = StreamController<CertPinChallenge>.broadcast(sync: false);
  final _changes = StreamController<void>.broadcast();
  CertPinPersist? _persist;

  /// Every refused certificate, for a UI that offers to confirm it.
  Stream<CertPinChallenge> get challenges => _challenges.stream;

  /// Fires after the set of pins changed.
  Stream<void> get changes => _changes.stream;

  List<CertPin> get pins =>
      _pins.values.toList()..sort((a, b) => a.key.compareTo(b.key));

  CertPin? pinFor(String host, int port) => _pins[certPinKey(host, port)];

  bool hasPinForHost(String host) {
    final h = host.toLowerCase();
    return _pins.values.any((p) => p.host == h);
  }

  /// The last refused certificate for [host]:[port], if any.
  CertPinChallenge? lastRejection(String host, int port) =>
      _rejections[certPinKey(host, port)];

  /// The most recent refused certificate on any host.
  CertPinChallenge? get latestRejection =>
      _latestKey == null ? null : _rejections[_latestKey];

  CertPinChallenge? lastRejectionFor(Uri uri) =>
      lastRejection(uri.host, defaultPortFor(uri));

  void setPersistence(CertPinPersist? persist) => _persist = persist;

  /// Loads pins serialized by [toJsonString]. Bad input leaves no pins.
  void loadJson(String? json) {
    _pins.clear();
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json);
      if (list is! List) return;
      for (final e in list) {
        final pin = CertPin.fromJson(e);
        if (pin != null) _pins[pin.key] = pin;
      }
    } catch (_) {
      _pins.clear();
    }
    _changes.add(null);
  }

  String toJsonString() =>
      jsonEncode(pins.map((p) => p.toJson()).toList(growable: false));

  /// Pins for an isolate, which starts with empty globals.
  Map<String, String> toIsolateMap() => {
    for (final p in _pins.values) p.key: p.sha256,
  };

  void loadIsolateMap(Map<String, String> map) {
    _pins
      ..clear()
      ..addEntries(
        map.entries.map((e) {
          final i = e.key.lastIndexOf(':');
          final pin = CertPin(
            host: e.key.substring(0, i),
            port: int.parse(e.key.substring(i + 1)),
            sha256: e.value,
          );
          return MapEntry(pin.key, pin);
        }),
      );
  }

  /// The decision for a certificate that failed system validation.
  ///
  /// [derBytes] is the DER of the leaf certificate presented by [host]:[port].
  bool check(
    List<int> derBytes,
    String host,
    int port, {
    String subject = '',
    String issuer = '',
    DateTime? validUntil,
  }) {
    final fingerprint = certFingerprint(derBytes);
    final key = certPinKey(host, port);
    final pinned = _pins[key];
    if (pinned != null && pinned.sha256 == fingerprint) {
      _rejections.remove(key);
      return true;
    }
    final challenge = CertPinChallenge(
      host: host.toLowerCase(),
      port: port,
      sha256: fingerprint,
      derBase64: base64Encode(derBytes),
      subject: subject,
      issuer: issuer,
      validUntil: validUntil,
      previousSha256: pinned?.sha256,
    );
    final previous = _rejections[key];
    _rejections[key] = challenge;
    _latestKey = key;
    if (previous?.sha256 != fingerprint && !_challenges.isClosed) {
      _challenges.add(challenge);
    }
    return false;
  }

  /// Trusts [challenge]'s certificate for its host and port from now on.
  Future<void> confirm(CertPinChallenge challenge) => pin(
    CertPin(
      host: challenge.host,
      port: challenge.port,
      sha256: challenge.sha256,
      derBase64: challenge.derBase64,
      pinnedAt: DateTime.now(),
    ),
  );

  Future<void> pin(CertPin pin) async {
    _pins[pin.key] = pin;
    _rejections.remove(pin.key);
    await _save();
  }

  Future<void> remove(String key) async {
    if (_pins.remove(key) == null) return;
    await _save();
  }

  Future<void> clear() async {
    _pins.clear();
    _rejections.clear();
    await _save();
  }

  Future<void> _save() async {
    _changes.add(null);
    await _persist?.call(toJsonString());
  }

  /// Test hook.
  void resetForTest() {
    _pins.clear();
    _rejections.clear();
    _persist = null;
  }
}
