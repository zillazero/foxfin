import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:server_core/server_core.dart';

/// WebView trust callback: proceeds only for a certificate pinned for this
/// exact host:port, otherwise cancels (normal system validation applies
/// before this is ever asked).
Future<ServerTrustAuthResponse?> pinnedServerTrust(
  InAppWebViewController controller,
  URLAuthenticationChallenge challenge,
) async {
  final space = challenge.protectionSpace;
  final der = space.sslCertificate?.x509Certificate?.encoded;
  final port = (space.port == null || space.port! <= 0) ? 443 : space.port!;
  final ok =
      der != null && CertPinRegistry.instance.check(der, space.host, port);
  return ServerTrustAuthResponse(
    action: ok
        ? ServerTrustAuthResponseAction.PROCEED
        : ServerTrustAuthResponseAction.CANCEL,
  );
}
