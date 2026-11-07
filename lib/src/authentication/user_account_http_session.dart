part of 'user_account_http_authentication_backend.dart';

abstract interface class _CredentialLease {
  _SubmissionOwner get _owner;
  bool _isCurrent();
}

enum UserAccountHttpFailure { unavailable, retired, timedOut, invalidResponse }

/// Safe failure facts. A dispatched mutation may have committed even when the
/// client did not receive a reply. Callers must not automatically replay it.
final class UserAccountHttpException implements Exception {
  const UserAccountHttpException(
    this.failure, {
    required this.mutationMayHaveCompleted,
  });
  final UserAccountHttpFailure failure;
  final bool mutationMayHaveCompleted;
  @override
  String toString() => 'UserAccountHttpException(${failure.name})';
}

/// Complete bounded HTTP reply; no authorization/cookie/redirect headers escape.
final class UserAccountHttpReply {
  UserAccountHttpReply._(
    this.statusCode,
    Map<String, String> headers,
    Uint8List bytes,
  ) : headers = Map.unmodifiable({
        for (final header in headers.entries)
          if (const {
            'etag',
            'content-type',
            'cache-control',
          }.contains(header.key.toLowerCase()))
            header.key.toLowerCase(): header.value,
      }),
      _bytes = Uint8List.fromList(bytes);
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  Object? json() {
    try {
      return jsonDecode(utf8.decode(_bytes, allowMalformed: false));
    } catch (_) {
      throw const FormatException('Invalid authenticated service response');
    }
  }

  @override
  String toString() => 'UserAccountHttpReply(statusCode: $statusCode)';
}

/// Account-bound service access, without exposing the private Bearer to App/UI.
/// There are no automatic refresh/retry/redirect operations. Reacquire after a
/// successful authentication refresh; logical workspace identity stays with App.
final class UserAccountHttpSession implements _CredentialLease {
  UserAccountHttpSession._(
    this._backend,
    this._owner,
    this._binding,
    this.serviceBaseUri,
    this._client,
    this._ownsClient,
  );
  final UserAccountHttpAuthenticationBackend _backend;
  @override
  final _SubmissionOwner _owner;
  final SubmissionAuthenticationBinding _binding;
  final Uri serviceBaseUri;
  final http.Client _client;
  final bool _ownsClient;
  final StreamController<void> _retired = StreamController.broadcast(
    sync: true,
  );
  bool _closed = false;
  final _ownedTransferClients = <http.Client>{};

  String get userAccountId => _owner.userAccountId;
  String get authorityProfileId => _binding.authorityProfileId;
  Uri get authorityBaseUri => _binding.authorityBaseUri;
  bool get isClosed => _closed;

  /// Bind existing delivery/Studio transports inside Core, without exposing a
  /// credential provider or token to application presentation. An optional
  /// borrowed run lifetime fences dispatch and aborts pending IO on retirement;
  /// retiring it does not retire the account session.
  UserAccountMaterialDeliveryAccess createMaterialDeliveryAccess({
    http.Client? directTransferClient,
    SubmissionRunLifetime? lifetime,
  }) {
    if (!_isCurrent() || !(lifetime?.isCurrent ?? true)) {
      throw StateError('Authenticated delivery is unavailable');
    }
    final tkl = HttpSubmissionConnection(
      id: 'tkl',
      endpoint: serviceBaseUri.resolve('knowledge-lake/material-delivery/'),
    );
    final studio = HttpSubmissionConnection(
      id: 'studio',
      endpoint: serviceBaseUri.resolve('editing-studio/book-material/submit'),
    );
    var active = true;
    bool current() => active && _isCurrent() && (lifetime?.isCurrent ?? true);
    final scope = _backend.createSubmissionScope(
      trustedTargets: [tkl, studio],
      isRunCurrent: current,
    );
    final direct =
        directTransferClient ?? browser.createCapabilityTransferHttpClient();
    if (directTransferClient == null) _ownedTransferClients.add(direct);
    final cancelled = Completer<void>();
    StreamSubscription<void>? retirement;
    void close() {
      if (!active) return;
      active = false;
      if (!cancelled.isCompleted) cancelled.complete();
      if (retirement != null) _observe(retirement.cancel());
      if (directTransferClient == null &&
          _ownedTransferClients.remove(direct)) {
        try {
          direct.close();
        } catch (_) {
          /* The access is already retired. */
        }
      }
    }

    retirement = _retired.stream.listen((_) => close());
    lifetime?.cancelled.then<void>((_) => close());
    final routed = _DeliveryRoutingClient(serviceBaseUri, _client, direct);
    return UserAccountMaterialDeliveryAccess._(
      binding: scope.binding,
      authentication: scope.context,
      tklConnection: tkl,
      studioConnection: studio,
      delivery: TklMaterialDeliveryHttpClient(
        connection: tkl,
        client: routed,
        credentials: scope,
        authenticationBinding: scope.binding,
        isRunCurrent: current,
        cancellation: cancelled.future,
      ),
      studio: HttpSubmissionTransport(
        connection: studio,
        client: _client,
        credentials: scope,
        isRunCurrent: current,
        cancellation: cancelled.future,
      ),
      close: close,
    );
  }

