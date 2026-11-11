import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http_api;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/src/authentication/native_authentication_credential_store.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_http_fixture.dart';

const _access = 'SYNTHETIC.transport-access=';
const _refresh = 'SYNTHETIC.transport-refresh==';
const _privateCause = 'SYNTHETIC.private-provider-cause';
const _account = ' synthetic/account:α ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ControlledSubmissionHttpClient client() {
    final owned = ControlledSubmissionHttpClient();
    addTearDown(owned.close);
    return owned;
  }

  for (final registered in [false, true]) {
    final version = registered ? 'v2' : 'v1';
    test('$version bound dispatch uses only the exact advanced port', () async {
      // Given immutable bound intent, a typed target and controlled matching ACK.
      final binding = _binding();
      final target = _target();
      final credentials = _AdvancedCredentials();
      final http = client()..respond(submissionJsonResponse(_ack()));
      final transport = _transport(http, credentials, target);
      // When the real transport submits the chosen packet schema.
      final accepted = await _submit(transport, registered, binding: binding);
      // Then the advanced call retains exact object identity and local data stays local.
      expect(accepted.requestId, 'book-1');
      expect(accepted.subjectId, 'book-1');
      expect(credentials.advancedCalls, hasLength(1));
      expect(credentials.advancedCalls.single.$1, same(binding));
      expect(credentials.advancedCalls.single.$2, same(target));
      expect(credentials.legacyCalls, isEmpty);
      final sent = http.requests.single;
      expect(sent.uri, target.endpoint);
      expect(sent.headers, {
        'content-type': 'application/json',
        'accept': 'application/json',
        'idempotency-key': 'book-1',
        'authorization': 'Bearer $_access',
      });
      expect(sent.followsRedirects, isFalse);
      expect(
        sent.json,
        registered
            ? RegisteredMaterialSubmissionCodec.packetToJson(
                _registered(binding, target),
              )
            : SubmissionCodec.packetToJson(_packet(binding)),
      );
      expect(
        utf8.decode(sent.bytes),
        allOf(
          isNot(contains('authenticationBinding')),
          isNot(contains(_account)),
          isNot(contains('authorityProfileId')),
          isNot(contains(_access)),
          isNot(contains(_refresh)),
        ),
      );
    });

    for (final result in ['null', 'throw', 'empty', 'newline', 'space']) {
      test(
        '$version advanced $result denies without fallback or raw cause',
        () async {
          // Given an advanced lookup that cannot provide a safe current ACCESS.
          final credentials = _AdvancedCredentials()
            ..lookup = () => switch (result) {
              'null' => null,
              'throw' => throw StateError(_privateCause),
              'empty' => '',
              'newline' => '$_access\r\n$_privateCause',
              _ => 'Bearer $_privateCause',
            };
          final http = client();
          // When actual packet dispatch observes that lookup exactly once.
          final error = await _capture(
            () => _submit(
              _transport(http, credentials, _target()),
              registered,
              binding: _binding(),
            ),
          );
          // Then only fixed safe errors escape and no credential fallback or HTTP occurs.
          expect(
            error,
            _submissionFailure(
              result == 'throw' ? 'credentialUnavailable' : 'authRequired',
              retryable: result == 'throw',
            ),
          );
          expect('$error', isNot(contains(_privateCause)));
          expect(
            (error! as SubmissionAdapterException).message,
            result == 'throw'
                ? 'Submission credentials are unavailable.'
                : 'Submission authorization is required.',
          );
          expect(credentials.advancedCalls, hasLength(1));
          expect(credentials.legacyCalls, isEmpty);
          expect(http.requests, isEmpty);
        },
      );
    }

    for (final mode in [
      'bound legacy',
      'bound anonymous',
      'unbound advanced',
      'unbound anonymous advanced',
    ]) {
      test(
        '$version $mode denies before every credential or HTTP call',
        () async {
          // Given incompatible binding/provider/target selection, before provider IO.
          final legacy = _LegacyCredentials();
          final advanced = _AdvancedCredentials();
          final provider = mode == 'bound legacy' ? legacy : advanced;
          final binding = mode.startsWith('unbound') ? null : _binding();
          final target = _target(anonymous: mode.contains('anonymous'));
          final http = client();
          // When the actual transport attempts this selection.
          final error = await _capture(
            () => _submit(
              _transport(http, provider, target),
              registered,
              binding: binding,
            ),
          );
          // Then old unbound intent is never adopted or dispatched anonymously.
          expect(error, _submissionFailure('authRequired'));
          expect(legacy.calls, isEmpty);
          expect(advanced.legacyCalls, isEmpty);
          expect(advanced.advancedCalls, isEmpty);
          expect(http.requests, isEmpty);
        },
      );
    }

    for (final anonymous in [false, true]) {
      test(
        '$version legacy unbound anonymous=$anonymous remains compatible',
        () async {
          // Given legacy intent with explicitly authenticated or anonymous configuration.
          final credentials = _LegacyCredentials();
          final target = _target(anonymous: anonymous);
          final http = client()..respond(submissionJsonResponse(_ack()));
          // When the unchanged legacy route sends the packet.
          final accepted = await _submit(
            _transport(http, credentials, target),
            registered,
          );
          // Then bearer lookup remains id-only and anonymous remains credential-free.
          expect(accepted.requestId, 'book-1');
          expect(credentials.calls, anonymous ? isEmpty : ['studio']);
          expect(
            http.requests.single.headers['authorization'],
            anonymous ? isNull : 'Bearer $_access',
          );
        },
      );
    }

    test('$version target mismatch precedes advanced lookup', () async {
      // Given a bound packet pinned to a different target from this transport.
      final credentials = _AdvancedCredentials();
      final http = client();
      final transport = _transport(http, credentials, _target(id: 'other'));
      // When actual submit checks its frozen target.
      final error = await _capture(
        () => _submit(
          transport,
          registered,
          binding: _binding(),
          packetTarget: _target(),
        ),
      );
      // Then mismatched target is rejected before any authorization work.
      expect(error, _submissionFailure('connectionMismatch'));
      expect(credentials.advancedCalls, isEmpty);
      expect(credentials.legacyCalls, isEmpty);
      expect(http.requests, isEmpty);
    });
  }

  for (final operation in ['readonly', 'mutating', 'multipart']) {
    test('TKL $operation selects the captured actor and configured service root', () async {
      // Given controlled TKL responses and an explicit local actor captured by composition.
      final binding = _binding();
      final root = _target(tkl: true);
      final credentials = _AdvancedCredentials();
      final http = client()
        ..respond(
          submissionJsonResponse(
            operation == 'readonly' ? _destination() : _snapshot(),
          ),
        );
      final remote = _tkl(http, credentials, root, binding);
      // When a real readonly, JSON mutation or multipart operation uses _call.
      final result = await _tklCall(remote, operation);
      // Then only the root/actor select ACCESS; no server owner fields are invented.
      expect(result, isNotNull);
      expect(credentials.advancedCalls, hasLength(1));
      expect(credentials.advancedCalls.single.$1, same(binding));
      expect(credentials.advancedCalls.single.$2, same(root));
      expect(credentials.legacyCalls, isEmpty);
      final sent = http.requests.single;
      expect(
        sent.uri,
        root.endpoint.resolve(switch (operation) {
          'readonly' => 'getDestination',
          'mutating' => 'prepare',
          _ => 'uploadOriginal',
        }),
      );
      expect(sent.method, operation == 'readonly' ? 'GET' : 'POST');
      expect(sent.headers['authorization'], 'Bearer $_access');
      expect(sent.followsRedirects, isFalse);
      final body = utf8.decode(sent.bytes);
      expect(
        body,
        allOf(
          isNot(contains(_account)),
          isNot(contains('authenticationBinding')),
          isNot(contains('authority')),
          isNot(contains(_refresh)),
        ),
      );
      if (operation == 'readonly') {
        expect(sent.bytes, isEmpty);
      } else if (operation == 'mutating') {
        expect(sent.json, {
          'requestId': 'book-1',
          'contribution': {'title': ' Book '},
        });
        expect(
          result,
          isA<TklMaterialDeliverySnapshot>().having(
            (value) => value.requestId,
            'request',
            'book-1',
          ),
        );
      } else {
        expect(
          sent.headers['content-type'],
          startsWith('multipart/form-data;'),
        );
        expect(RegExp('name="[^"]+"').allMatches(body).map((m) => m[0]), [
          'name="deliveryRef"',
          'name="resourceId"',
          'name="content"',
          'name="original"',
        ]);
        expect(body, contains('ABC'));
        expect(
          result,
          isA<TklMaterialDeliverySnapshot>().having(
            (value) => value.resources.single.byteLength,
            'original length',
            3,
          ),
        );
      }
    });

    for (final mode in ['bound legacy', 'unbound advanced']) {
      test('TKL $operation $mode denies before provider and send', () async {
        // Given a configuration that must never select either credential method.
        final advanced = _AdvancedCredentials();
        final legacy = _LegacyCredentials();
        final http = client();
        final remote = _tkl(
          http,
          mode == 'bound legacy' ? legacy : advanced,
          _target(tkl: true),
          mode == 'bound legacy' ? _binding() : null,
        );
        // When the real selected TKL operation attempts dispatch.
        final error = await _capture(() => _tklCall(remote, operation));
        // Then denial is safe and never reports a possible remote mutation.
        expect(
          error,
          isA<TklMaterialDeliveryHttpException>()
              .having((e) => e.code, 'code', 'authRequired')
              .having((e) => e.retryable, 'retryable', isFalse)
              .having((e) => e.outcomeUnknown, 'unknown', isFalse),
        );
        expect(legacy.calls, isEmpty);
        expect(advanced.legacyCalls, isEmpty);
        expect(advanced.advancedCalls, isEmpty);
        expect(http.requests, isEmpty);
      });
    }
  }

  for (final deadline in [false, true]) {
    testWidgets(
      'held advanced lookup ${deadline ? 'deadline' : 'cancellation'} stays notSent',
      (tester) async {
        // Given an advanced lookup held before HTTP and an observable cancellation.
        final lookup = Completer<String?>();
        final cancellation = Completer<void>();
        final credentials = _AdvancedCredentials()
          ..lookup = () => lookup.future;
        final http = client();
        final transport = _transport(
          http,
          credentials,
          _target(),
          cancellation: cancellation.future,
          timeout: const Duration(seconds: 10),
        );
        Object? observed;
        var completed = false;
        // When submit waits for ACCESS and its original lifetime is withdrawn.
        _capture(() => transport.submit(_packet(_binding()))).then((error) {
          observed = error;
          completed = true;
        });
        await tester.pump();
        if (deadline) {
          await tester.pump(const Duration(seconds: 10));
        } else {
          cancellation.complete();
        }
        await tester.pump();
        // Then retirement wins, and a late provider failure is observed without dispatch.
        expect(completed, isTrue);
        expect(
          observed,
          _submissionFailure(
            deadline ? 'operationTimeout' : 'operationCancelled',
            stage: SubmissionFailureStage.transport,
            retryable: true,
          ),
        );
        lookup.completeError(StateError(_privateCause));
        await tester.pump();
        expect('$observed', isNot(contains(_privateCause)));
        expect(credentials.advancedCalls, hasLength(1));
        expect(credentials.legacyCalls, isEmpty);
        expect(http.requests, isEmpty);
      },
    );
  }

  test('retired predicate discards a held matching ACK as unknown', () async {
    // Given a matching ACK held after actual HTTP send.
    final sent = Completer<void>();
    final reply = Completer<http_api.StreamedResponse>();
    var current = true;
    final http = client()
      ..handler = (_) {
        sent.complete();
        return reply.future;
      };
    final credentials = _AdvancedCredentials();
    final transport = _transport(
      http,
      credentials,
      _target(),
      isCurrent: () => current,
    );
    // When the actor retires before the response is released.
    final outcome = _capture(() => transport.submit(_packet(_binding())));
    await sent.future;
    current = false;
    reply.complete(submissionJsonResponse(_ack()));
    final error = await outcome;
    // Then the late server result cannot become current acceptance.
    expect(
      error,
      _submissionFailure(
        'operationCancelled',
        stage: SubmissionFailureStage.transport,
        retryable: true,
        outcome: SubmissionTransportFailureOutcome.unknown,
      ),
    );
    expect(http.requests, hasLength(1));
    expect(credentials.advancedCalls, hasLength(1));
    expect(credentials.legacyCalls, isEmpty);
  });

  testWidgets('credential wait and held ACK share the original total deadline', (
    tester,
  ) async {
    // Given a 10s operation whose advanced credential lookup consumes 7s.
    final lookup = Completer<String?>();
    final reply = Completer<http_api.StreamedResponse>();
    final credentials = _AdvancedCredentials()..lookup = () => lookup.future;
    final http = client()..handler = (_) => reply.future;
    final transport = _transport(
      http,
      credentials,
      _target(),
      timeout: const Duration(seconds: 10),
    );
    Object? observed;
    var completed = false;
    // When credentials arrive at 7s but the ACK is still held at the original 10s.
    _capture(() => transport.submit(_packet(_binding()))).then((error) {
      observed = error;
      completed = true;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    lookup.complete(_access);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final completedBeforeDeadline = completed;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    // Then the deadline was not restarted, and the late ACK remains discarded.
    expect(completedBeforeDeadline, isFalse);
    expect(completed, isTrue);
    expect(
      observed,
      _submissionFailure(
        'operationTimeout',
        stage: SubmissionFailureStage.transport,
        retryable: true,
        outcome: SubmissionTransportFailureOutcome.unknown,
      ),
    );
    expect(http.requests, hasLength(1));
    reply.complete(submissionJsonResponse(_ack()));
    await tester.pump();
  });

  test(
    'accepted native account scope supplies only ACCESS and retires on logout',
    () async {
      // Given real backend/client/native-store APIs and a test-local protected CAS seam.
      const channel = MethodChannel(
        'org.textus.flutter.core/authentication_credentials',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final native = _NativeCas();
      messenger.setMockMethodCallHandler(channel, native.handle);
      final store = NativeAuthenticationCredentialStore();
      var authRequests = 0;
      final authHttp = MockClient((_) async {
        final step = authRequests++;
        if (step >= 2) {
          return http_api.Response.bytes(const <int>[], 200);
        }
        return http_api.Response.bytes(
          utf8.encode(
            jsonEncode(switch (step) {
              0 => {
                'user_account_id': _account,
                'credential_id': 'synthetic/credential',
                'access_session_id': 'synthetic/access-session',
                'access_token': _access,
                'refresh_session_id': 'synthetic/refresh-session',
                'refresh_token': _refresh,
                'authenticated': true,
              },
              _ => {'id': _account, 'handle': 'Synthetic'},
            }),
          ),
          200,
        );
      });
      final backend = UserAccountHttpAuthenticationBackend(
        profile: _profile(),
        client: authHttp,
        credentialStore: store,
      );
      final account = UserAccountAuthenticationClient(backend: backend);
      addTearDown(() async {
        try {
          await account.close();
          await backend.close();
          await store.close();
        } finally {
          authHttp.close();
          messenger.setMockMethodCallHandler(channel, null);
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      });
      await account.signIn(identifier: 'synthetic', password: 'synthetic');
      final target = _target();
      final callsBeforeScope = List<String>.of(native.calls);
      final scope = backend.createSubmissionScope(
        trustedTargets: [target],
        isRunCurrent: () => true,
      );
      final http = client()..respond(submissionJsonResponse(_ack()));
      final transport = _transport(http, scope, target);
      final callsAfterConstruction = List<String>.of(native.calls);
      // When the real scope reads its accepted native owner for a matching HTTP endpoint.
      final accepted = await transport.submit(_packet(scope.binding));
      // Then inert composition led to one readonly ACCESS lookup and a matching ACK.
      expect(account.snapshot.isAuthenticated, isTrue);
      expect(accepted.requestId, 'book-1');
      expect(callsAfterConstruction, callsBeforeScope);
      expect(native.calls, [...callsBeforeScope, 'read']);
      expect(authRequests, 2);
      expect(http.requests.single.headers['authorization'], 'Bearer $_access');
      expect(
        http.requests.single.headers.values,
        everyElement(isNot(contains(_refresh))),
      );
      expect(
        utf8.decode(http.requests.single.bytes),
        isNot(contains(_refresh)),
      );
      // Given the old immutable binding and scope after explicit account retirement.
      await account.signOut();
      final beforeRetiredAttempt = List<String>.of(native.calls);
      // When a later dispatch tries to reuse that old accepted scope.
      final error = await _capture(
        () => transport.submit(_packet(scope.binding)),
      );
      // Then the scope denies without native lookup, HTTP dispatch or refresh forwarding.
      expect(error, _submissionFailure('authRequired'));
      expect(scope.context.isCurrent, isFalse);
      expect(native.calls, beforeRetiredAttempt);
      expect(http.requests, hasLength(1));
      expect(authRequests, 3);
    },
  );

  for (final advanced in [false, true]) {
    test(
      'direct byte and chunk PUTs ignore ${advanced ? 'advanced' : 'legacy'} credentials',
      () async {
        // Given supplied narrow provider sessions and counting application credential ports.
        final legacy = _LegacyCredentials();
        final scoped = _AdvancedCredentials();
        final http = client();
        http.handler = (request) {
          final lastChunk =
              request.headers['content-range'] == 'bytes 262144-262146/262147';
          return http_api.StreamedResponse(
            const Stream<List<int>>.empty(),
            http.requests.length == 1 || lastChunk ? 201 : 308,
            headers: {if (http.requests.length == 2) 'range': 'bytes=0-262143'},
          );
        };
        final remote = _tkl(
          http,
          advanced ? scoped : legacy,
          _target(tkl: true),
          _binding(),
        );
        final bytes = Uint8List.fromList([0, 1, 128, 255]);
        const total = 262147;
        final ranges = <(int, int)>[];
        // When both real direct APIs send only the provider-confirmed byte ranges.
        final direct = await remote.uploadDirect(
          instruction: _instruction(4, offset: 2),
          content: bytes,
        );
        final streamed = await remote.uploadDirectStream(
          instruction: _instruction(total),
          totalLength: total,
          openRange: (start, end) {
            ranges.add((start, end));
            return _range(start, end);
          },
        );
        // Then no UA/legacy lookup or Authorization is used, including later chunks.
        expect(direct.byteLength, 4);
        expect(streamed.byteLength, total);
        expect(legacy.calls, isEmpty);
        expect(scoped.advancedCalls, isEmpty);
        expect(scoped.legacyCalls, isEmpty);
        expect(ranges, [(0, 262144), (262144, total)]);
        expect(http.requests.map((r) => r.headers['content-range']), [
          'bytes 2-3/4',
          'bytes 0-262143/262147',
          'bytes 262144-262146/262147',
        ]);
        expect(http.requests.first.bytes, [128, 255]);
        expect(http.requests[1].bytes, List.generate(262144, (i) => i % 251));
        expect(
          http.requests[2].bytes,
          List.generate(3, (i) => (262144 + i) % 251),
        );
        for (final sent in http.requests) {
          expect(sent.method, 'PUT');
          expect(sent.uri, _instruction(total).uploadUri);
          expect(sent.headers.containsKey('authorization'), isFalse);
          expect(sent.followsRedirects, isFalse);
        }
      },
    );
  }

  for (final uri in [
    'https://foreign.example.test/upload/drive/v3/files?uploadType=resumable&upload_id=x',
    'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x&upload_id=y',
    'http://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x',
  ]) {
    test('direct instruction retains its narrow URI restriction: $uri', () {
      // Given a supplied session URI outside the accepted narrow instruction syntax.
      Object? error;
      // When the actual instruction validates it once.
      try {
        _instruction(4, uri: uri);
      } catch (caught) {
        error = caught;
      }
      // Then the instruction rejects it before any upload can be requested.
      expect(error, isA<ArgumentError>());
    });
  }
}

UserAccountHttpProfile _profile() => UserAccountHttpProfile(
  profileId: 'transport-profile',
  serviceBaseUri: Uri.parse('https://account.example.test/user-account/'),
);
SubmissionAuthenticationBinding _binding() => SubmissionAuthenticationBinding(
  authority: _profile(),
  userAccountId: _account,
);
HttpSubmissionConnection _target({
  String id = 'studio',
  bool anonymous = false,
  bool tkl = false,
}) => HttpSubmissionConnection(
  id: id,
  endpoint: Uri.parse(
    tkl
        ? 'https://lake.example.test/material-delivery/'
        : 'https://studio.example.test/submit',
  ),
  requiresBearerToken: !anonymous,
);

SubmissionRequest _request(
  SubmissionAuthenticationBinding? binding, {
  bool registered = false,
}) => SubmissionRequest(
  id: 'book-1',
  kind: 'bookMaterial',
  subjectId: 'book-1',
  createdAt: DateTime.utc(2026, 11, 6),
  document: const {'local': 'draft'},
  payload: registered
      ? const {
          'schemaVersion': 1,
          'type': 'bookMaterial',
          'material': {'schemaVersion': 2, 'id': 'book-1'},
          'recognitionReports': {},
        }
      : const {'title': ' Book '},
  materials: const [],
  transportConnectionId: 'studio',
  authenticationBinding: binding,
  tklDelivery: registered
      ? TklMaterialDeliveryRequest(
          requestId: 'book-1',
          contribution: const {'title': ' Book '},
        )
      : null,
);
SubmissionPacket _packet(SubmissionAuthenticationBinding? binding) =>
    SubmissionPacket(request: _request(binding), receipts: const {});
RegisteredMaterialSubmissionPacket _registered(
  SubmissionAuthenticationBinding? binding,
  HttpSubmissionConnection target,
) => RegisteredMaterialSubmissionPacket(
  sourceRequest: _request(binding, registered: true),
  target: target,
  association: RegisteredMaterialAssociation(
    materialRef: 'urn:synthetic:material',
    resources: const [],
  ),
);
Future<SubmissionAcknowledgement> _submit(
  HttpSubmissionTransport transport,
  bool registered, {
  SubmissionAuthenticationBinding? binding,
  HttpSubmissionConnection? packetTarget,
}) => registered
    ? transport.submitRegisteredMaterial(
        _registered(binding, packetTarget ?? transport.connection),
      )
    : transport.submit(_packet(binding));

Map<String, Object?> _ack() => SubmissionCodec.acknowledgementToJson(
  SubmissionAcknowledgement(
    requestId: 'book-1',
    subjectId: 'book-1',
    serverId: 'synthetic/accepted',
    receivedAt: DateTime.utc(2026, 11, 6),
  ),
);
HttpSubmissionTransport _transport(
  http_api.Client client,
  SubmissionCredentialProvider credentials,
  HttpSubmissionConnection target, {
  Future<void>? cancellation,
  bool Function()? isCurrent,
  Duration timeout = const Duration(seconds: 45),
}) => HttpSubmissionTransport(
  connection: target,
  client: client,
  credentials: credentials,
  cancellation: cancellation,
  isRunCurrent: isCurrent,
  operationTimeout: timeout,
);
TklMaterialDeliveryHttpClient _tkl(
  http_api.Client client,
  SubmissionCredentialProvider credentials,
  HttpSubmissionConnection root,
  SubmissionAuthenticationBinding? binding,
) => TklMaterialDeliveryHttpClient(
  connection: root,
  client: client,
  credentials: credentials,
  authenticationBinding: binding,
);
Future<Object?> _tklCall(
  TklMaterialDeliveryHttpClient client,
  String operation,
) => switch (operation) {
  'readonly' => client.getDestination(),
  'mutating' => client.prepare(
    TklMaterialDeliveryRequest(
      requestId: 'book-1',
      contribution: const {'title': ' Book '},
    ),
  ),
  _ => client.uploadOriginal(
    deliveryRef: 'delivery-1',
    resourceId: 'cover',
    mediaType: 'image/png',
    content: Uint8List.fromList([65, 66, 67]),
  ),
};
Map<String, Object?> _destination() => {
  'availability': 'available',
  'destinationId': 'selected',
  'label': 'Library',
  'transferMethod': 'googleDriveResumable',
};
Map<String, Object?> _snapshot() => {
  'deliveryRef': 'delivery-1',
  'requestId': 'book-1',
  'revision': 1,
  'destinationId': 'selected',
  'destinationLabel': 'Library',
  'state': 'prepared',
  'resources': [
    {
      'resourceId': 'cover',
      'mediaType': 'image/png',
      'byteLength': 3,
      'state': 'pending',
    },
  ],
};
Matcher _submissionFailure(
  String code, {
  bool retryable = false,
  SubmissionFailureStage stage = SubmissionFailureStage.configuration,
  SubmissionTransportFailureOutcome outcome =
      SubmissionTransportFailureOutcome.notSent,
}) => isA<SubmissionAdapterException>()
    .having((e) => e.code, 'code', code)
    .having((e) => e.stage, 'stage', stage)
    .having((e) => e.retryable, 'retryable', retryable)
    .having((e) => e.transportFailureOutcome, 'outcome', outcome);
Future<Object?> _capture<T>(Future<T> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

final class _LegacyCredentials implements SubmissionCredentialProvider {
  final calls = <String>[];
  @override
  Future<String?> bearerToken(String connectionId) async {
    calls.add(connectionId);
    return _access;
  }
}

final class _AdvancedCredentials
    implements AuthenticatedSubmissionCredentialProvider {
  final legacyCalls = <String>[];
  final advancedCalls =
      <(SubmissionAuthenticationBinding, HttpSubmissionConnection)>[];
  FutureOr<String?> Function()? lookup;
  @override
  Future<String?> bearerToken(String connectionId) async {
    legacyCalls.add(connectionId);
    return _access;
  }

  @override
  Future<String?> bearerTokenFor({
    required SubmissionAuthenticationBinding binding,
    required HttpSubmissionConnection connection,
  }) {
    advancedCalls.add((binding, connection));
    return Future<String?>.sync(lookup ?? () => _access);
  }
}

final class _NativeCas {
  Uint8List? _value;
  String? _revision;
  int _sequence = 0;
  final calls = <String>[];
  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final args = call.arguments as Map;
    switch (call.method) {
      case 'read':
        return _value == null
            ? null
            : {'revision': _revision, 'value': Uint8List.fromList(_value!)};
      case 'replace':
        if (args['expectedRevision'] != _revision) return null;
        _value = Uint8List.fromList(args['value'] as Uint8List);
        _revision = (++_sequence).toRadixString(16).padLeft(32, '0');
        return _revision;
      case 'remove':
        if (_value == null || args['expectedRevision'] != _revision) {
          return false;
        }
        _value = null;
        _revision = null;
        return true;
      case 'close':
        return null;
      default:
        throw StateError('Unexpected synthetic native operation');
    }
  }
}

TklDirectTransferInstruction _instruction(
  int total, {
  int offset = 0,
  String? uri,
}) => TklDirectTransferInstruction(
  transferRef: 'synthetic/transfer',
  resourceId: 'cover',
  uploadUri: Uri.parse(
    uri ?? 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=synthetic-session',
  ),
  mediaType: 'application/octet-stream',
  byteLength: total,
  nextOffset: offset,
);
Stream<List<int>> _range(int start, int end) async* {
  for (var offset = start; offset < end;) {
    final limit = offset + 65536 < end ? offset + 65536 : end;
    yield List.generate(limit - offset, (i) => (offset + i) % 251);
    offset = limit;
  }
}
