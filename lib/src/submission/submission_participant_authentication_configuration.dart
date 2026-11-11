import 'dart:convert';

import '../authentication/user_account_http_authentication_backend.dart';
import 'submission_json.dart' as j;

/// Immutable operator intent for one authority and explicitly trusted targets.
/// This declaration contains no account, credential, session or server grant.
final class SubmissionParticipantAuthenticationConfiguration {
  /// Validates raw authority input using the production HTTPS profile policy.
  /// Construction performs no IO and retains no invalid input or error cause.
  factory SubmissionParticipantAuthenticationConfiguration({
    required String authorityProfileId,
    required String authorityBaseUri,
    required List<String> trustedConnectionIds,
  }) {
    try {
      final authority = UserAccountHttpProfile.fromString(
        profileId: authorityProfileId,
        serviceBaseUri: authorityBaseUri,
      );
      final ids = List<String>.unmodifiable(trustedConnectionIds.map(j.token));
      if (ids.isEmpty || ids.length > 128 || ids.toSet().length != ids.length) {
        throw ArgumentError();
      }
      final configuration = SubmissionParticipantAuthenticationConfiguration._(
        authority.profileId,
        authority.serviceBaseUri,
        ids,
      );
      if (utf8.encode(jsonEncode(configuration.toJson())).length > 65536) {
        throw ArgumentError();
      }
      return configuration;
    } catch (_) {
      throw ArgumentError('Invalid participant submission configuration');
    }
  }

  SubmissionParticipantAuthenticationConfiguration._(
    this.authorityProfileId,
    this.authorityBaseUri,
    this.trustedConnectionIds,
  );

  final String authorityProfileId;
  final Uri authorityBaseUri;

  /// Ordered operator values, with no same-origin or URL-derived membership.
  final List<String> trustedConnectionIds;

  /// A fresh inert production profile with the existing default request timeout.
  UserAccountHttpProfile get authority => UserAccountHttpProfile(
    profileId: authorityProfileId,
    serviceBaseUri: authorityBaseUri,
  );

  /// Detached closed v1 persistence JSON, containing no runtime options.
  Map<String, Object?> toJson() => {
    'version': 1,
    'authorityProfileId': authorityProfileId,
    'authorityBaseUri': authorityBaseUri.toString(),
    'trustedConnectionIds': trustedConnectionIds.toList(),
  };

  /// Stored authority identity must already have its canonical URI spelling.
  static SubmissionParticipantAuthenticationConfiguration fromJson(
    Object? json,
  ) => j.decode(() {
    final value = j.exact(json, {
      'version',
      'authorityProfileId',
      'authorityBaseUri',
      'trustedConnectionIds',
    });
    j.version(value);
    final base = j.string(value['authorityBaseUri']);
    final configuration = SubmissionParticipantAuthenticationConfiguration(
      authorityProfileId: j.string(value['authorityProfileId']),
      authorityBaseUri: base,
      trustedConnectionIds: j
          .array(value['trustedConnectionIds'])
          .map(j.string)
          .toList(),
    );
    if (base != configuration.authorityBaseUri.toString()) {
      throw const FormatException('Invalid submission authority identity');
    }
    return configuration;
  });

  @override
  bool operator ==(Object other) =>
      other is SubmissionParticipantAuthenticationConfiguration &&
      authorityProfileId == other.authorityProfileId &&
      authorityBaseUri == other.authorityBaseUri &&
      j.deepEquals(trustedConnectionIds, other.trustedConnectionIds);

  @override
  int get hashCode => Object.hash(
    authorityProfileId,
    authorityBaseUri,
    Object.hashAll(trustedConnectionIds),
  );

  @override
  String toString() => 'SubmissionParticipantAuthenticationConfiguration';
}