  @override
  bool _isCurrent() => !_closed && _backend._ownsSubmission(_owner, _binding);

  Future<UserAccountHttpReply> get(
    String operation, {
    Map<String, String> query = const {},
    int maximumResponseBytes = 2097152,
  }) => _request(
    'GET',
    operation,
    query: query,
    maximumResponseBytes: maximumResponseBytes,
  );

  Future<UserAccountHttpReply> post(
    String operation, {
    required Map<String, Object?> body,
    String? ifMatch,
    int maximumResponseBytes = 2097152,
  }) => _request(
    'POST',
    operation,
    body: body,
    ifMatch: ifMatch,
    maximumResponseBytes: maximumResponseBytes,
  );

  Future<UserAccountHttpReply> _request(
    String method,
    String operation, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    String? ifMatch,
    required int maximumResponseBytes,
  }) async {
    if (!_matches(
          RegExp(r'[A-Za-z][A-Za-z0-9_-]*(/[A-Za-z][A-Za-z0-9_-]*)*'),
          operation,
        ) ||
        operation.length > 1024 ||
        maximumResponseBytes < 1 ||
        maximumResponseBytes > 67108864 ||
        (ifMatch != null &&
            (ifMatch.isEmpty ||
                ifMatch.length > 1024 ||
                ifMatch.codeUnits.any((v) => v < 32 || v == 127)))) {
      throw ArgumentError('Invalid authenticated service request');
    }
    String? encoded;
    try {
      encoded = body == null ? null : jsonEncode(body);
    } catch (_) {
      throw ArgumentError('Invalid authenticated service request');
    }
    final abort = Completer<void>();
    final result = Completer<UserAccountHttpReply>();
    var dispatched = false;
    var count = 0;
    final bytes = BytesBuilder(copy: false);
    StreamSubscription<List<int>>? receiving;
    void fail(UserAccountHttpFailure reason) {
      if (result.isCompleted) return;
      result.completeError(
        UserAccountHttpException(
          reason,
          mutationMayHaveCompleted: method == 'POST' && dispatched,
        ),
      );
      if (!abort.isCompleted) abort.complete();
      final subscription = receiving;
      if (subscription != null) _observe(subscription.cancel());
    }

    void guard() {
      if (!_isCurrent()) fail(UserAccountHttpFailure.retired);
    }

    final retirement = _retired.stream.listen(
      (_) => fail(UserAccountHttpFailure.retired),
    );
    final timer = Timer(
      _backend.profile.requestTimeout,
      () => fail(UserAccountHttpFailure.timedOut),
    );
    _observe(() async {
      try {
        guard();
        if (result.isCompleted) return;
        final token = await _backend._credentialToken(this);
        guard();
        if (result.isCompleted) return;
        if (token == null) {
          fail(UserAccountHttpFailure.unavailable);
          return;
        }
        final request = http.AbortableRequest(
          method,
          serviceBaseUri
              .resolve(operation)
              .replace(queryParameters: query.isEmpty ? null : query),
          abortTrigger: abort.future,
        )..followRedirects = false;
        request.headers['Accept'] = 'application/json';
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Cache-Control'] = 'no-store';
        if (ifMatch != null) request.headers['If-Match'] = ifMatch;
        if (encoded != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = encoded;
        }
        guard();
        if (result.isCompleted) return;
        dispatched = true;
        final response = await _client.send(request);
        guard();
        if (result.isCompleted) {
          _observe(
            response.stream.listen((_) {}, onError: (Object _) {}).cancel(),
          );
          return;
        }
        receiving = response.stream.listen(
          (chunk) {
            guard();
            if (result.isCompleted) return;
            count += chunk.length;
            if (count > maximumResponseBytes) {
              fail(UserAccountHttpFailure.invalidResponse);
            } else {
              bytes.add(chunk);
            }
          },
          onError: (Object _) => fail(UserAccountHttpFailure.unavailable),
          onDone: () {
            guard();
            if (!result.isCompleted) {
              result.complete(
                UserAccountHttpReply._(
                  response.statusCode,
                  response.headers,
                  bytes.takeBytes(),
                ),
              );
            }
          },
          cancelOnError: true,
        );
      } catch (_) {
        fail(UserAccountHttpFailure.unavailable);
      }
    }());
    try {
      return await result.future;
    } finally {
      timer.cancel();
      _observe(retirement.cancel());
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// Retires dispatch and pending reads immediately; never logs the account out.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final client in _ownedTransferClients.toList()) {
      _ownedTransferClients.remove(client);
      try {
        client.close();
      } catch (_) {
        /* Continue retiring other owners. */
      }
    }
    _backend._httpSessions.remove(this);
    _retired.add(null);
    _observe(_retired.close());
    if (_ownsClient) {
      try {
        _client.close();
      } catch (_) {
        /* Already retired. */
      }
    }
  }

  @override
  String toString() => 'UserAccountHttpSession';
}
