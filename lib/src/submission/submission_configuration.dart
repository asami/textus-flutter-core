import 'dart:convert';

import 'submission_connections.dart';
import 'submission_json.dart' as j;

/// Safe platform configuration failure. Only the fixed vocabulary is retained.
final class SubmissionConfigurationException implements Exception {
  /// Rejects unknown codes/messages rather than retaining arbitrary secret data.
  SubmissionConfigurationException({
    required String code,
    required String message,
  }) : code = code,
       message = message {
    if (messages[code] != message) {
      throw ArgumentError('Invalid configuration failure');
    }
  }

  /// Fixed safe diagnostic identity.
  final String code;

  /// Fixed safe display text, without input, native details or a cause.
  final String message;

  /// Closed platform error vocabulary shared with the native implementation.
  static const messages = <String, String>{
    'configurationUnavailable': 'Submission configuration is unavailable.',
    'configurationInvalid': 'Submission configuration is invalid.',
    'connectionConflict': 'Submission connection identity conflicts.',
    'connectionMissing': 'Submission connection is not configured.',
    'configurationClosed': 'Submission configuration is closed.',
    'authorizationRequired': 'Submission authorization is required.',
    'authorizationCancelled': 'Submission authorization was cancelled.',
    'authorizationBusy': 'Submission authorization is already in progress.',
    'foregroundRequired':
        'Submission authorization requires a foreground activity.',
    'credentialUnavailable': 'Submission credentials are unavailable.',
  };

  /// Replaces an untrusted native code/message with a fixed safe failure.
  factory SubmissionConfigurationException.safe(String code) {
    final selected = messages.containsKey(code)
        ? code
        : 'configurationUnavailable';
    return SubmissionConfigurationException(
      code: selected,
      message: messages[selected]!,
    );
  }

  @override
  String toString() => 'SubmissionConfigurationException($code)';
}

/// Observed credential availability; a recorded grant is not network readiness.
enum SubmissionAuthorizationState {
  available,
  authorizationRequired,
  unavailable,
}

