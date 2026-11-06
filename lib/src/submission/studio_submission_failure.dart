import 'submission_http.dart';
import 'submission_record.dart';

// Internal Studio v2 diagnostics only; no message or arbitrary code is trusted.
const _studioFailures = {
  400: (10899020100, 'argument', 'invalid', 'studioInputInvalid'),
  401: (
    91599020100,
    'security',
    'authentication-required',
    'studioAuthenticationRequired',
  ),
  403: (91699020100, 'security', 'permission-denied', 'studioPermissionDenied'),
  404: (61099020100, 'resource', 'not-found', 'studioNotFound'),
  409: (81299020100, 'state', 'conflict', 'studioConflict'),
};

bool isStudioSubmissionFailureCode(String code) => switch (code) {
  'studioInputInvalid' ||
  'studioAuthenticationRequired' ||
  'studioPermissionDenied' ||
  'studioNotFound' ||
  'studioConflict' ||
  'studioHttp400' ||
  'studioHttp401' ||
  'studioHttp403' ||
  'studioHttp404' ||
  'studioHttp409' ||
  'studioHttpUnknown' => true,
  _ => false,
};

void rejectStudioHttpStatus(
  SubmissionHttpResponse response,
  SubmissionFailureStage stage,
) {
  final status = response.statusCode;
  if (status < 400 || status > 599) {
    rejectHttpStatus(response, stage);
    return;
  }
  final tuple = _studioFailures[status];
  final code = tuple == null
      ? 'studioHttpUnknown'
      : _matchesStudioFailure(response)
      ? tuple.$4
      : 'studioHttp$status';
  throw httpFailure(
    status == 401 ? SubmissionFailureStage.configuration : stage,
    code,
    retryable: status == 408 || status == 429 || status >= 500,
  );
}

bool _matchesStudioFailure(SubmissionHttpResponse response) {
  final tuple = _studioFailures[response.statusCode]!;
  final contentType = response.headers['content-type'];
  if (contentType == null ||
      !RegExp(
        r'^application/json(?:\s*;\s*charset\s*=\s*(?:[A-Za-z0-9_-]+|"[A-Za-z0-9_-]+"))?\s*$',
        caseSensitive: false,
      ).hasMatch(contentType.trim())) {
    return false;
  }
  try {
    final body = response.json();
    if (body is! Map) return false;
    final error = body['error'];
    if (error is! Map ||
        error['detailCode'] is! int ||
        error['detailCode'] != tuple.$1) {
      return false;
    }
    if (error.containsKey('status') &&
        (error['status'] is! int || error['status'] != response.statusCode)) {
      return false;
    }
    final conclusion = error['conclusion'];
    if (conclusion is! Map) return false;
    if (conclusion.containsKey('status')) {
      final status = conclusion['status'];
      if (status is! Map) return false;
      if (status.containsKey('detailCode') &&
          (status['detailCode'] is! int || status['detailCode'] != tuple.$1)) {
        return false;
      }
      if (status.containsKey('webCode') &&
          (status['webCode'] is! int ||
              status['webCode'] != response.statusCode)) {
        return false;
      }
    }
    final observation = conclusion['observation'];
    if (observation is! Map) return false;
    final taxonomy = observation['taxonomy'];
    return taxonomy is Map &&
        taxonomy['category'] == tuple.$2 &&
        taxonomy['symptom'] == tuple.$3;
  } catch (_) {
    return false;
  }
}
