import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

/// What the engine is told about certificates the system will not vouch for.
///
/// The preference is one switch, but the engine decides per origin. A user with
/// a self signed server on the LAN and a second one behind a real certificate
/// should not have the second relaxed along with the first, so the hosts the
/// switch was meant for travel with it.
class EngineTrust {
  const EngineTrust({required this.enabled, required this.hosts});

  final bool enabled;
  final List<String> hosts;

  /// Foxfin 2.9.2: derived from the pinned certificates (Trust on First
  /// Use). Only hosts with a pinned certificate are relaxed for the engine,
  /// and only while at least one pin exists. These engines can't check a
  /// fingerprint themselves, so the Dart side still enforces the exact pin
  /// for everything that goes through it.
  factory EngineTrust.current() {
    final hosts = <String>{
      for (final pin in CertPinRegistry.instance.pins) pin.host,
    };
    if (hosts.isEmpty) return const EngineTrust(enabled: false, hosts: []);
    return EngineTrust(enabled: true, hosts: hosts.toList()..sort());
  }

  bool matches(EngineTrust? other) =>
      other != null &&
      other.enabled == enabled &&
      listEquals(other.hosts, hosts);

  Map<String, Object?> toChannelArguments() => {
    'enabled': enabled,
    'hosts': hosts,
  };
}