/// Immutable definitions and selection for future intent; never contains secrets.
final class SubmissionConfigurationSnapshot {
  /// Freezes definitions and validates the 128 connection limit and exact kinds.
  SubmissionConfigurationSnapshot({
    required List<DriveSubmissionConnection> driveConnections,
    required List<HttpSubmissionConnection> httpConnections,
    this.selectedStorageConnectionId,
    this.selectedTransportConnectionId,
    Map<String, List<String>> referenceAccessBindings = const {},
  }) : driveConnections = List.unmodifiable(driveConnections),
       httpConnections = List.unmodifiable(httpConnections),
       referenceAccessBindings = Map<String, List<String>>.unmodifiable({
         for (final entry in referenceAccessBindings.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }) {
    final ids = <String>{};
    for (final connection in [
      ...this.driveConnections,
      ...this.httpConnections,
    ]) {
      final id = connection is DriveSubmissionConnection
          ? connection.id
          : (connection as HttpSubmissionConnection).id;
      if (!ids.add(id)) throw ArgumentError('Duplicate connection identity');
      final definition = connection is DriveSubmissionConnection
          ? connection.toJson()
          : (connection as HttpSubmissionConnection).toJson();
      if (utf8.encode(jsonEncode(definition)).length > 65536) {
        throw ArgumentError('Submission definition exceeds its bound');
      }
    }
    if (ids.length > 128 ||
        (selectedStorageConnectionId != null &&
            !this.driveConnections.any(
              (c) => c.id == selectedStorageConnectionId,
            )) ||
        (selectedTransportConnectionId != null &&
            !this.httpConnections.any(
              (c) => c.id == selectedTransportConnectionId,
            ))) {
      throw ArgumentError('Invalid submission configuration');
    }
    var associations = 0;
    for (final entry in this.referenceAccessBindings.entries) {
      j.token(entry.key);
      if (!this.httpConnections.any((c) => c.id == entry.key) ||
          entry.value.toSet().length != entry.value.length) {
        throw ArgumentError('Invalid reference access binding');
      }
      for (final id in entry.value) {
        j.token(id);
        if (!this.driveConnections.any((c) => c.id == id)) {
          throw ArgumentError('Invalid reference access binding');
        }
      }
      associations += entry.value.length;
    }
    if (this.referenceAccessBindings.length > 128 || associations > 128) {
      throw ArgumentError('Reference access bindings exceed their bound');
    }
    if (utf8.encode(jsonEncode(toJson())).length > 128 * 65536) {
      throw ArgumentError('Submission configuration exceeds its bound');
    }
  }

  /// All immutable storage targets, including previously selected definitions.
  final List<DriveSubmissionConnection> driveConnections;

  /// All immutable transport targets, including previously selected definitions.
  final List<HttpSubmissionConnection> httpConnections;

  /// Storage selection for newly created intent, or null.
  final String? selectedStorageConnectionId;

  /// Transport selection for newly created intent, or null.
  final String? selectedTransportConnectionId;

  /// Explicit operator-provisioned server resolver access by exact connection id.
  /// A missing key is unknown; an empty list explicitly revokes access. This
  /// deeply frozen local declaration does not prove actual remote permissions.
  final Map<String, List<String>> referenceAccessBindings;

  /// Detached closed version 2 JSON; connection definitions retain version 1.
  Map<String, Object?> toJson() => {
    'version': 2,
    'driveConnections': driveConnections.map((c) => c.toJson()).toList(),
    'httpConnections': httpConnections.map((c) => c.toJson()).toList(),
    'selectedStorageConnectionId': selectedStorageConnectionId,
    'selectedTransportConnectionId': selectedTransportConnectionId,
    'referenceAccessBindings': {
      for (final entry in referenceAccessBindings.entries)
        entry.key: entry.value.toList(),
    },
  };

  /// Rejects corruption, missing/extra keys and unknown versions without fallback.
  factory SubmissionConfigurationSnapshot.fromJson(Map<String, Object?> json) =>
      j.decode(() {
        final version = j.integer(json['version']);
        if (version != 1 && version != 2) {
          throw const FormatException('Unsupported configuration version');
        }
        final value = j.exact(json, {
          'version',
          'driveConnections',
          'httpConnections',
          'selectedStorageConnectionId',
          'selectedTransportConnectionId',
          if (version == 2) 'referenceAccessBindings',
        });
        return SubmissionConfigurationSnapshot(
          driveConnections: j
              .array(value['driveConnections'])
              .map((c) => DriveSubmissionConnection.fromJson(j.object(c)))
              .toList(),
          httpConnections: j
              .array(value['httpConnections'])
              .map((c) => HttpSubmissionConnection.fromJson(j.object(c)))
              .toList(),
          selectedStorageConnectionId: j.nullableString(
            value['selectedStorageConnectionId'],
          ),
          selectedTransportConnectionId: j.nullableString(
            value['selectedTransportConnectionId'],
          ),
          referenceAccessBindings: version == 1
              ? const {}
              : {
                  for (final entry
                      in j.object(value['referenceAccessBindings']).entries)
                    entry.key: j.array(entry.value).map(j.string).toList(),
                },
        );
      });
}

/// Owned durable configuration handle. Errors never synthesize an empty snapshot.
abstract interface class SubmissionConfigurationStore {
  /// Reads current committed definitions; an absent store is legitimately empty.
  Future<SubmissionConfigurationSnapshot> snapshot();

  /// Inserts an immutable target or accepts an identical definition idempotently.
  /// A conflicting id always fails without replacing previously accepted data.
  Future<void> putDrive(DriveSubmissionConnection connection);

  /// Inserts an immutable endpoint/auth requirement, with the same conflict rule.
  Future<void> putHttp(HttpSubmissionConnection connection);

  /// Atomically selects existing exact kinds for new intent. Null clears a choice.
  /// Queued intent and all previously registered definitions remain unchanged.
  Future<void> select({
    String? storageConnectionId,
    String? transportConnectionId,
  });

  /// Atomically replaces one registered HTTP target's exact Drive access ids.
  /// Empty retains explicit revocation. Validate the whole resulting map before
  /// writing; preserve selection, definitions, secrets and queued intent. Custom
  /// stores must implement this operation; failures never fabricate a binding.
  Future<void> setReferenceAccess({
    required String transportConnectionId,
    required List<String> storageConnectionIds,
  });

  /// Prevents new calls and drains/closes only this handle. Never deletes data.
  Future<void> close();
}
