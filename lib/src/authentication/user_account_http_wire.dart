import 'dart:convert';

import 'user_account_authentication.dart';

/// Internal decoded wire data, without transport or authentication authority.
sealed class UserAccountHttpWireLoginResult {
  const UserAccountHttpWireLoginResult._();
}

/// Sensitive session material for a future Core-owned transport backend.
final class UserAccountHttpWireSessionPair
    extends UserAccountHttpWireLoginResult {
  const UserAccountHttpWireSessionPair._({
    required this.userAccountId,
    required this.credentialId,
    required this.accessSessionId,
    required this.accessToken,
    required this.refreshSessionId,
    required this.refreshToken,
  }) : super._();

  final String userAccountId;
  final String credentialId;
  final String accessSessionId;
  final String accessToken;
  final String refreshSessionId;
  final String refreshToken;

  @override
  String toString() => 'UserAccountHttpWireSessionPair';
}

/// Refresh deliberately has no credential identity and is not a login result.
final class UserAccountHttpWireRefreshPair {
  const UserAccountHttpWireRefreshPair._({
    required this.userAccountId,
    required this.accessSessionId,
    required this.accessToken,
    required this.refreshSessionId,
    required this.refreshToken,
  });

  final String userAccountId;
  final String accessSessionId;
  final String accessToken;
  final String refreshSessionId;
  final String refreshToken;

  @override
  String toString() => 'UserAccountHttpWireRefreshPair';
}

/// Closed six-key refresh root; login's seven-key requirement stays separate.
UserAccountHttpWireRefreshPair decodeUserAccountHttpRefresh(Object? document) {
  try {
    final root = _object(document);
    _requireKeys(root, _refreshKeys);
    if (root['authenticated'] != true) throw _invalidResponse;
    return UserAccountHttpWireRefreshPair._(
      userAccountId: _opaque(root['user_account_id']),
      accessSessionId: _opaque(root['access_session_id']),
      accessToken: _token(root['access_token']),
      refreshSessionId: _opaque(root['refresh_session_id']),
      refreshToken: _token(root['refresh_token']),
    );
  } catch (_) {
    throw _invalidResponse;
  }
}

/// An action-required result; this never establishes authentication.
final class UserAccountHttpWireChallenge
    extends UserAccountHttpWireLoginResult {
  const UserAccountHttpWireChallenge._({
    required this.userAccountId,
    required this.credentialId,
    required this.challengeId,
    required this.channel,
  }) : super._();

  final String userAccountId;
  final String credentialId;
  final String challengeId;
  final String channel;

  @override
  String toString() => 'UserAccountHttpWireChallenge';
}

/// Fixed diagnostics contain no received data or underlying error.
final class UserAccountHttpWireException implements Exception {
  const UserAccountHttpWireException._();

  @override
  String toString() => 'UserAccountHttpWireException(invalidResponse)';
}

/// Decodes only the adopted root password-login response shapes.
///
/// The caller still owns trusted transport, status and operation-lifetime checks,
/// credential-backed account lookup, and any later persistence/publication.
UserAccountHttpWireLoginResult decodeUserAccountHttpLogin(Object? document) {
  try {
    final root = _object(document);
    final authenticated = root['authenticated'];
    if (authenticated is! bool) throw _invalidResponse;
    if (authenticated) {
      _requireKeys(root, _sessionKeys);
      return UserAccountHttpWireSessionPair._(
        userAccountId: _opaque(root['user_account_id']),
        credentialId: _opaque(root['credential_id']),
        accessSessionId: _opaque(root['access_session_id']),
        accessToken: _token(root['access_token']),
        refreshSessionId: _opaque(root['refresh_session_id']),
        refreshToken: _token(root['refresh_token']),
      );
    }
    _requireKeys(root, _challengeKeys);
    final twoFactorRequired = root['two_factor_required'];
    final channel = root['channel'];
    if (twoFactorRequired is! bool ||
        !twoFactorRequired ||
        channel is! String ||
        channel != 'email') {
      throw _invalidResponse;
    }
    return UserAccountHttpWireChallenge._(
      userAccountId: _opaque(root['user_account_id']),
      credentialId: _opaque(root['credential_id']),
      challengeId: _opaque(root['challenge_id']),
      channel: channel,
    );
  } catch (_) {
    throw _invalidResponse;
  }
}

/// Projects an account record only after exact expected-account binding.
///
/// Decoding this record alone does not establish authentication authority.
AuthenticatedUserAccount decodeUserAccountHttpAccount(
  Object? document, {
  required String expectedUserAccountId,
}) {
  try {
    final expected = _opaque(expectedUserAccountId);
    final root = _object(document);
    if (root.containsKey('error')) throw _invalidResponse;
    final id = _opaque(root['id']);
    if (id != expected) throw _invalidResponse;
    final handle = root['handle'];
    if (handle != null &&
        (handle is! String || utf8.encode(handle).length > 4096)) {
      throw _invalidResponse;
    }
    return AuthenticatedUserAccount(
      userAccountId: id,
      displayName: handle as String?,
    );
  } catch (_) {
    throw _invalidResponse;
  }
}

const _invalidResponse = UserAccountHttpWireException._();
const _sessionKeys = {
  'user_account_id',
  'credential_id',
  'access_session_id',
  'access_token',
  'refresh_session_id',
  'refresh_token',
  'authenticated',
};
const _refreshKeys = {
  'user_account_id',
  'access_session_id',
  'access_token',
  'refresh_session_id',
  'refresh_token',
  'authenticated',
};
const _challengeKeys = {
  'user_account_id',
  'credential_id',
  'two_factor_required',
  'challenge_id',
  'channel',
  'authenticated',
};
final _bearerToken = RegExp(r'^[A-Za-z0-9._~+/-]+=*$');

Map<Object?, Object?> _object(Object? document) {
  if (document is! Map<Object?, Object?> ||
      document.keys.any((key) => key is! String)) {
    throw _invalidResponse;
  }
  return document;
}

void _requireKeys(Map<Object?, Object?> root, Set<String> keys) {
  if (root.length != keys.length || !keys.every(root.containsKey)) {
    throw _invalidResponse;
  }
}

String _opaque(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      utf8.encode(value).length > 4096 ||
      value.codeUnits.any((unit) => unit < 32 || unit == 127)) {
    throw _invalidResponse;
  }
  return value;
}

String _token(Object? value) {
  if (value is! String || value.isEmpty || value.length > 8192) {
    throw _invalidResponse;
  }
  final match = _bearerToken.firstMatch(value);
  if (match == null || match.group(0) != value) throw _invalidResponse;
  return value;
}
