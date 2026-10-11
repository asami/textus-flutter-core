import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'submission_adapters.dart';
import 'submission_connections.dart';
import 'submission_record.dart';

// Internal HTTP lifetime and fixed error vocabulary; intentionally unexported.

SubmissionAdapterException httpFailure(
  SubmissionFailureStage stage,
  String code, {
  bool retryable = false,
}) => SubmissionAdapterException(
  stage: stage,
  code: code,
  message: switch (code) {
    'operationTimeout' => 'Submission operation timed out.',
    'operationCancelled' => 'Submission operation was cancelled.',
    'authRequired' => 'Submission authorization is required.',
    'credentialUnavailable' => 'Submission credentials are unavailable.',
    'connectionMismatch' => 'Submission connection does not match.',
    'materialMismatch' => 'Submission material does not match.',
    'reservationMismatch' => 'Submission reservation does not match.',
    'originalLengthMismatch' => 'Submission original length does not match.',
    'permissionDenied' => 'Submission permission was denied.',
    'requestRejected' => 'Submission request was rejected.',
    'redirectRejected' => 'Submission redirect was rejected.',
    'connectionFailed' => 'Submission connection could not be completed.',
    'serviceUnavailable' => 'Submission service is temporarily unavailable.',
    'rateLimited' => 'Submission service is temporarily rate limited.',
    'invalidResponse' => 'Submission response is invalid.',
    'invalidUploadLocation' => 'Submission upload location is invalid.',
    'uploadIncomplete' => 'Submission upload is incomplete.',
    'verificationUnavailable' => 'Submission verification is unavailable.',
    'remoteBindingMismatch' => 'Submission remote binding does not match.',
    'invalidRemoteMetadata' => 'Submission remote metadata is invalid.',
    'acknowledgementMissing' => 'Submission acknowledgement is missing.',
    'invalidAcknowledgement' => 'Submission acknowledgement is invalid.',
    _ => 'Submission operation could not be completed.',
  },
  retryable: retryable,
);

void validateHttpTimeout(Duration timeout) {
  if (timeout <= Duration.zero || timeout > const Duration(seconds: 45)) {
    throw ArgumentError('Operation timeout must be positive and at most 45s');
  }
}

final class SubmissionHttpResponse {
  SubmissionHttpResponse(this.statusCode, this.headers, this.bytes);
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;

  Object? json() => jsonDecode(utf8.decode(bytes));
}

/// One operation's monotonic deadline, abort signal and response subscription.
/// No borrowed client/provider is closed; late work is observed and discarded.
final class SubmissionHttpOperation {
  SubmissionHttpOperation({
    required this.stage,
    required Duration timeout,
    required this.isRunCurrent,
    required Future<void>? cancellation,
  }) : _timeout = timeout {
    _clock.start();
    _timer = Timer(timeout, () => _stop('operationTimeout'));
    cancellation?.then<void>(
      (_) {
        if (!_disposed) _stop('operationCancelled');
      },
      onError: (Object error, StackTrace stack) {
        if (!_disposed) _stop('operationCancelled');
      },
    );
  }

  final SubmissionFailureStage stage;
  final bool Function()? isRunCurrent;
  final Duration _timeout;
  final Stopwatch _clock = Stopwatch();
  final Completer<void> _abort = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  late final Timer _timer;
  StreamSubscription<List<int>>? _subscription;
  SubmissionAdapterException? _reason;
  bool _disposed = false;

  void _observe(Future<void> future) {
    unawaited(
      future.then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
    );
  }

