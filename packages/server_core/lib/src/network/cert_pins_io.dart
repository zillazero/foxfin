import 'dart:io';

import 'cert_pins.dart';

/// A `badCertificateCallback` that accepts only pinned certificates.
bool certPinBadCertificateCallback(
  X509Certificate cert,
  String host,
  int port,
) => CertPinRegistry.instance.check(
  cert.der,
  host,
  port,
  subject: cert.subject,
  issuer: cert.issuer,
  validUntil: cert.endValidity,
);
