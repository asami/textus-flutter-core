import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'submission_configuration.dart';
import 'submission_connections.dart';
import 'submission_json.dart' as j;

/// Owned Android secure configuration facade and borrowed credential port.
///
/// Android alone is supported, even when a test channel is supplied. Native
/// persistence is encrypted and transactional. The optional channel is borrowed.
/// Close joins accepted calls, rejects their late results and closes only this
/// engine's configuration handle; it never cancels durable work.
final class AndroidSubmissionConfigurationStore
    implements SubmissionConfigurationStore, SubmissionCredentialProvider {
  /// Creates a facade without IO; unsupported platforms fail before channel IO.
  AndroidSubmissionConfigurationStore({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('org.textus.flutter.core/submission');

  final MethodChannel _channel;
  final Set<Future<void>> _calls = {};
  bool _closing = false;
  Future<void>? _closeFuture;

  void _supported() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Android submission configuration is unsupported here',
      );
    }
  }

  Future<T> _call<T>(
    String method,
    Map<String, Object?> arguments,
    T Function(Object?) decode,
  ) {
    _supported();
    if (_closing) {
      return Future.error(
        SubmissionConfigurationException.safe('configurationClosed'),
      );
    }
    final result = () async {
      try {
        final value = await _channel.invokeMethod<Object?>(method, arguments);
        if (_closing) {
          throw SubmissionConfigurationException.safe('configurationClosed');
        }
        return decode(value);
      } on SubmissionConfigurationException {
        rethrow;
      } on PlatformException catch (error) {
        throw SubmissionConfigurationException.safe(error.code);
      } catch (_) {
        throw SubmissionConfigurationException.safe('configurationUnavailable');
      }
    }();
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _calls.add(settled);
    settled.then((_) => _calls.remove(settled));
    return result;
  }

  void _nothing(Object? value) {
    if (value != null) {
      throw SubmissionConfigurationException.safe('configurationUnavailable');
    }
  }

  void _definition(Map<String, Object?> definition) {
    if (utf8.encode(jsonEncode(definition)).length > 65536) {
      throw ArgumentError('Submission definition exceeds its bound');
    }
  }

  @override
  Future<SubmissionConfigurationSnapshot> snapshot() => _call(
    'snapshot',
    {},
    (value) => SubmissionConfigurationSnapshot.fromJson(j.object(value)),
  );

  @override
  Future<void> putDrive(DriveSubmissionConnection connection) {
    _definition(connection.toJson());
    if (!RegExp(r'^[^\s@\x00-\x1f\x7f]+@[^\s@\x00-\x1f\x7f]+$')
        .hasMatch(connection.accountId)) {
      throw ArgumentError('Invalid Android account identity');
    }
    return _call('putDrive', {'connection': connection.toJson()}, _nothing);
  }

  @override
  Future<void> putHttp(HttpSubmissionConnection connection) {
    _definition(connection.toJson());
    return _call('putHttp', {'connection': connection.toJson()}, _nothing);
  }

  @override
  Future<void> select({
    String? storageConnectionId,
    String? transportConnectionId,
  }) {
    if (storageConnectionId != null) j.token(storageConnectionId);
    if (transportConnectionId != null) j.token(transportConnectionId);
    return _call('select', {
      'storageConnectionId': storageConnectionId,
      'transportConnectionId': transportConnectionId,
    }, _nothing);
  }

  /// Replaces explicit local server access declarations. Syntax, duplicate ids
  /// and the 128 association bound fail before IO; native transactions validate
  /// registered kinds/membership and the complete resulting map. Empty revokes.
  /// Android, closed, late-result and fixed safe error rules match other writes.
  @override
  Future<void> setReferenceAccess({
    required String transportConnectionId,
    required List<String> storageConnectionIds,
  }) {
    j.token(transportConnectionId);
    final ids = List<String>.of(storageConnectionIds);
    for (final id in ids) {
      j.token(id);
    }
    if (ids.length > 128 || ids.toSet().length != ids.length) {
      throw ArgumentError('Invalid reference access binding');
    }
    return _call('setReferenceAccess', {
      'transportConnectionId': transportConnectionId,
      'storageConnectionIds': ids,
    }, _nothing);
  }

  /// Rotates/removes only a matching HTTP target's secret. Anonymous targets
  /// reject nonnull tokens natively. Tokens are never returned by a snapshot.
  Future<void> setHttpBearerToken(String connectionId, String? token) {
    j.token(connectionId);
    if (token != null &&
        (token.length > 8192 ||
            !RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(token))) {
      throw ArgumentError('Invalid bearer credential');
    }
    return _call('setHttpBearerToken', {
      'connectionId': connectionId,
      'token': token,
    }, _nothing);
  }

  SubmissionAuthorizationState _state(Object? value) =>
      j.enumeration(value, SubmissionAuthorizationState.values);

  /// Explicit foreground consent for the exact persisted Google account. Requires
  /// a resumed Activity; cancellation, competing consent and SDK failures are safe.
  Future<SubmissionAuthorizationState> authorizeDrive(String connectionId) {
    j.token(connectionId);
    return _call('authorizeDrive', {'connectionId': connectionId}, (value) {
      final state = _state(value);
      if (state != SubmissionAuthorizationState.available) {
        throw SubmissionConfigurationException.safe('authorizationRequired');
      }
      return state;
    });
  }

  /// Observes availability using fresh exact-account silent authorization. Never
  /// opens consent or infers current credentials from a persisted grant alone.
  Future<SubmissionAuthorizationState> authorizationState(String connectionId) {
    j.token(connectionId);
    return _call('authorizationState', {'connectionId': connectionId}, _state);
  }

  @override
  Future<String?> bearerToken(String connectionId) {
    j.token(connectionId);
    return _call('bearerToken', {'connectionId': connectionId}, (value) {
      final token = j.nullableString(value);
      if (token != null &&
          (token.length > 8192 ||
              !RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(token))) {
        throw SubmissionConfigurationException.safe('credentialUnavailable');
      }
      return token;
    });
  }

  @override
  Future<void> close() {
    _supported();
    _closing = true;
    return _closeFuture ??= () async {
      await Future.wait(_calls.toList());
      try {
        _nothing(
          await _channel.invokeMethod<Object?>(
            'closeConfiguration',
            <String, Object?>{},
          ),
        );
      } on PlatformException catch (error) {
        throw SubmissionConfigurationException.safe(error.code);
      } catch (_) {
        throw SubmissionConfigurationException.safe('configurationUnavailable');
      }
    }();
  }
}
