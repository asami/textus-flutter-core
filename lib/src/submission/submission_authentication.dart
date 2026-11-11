import '../authentication/user_account_authentication.dart';
import '../authentication/user_account_http_authentication_backend.dart';
import 'submission_json.dart' as j;

/// Immutable local participant intent, without credentials or authorization.
final class SubmissionAuthenticationBinding {
  /// Snapshots the authority identity and the exact opaque nonblank account ID.
  SubmissionAuthenticationBinding({
    required UserAccountHttpProfile authority,
    required String userAccountId,
  }) : authorityProfileId = authority.profileId,
       authorityBaseUri = authority.serviceBaseUri,
       userAccountId = AuthenticatedUserAccount(userAccountId: userAccountId)
           .userAccountId;

  final String authorityProfileId;
  final Uri authorityBaseUri;
  final String userAccountId;

  /// A fresh local persistence map; this is never a server packet.
  Map<String, Object?> toJson() => {
    'version': 1,
    'authorityProfileId': authorityProfileId,
    'authorityBaseUri': authorityBaseUri.toString(),
    'userAccountId': userAccountId,
  };

  /// Reads only closed v1 identities without repairing canonical URI spelling.
  /// Development HTTP parsing retains identity only; it grants no HTTP access.
  static SubmissionAuthenticationBinding fromJson(Object? json) => j.decode(() {
    final value = j.exact(json, {
      'version',
      'authorityProfileId',
      'authorityBaseUri',
      'userAccountId',
    });
    j.version(value);
    final base = j.string(value['authorityBaseUri']);
    final authority = UserAccountHttpProfile.fromString(
      profileId: j.string(value['authorityProfileId']),
      serviceBaseUri: base,
      allowDevelopmentHttp: true,
    );
    if (base != authority.serviceBaseUri.toString()) {
      throw const FormatException('Invalid submission authority identity');
    }
    return SubmissionAuthenticationBinding(
      authority: authority,
      userAccountId: j.string(value['userAccountId']),
    );
  });

  @override
  bool operator ==(Object other) =>
      other is SubmissionAuthenticationBinding &&
      authorityProfileId == other.authorityProfileId &&
      authorityBaseUri == other.authorityBaseUri &&
      userAccountId == other.userAccountId;

  @override
  int get hashCode =>
      Object.hash(authorityProfileId, authorityBaseUri, userAccountId);

  @override
  String toString() => 'SubmissionAuthenticationBinding';
}

/// Borrowed local dispatch lifetime fence, never a login or credential grant.
final class SubmissionAuthenticationContext {
  /// Construction retains the callback without invoking it or performing IO.
  SubmissionAuthenticationContext({
    required this.binding,
    required this._isCurrent,
  });

  final SubmissionAuthenticationBinding binding;
  final bool Function() _isCurrent;

  /// A withdrawn or failing owner cannot admit further dispatch/progress.
  bool get isCurrent {
    try {
      return _isCurrent();
    } catch (_) {
      return false;
    }
  }

  @override
  String toString() => 'SubmissionAuthenticationContext';
}