  void _abortRequest() {
    if (!_abort.isCompleted) _abort.complete();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) _observe(subscription.cancel());
  }

  void _stop(String code) {
    if (_disposed || _reason != null) return;
    _reason = httpFailure(stage, code, retryable: true);
    _abortRequest();
    _stopped.complete();
  }

  void check() {
    if (_reason != null) throw _reason!;
    if (_clock.elapsed >= _timeout) _stop('operationTimeout');
    try {
      if (!(isRunCurrent?.call() ?? true)) _stop('operationCancelled');
    } catch (_) {
      _stop('operationCancelled');
    }
    if (_reason != null) throw _reason!;
  }

  Future<T> wait<T>(Future<T> future, {void Function(T)? onDiscard}) async {
    // Future.any installs error handlers on both losers, including late errors.
    try {
      final result = await Future.any<T>([
        future,
        _stopped.future.then<T>((_) => throw _reason!),
      ]);
      try {
        check();
      } catch (_) {
        onDiscard?.call(result);
        rethrow;
      }
      return result;
    } catch (_) {
      check();
      rethrow;
    }
  }

  void _discardResponse(http.StreamedResponse response) {
    try {
      final discarded = response.stream.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      );
      _observe(discarded.cancel());
    } catch (_) {
      // An already discarded single-subscription stream needs no second owner.
    }
  }

  Future<String> token(
    SubmissionCredentialProvider provider,
    String connectionId,
  ) async {
    check();
    String? token;
    try {
      token = await wait(
        Future<String?>.sync(() => provider.bearerToken(connectionId)),
      );
    } catch (_) {
      check();
      throw httpFailure(
        SubmissionFailureStage.configuration,
        'credentialUnavailable',
        retryable: true,
      );
    }
    check();
    if (token == null || !RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(token)) {
      throw httpFailure(SubmissionFailureStage.configuration, 'authRequired');
    }
    return token;
  }

  Future<SubmissionHttpResponse> send(
    http.Client client,
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    check();
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: _abort.future,
    )..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    check();
    try {
      final pending = Future<http.StreamedResponse>.sync(
        () => client.send(request),
      );
      // A non-cooperative client may yield headers after the operation retired.
      // Observe its stream too, so late stream failures cannot escape the zone.
      unawaited(
        pending.then<void>((response) {
          if (_disposed || _reason != null) {
            _discardResponse(response);
          }
        }, onError: (Object error, StackTrace stack) {}),
      );
      final response = await wait(pending, onDiscard: _discardResponse);
      check();
      final completed = Completer<Uint8List>();
      final bytes = BytesBuilder(copy: true);
      _subscription = response.stream.listen(
        (chunk) {
          if (completed.isCompleted) return;
          if (bytes.length + chunk.length > 262144) {
            completed.completeError(httpFailure(stage, 'invalidResponse'));
            _abortRequest();
          } else {
            bytes.add(chunk);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!completed.isCompleted) completed.completeError(error, stack);
        },
        onDone: () {
          if (!completed.isCompleted) completed.complete(bytes.takeBytes());
        },
      );
      final result = await wait(completed.future);
      check();
      _subscription = null;
      return SubmissionHttpResponse(response.statusCode, {
        for (final entry in response.headers.entries)
          entry.key.toLowerCase(): entry.value,
      }, result);
    } on SubmissionAdapterException {
      rethrow;
    } catch (_) {
      check();
      throw httpFailure(stage, 'connectionFailed', retryable: true);
    }
  }

  void dispose() {
    _disposed = true;
    _timer.cancel();
    _clock.stop();
    _abortRequest();
  }
}

void rejectHttpStatus(
  SubmissionHttpResponse response,
  SubmissionFailureStage stage, {
  bool drive = false,
}) {
  final status = response.statusCode;
  if (status == 401) {
    throw httpFailure(SubmissionFailureStage.configuration, 'authRequired');
  }
  if (status == 403) {
    if (drive && _driveRateLimited(response)) {
      throw httpFailure(stage, 'rateLimited', retryable: true);
    }
    throw httpFailure(stage, 'permissionDenied');
  }
  if (status == 408 || status == 429 || status >= 500 && status <= 599) {
    throw httpFailure(stage, 'serviceUnavailable', retryable: true);
  }
  if (status >= 300 && status <= 399) {
    throw httpFailure(stage, 'redirectRejected');
  }
  if (status >= 400 && status <= 499) {
    throw httpFailure(stage, 'requestRejected');
  }
  throw httpFailure(stage, 'invalidResponse');
}

bool _driveRateLimited(SubmissionHttpResponse response) {
  try {
    final body = response.json();
    if (body is! Map || body['error'] is! Map) return false;
    final errors = (body['error'] as Map)['errors'];
    if (errors is! List) return false;
    return errors.any(
      (value) =>
          value is Map &&
          (value['reason'] == 'rateLimitExceeded' ||
              value['reason'] == 'userRateLimitExceeded'),
    );
  } catch (_) {
    return false;
  }
}
