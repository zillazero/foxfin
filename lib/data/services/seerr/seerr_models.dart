import 'package:json_annotation/json_annotation.dart';

part 'seerr_models.g.dart';

class MoonfinProxyConfig {
  final String jellyfinBaseUrl;
  final String jellyfinToken;

  /// Foxfin direct mode: talk to a Jellyseerr/Seerr server directly instead of
  /// through the Moonfin server plugin. Null or empty keeps the plugin proxy.
  final String? directUrl;

  /// Optional Seerr API key (direct mode). Never logged or shown unmasked.
  final String? apiKey;

  /// Session cookie from a direct Jellyfin/local sign in (direct mode).
  final String? sessionCookie;

  const MoonfinProxyConfig({
    required this.jellyfinBaseUrl,
    required this.jellyfinToken,
    this.directUrl,
    this.apiKey,
    this.sessionCookie,
  });

  bool get isDirect => directUrl != null && directUrl!.trim().isNotEmpty;
}

/// Outcome of the password-less Quick Connect sign in. Parsed by hand from any
/// status code so the caller can read the plugin's errorCode, since an old
/// plugin answers the attempt with a generic 401 body.
class MoonfinQuickConnectResult {
  final bool success;
  final String? errorCode;
  final int? seerrUserId;
  final String? displayName;

  const MoonfinQuickConnectResult({
    this.success = false,
    this.errorCode,
    this.seerrUserId,
    this.displayName,
  });
}

@JsonSerializable()
class MoonfinStatusResponse {
  final bool enabled;
  final bool authenticated;
  final String? url;
  final int? seerrUserId;
  final String? displayName;
  final String? avatar;
  final int permissions;
  final int? sessionCreated;
  final int? lastValidated;

  const MoonfinStatusResponse({
    this.enabled = false,
    this.authenticated = false,
    this.url,
    this.seerrUserId,
    this.displayName,
    this.avatar,
    this.permissions = 0,
    this.sessionCreated,
    this.lastValidated,
  });

  factory MoonfinStatusResponse.fromJson(Map<String, dynamic> json) =>
      _$MoonfinStatusResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinStatusResponseToJson(this);
}

@JsonSerializable()
class MoonfinLoginRequest {
  final String username;
  final String password;
  final String authType;

  const MoonfinLoginRequest({
    required this.username,
    required this.password,
    this.authType = 'jellyfin',
  });

  factory MoonfinLoginRequest.fromJson(Map<String, dynamic> json) =>
      _$MoonfinLoginRequestFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinLoginRequestToJson(this);
}

@JsonSerializable()
class MoonfinLoginResponse {
  final bool success;
  final String? error;
  final int? seerrUserId;
  final String? displayName;
  final String? avatar;
  final int permissions;

  const MoonfinLoginResponse({
    this.success = false,
    this.error,
    this.seerrUserId,
    this.displayName,
    this.avatar,
    this.permissions = 0,
  });

  factory MoonfinLoginResponse.fromJson(Map<String, dynamic> json) =>
      _$MoonfinLoginResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinLoginResponseToJson(this);
}

@JsonSerializable()
class MoonfinValidateResponse {
  final bool valid;
  final int? lastValidated;

  const MoonfinValidateResponse({
    this.valid = false,
    this.lastValidated,
  });

  factory MoonfinValidateResponse.fromJson(Map<String, dynamic> json) =>
      _$MoonfinValidateResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinValidateResponseToJson(this);
}

@JsonSerializable()
class SeerrMainSettings {
  final String apiKey;

  const SeerrMainSettings({required this.apiKey});

  factory SeerrMainSettings.fromJson(Map<String, dynamic> json) =>
      _$SeerrMainSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$SeerrMainSettingsToJson(this);
}

@JsonSerializable()
class SeerrStatus {
  final String? version;
  final int? commitTag;
  final int? updateAvailable;
  final int? commitsBehind;

  const SeerrStatus({
    this.version,
    this.commitTag,
    this.updateAvailable,
    this.commitsBehind,
  });

  factory SeerrStatus.fromJson(Map<String, dynamic> json) =>
      _$SeerrStatusFromJson(json);

  Map<String, dynamic> toJson() => _$SeerrStatusToJson(this);
}

/// Title and poster for a request or issue card. The request and issue list
/// media objects only carry ids, so these come from the details endpoints.
class SeerrMediaSummary {
  final String? title;
  final String? posterPath;

  const SeerrMediaSummary({this.title, this.posterPath});
}
