import 'dart:convert';

import 'submission_json.dart' as j;

/// Borrowed account-specific credential port, never closed by an adapter.
///
/// Tokens are ephemeral and must never be serialized, logged or stored in queue
/// values. Platform authorization belongs to the provider; Core performs no
/// interactive authorization or implicit environment lookup.
abstract interface class SubmissionCredentialProvider {
  /// Returns a current bearer token for this exact configured connection, or
  /// null when explicit authorization is required. Provider failures become a
  /// safe retryable configuration failure; malformed tokens are rejected.
  Future<String?> bearerToken(String connectionId);
}

/// Immutable safe Google Drive target definition, without credentials or IO.
///
/// Once queued, [id] must keep the same account/folder identity. Secret rotation
/// may preserve that identity; silently retargeting it is unsupported.
final class DriveSubmissionConnection {
  /// Rejects unsafe ids, blank/overlong accounts and NUL/CR/LF with safe
  /// [ArgumentError] messages. Construction performs no IO on any platform.
  DriveSubmissionConnection({
    required String id,
    required String accountId,
    required String folderId,
  }) : id = j.token(id),
       accountId = _account(accountId),
       folderId = _driveId(folderId);

  /// Stable safe configuration identity referenced by durable intent.
  final String id;

  /// Explicit account identity used by the future secure credential owner.
  final String accountId;

  /// Exact existing Google Drive folder identity.
  final String folderId;

  /// Returns detached version 1 definition JSON; no token field exists.
  Map<String, Object?> toJson() => {
    'version': 1,
    'type': 'googleDrive',
    'id': id,
    'accountId': accountId,
    'folderId': folderId,
  };

  /// Decodes a closed version 1 schema, rejecting missing/extra keys and invalid
  /// types/values with [FormatException] that never includes supplied data.
  factory DriveSubmissionConnection.fromJson(Map<String, Object?> json) =>
      j.decode(() {
        final value = j.exact(json, {
          'version',
          'type',
          'id',
          'accountId',
          'folderId',
        });
        j.version(value);
        if (value['type'] != 'googleDrive') {
          throw const FormatException('Invalid connection type');
        }
        return DriveSubmissionConnection(
          id: j.string(value['id']),
          accountId: j.string(value['accountId']),
          folderId: j.string(value['folderId']),
        );
      });
}

/// Immutable explicit HTTPS submission endpoint definition, without IO/secrets.
///
/// Once referenced by queued intent, [id] must retain its target identity.
final class HttpSubmissionConnection {
  /// Requires an absolute HTTPS URI with host and absolute nonempty path,
  /// without user information, query or fragment. Explicit TLS ports are valid.
  /// Invalid input throws a safe [ArgumentError]; construction performs no IO.
  HttpSubmissionConnection({
    required String id,
    required Uri endpoint,
    this.requiresBearerToken = true,
  }) : id = j.token(id),
       endpoint = _endpoint(endpoint);

  /// Stable safe configuration identity referenced by durable intent.
  final String id;

  /// Exact configured endpoint, including its encoded path and explicit port.
  final Uri endpoint;

  /// True requests account-specific credentials; false explicitly permits an
  /// anonymous POST and makes no credential provider call.
  final bool requiresBearerToken;

  /// Returns detached closed version 1 JSON, retaining the encoded URI exactly.
  Map<String, Object?> toJson() => {
    'version': 1,
    'type': 'http',
    'id': id,
    'endpoint': endpoint.toString(),
    'requiresBearerToken': requiresBearerToken,
  };

  /// Rejects unknown/missing keys, versions, types and unsafe values through
  /// safe [FormatException] messages without reflecting supplied data.
  factory HttpSubmissionConnection.fromJson(Map<String, Object?> json) =>
      j.decode(() {
        final value = j.exact(json, {
          'version',
          'type',
          'id',
          'endpoint',
          'requiresBearerToken',
        });
        j.version(value);
        final uri = Uri.tryParse(j.string(value['endpoint']));
        if (value['type'] != 'http' || uri == null) {
          throw const FormatException('Invalid HTTP connection');
        }
        return HttpSubmissionConnection(
          id: j.string(value['id']),
          endpoint: uri,
          requiresBearerToken: j.boolean(value['requiresBearerToken']),
        );
      });
}

String _account(String value) {
  if (value.trim().isEmpty ||
      utf8.encode(value).length > 256 ||
      value.contains(RegExp(r'[\x00\r\n]'))) {
    throw ArgumentError('Invalid account identity');
  }
  return value;
}

String _driveId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(value)) {
    throw ArgumentError('Invalid Drive identity');
  }
  return value;
}

Uri _endpoint(Uri value) {
  if (value.scheme != 'https' ||
      !value.hasAuthority ||
      value.host.isEmpty ||
      value.path.isEmpty ||
      !value.path.startsWith('/') ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment) {
    throw ArgumentError('Invalid HTTPS submission endpoint');
  }
  return value;
}
