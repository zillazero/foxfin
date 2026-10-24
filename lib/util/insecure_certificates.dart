// Foxfin 2.9.2: the global "allow self-signed certificates" switch is gone.
// Untrusted certificates are accepted only once pinned per host:port.
export 'package:server_core/server_core.dart'
    show CertPin, CertPinChallenge, CertPinRegistry, certPinKey, defaultPortFor;
export 'cert_pin_store.dart';
