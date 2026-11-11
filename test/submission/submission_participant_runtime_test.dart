import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/src/submission/submission_participant_runtime.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ParticipantNativeStore native;
  late List<SubmissionParticipantRuntime> owners;
  late List<ParticipantLogin> logins;
  TargetPlatform? previousPlatform;

  setUp(() {
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = ParticipantNativeStore();
    owners = [];
    logins = [];
    messenger.setMockMethodCallHandler(
      participantCredentialChannel,
      native.handle,
    );
  });
  tearDown(() async {
    try {
      for (final owner in owners) {
        await owner.close();
      }
      for (final login in logins) {
        await login.close();
      }
    } finally {
      messenger.setMockMethodCallHandler(participantCredentialChannel, null);
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  Future<ParticipantLogin> login({String account = 'A'}) async {
    final result = ParticipantLogin();
    logins.add(result);
    await result.signIn(account: account);
    return result;
  }

  Future<SubmissionParticipantRuntime> open({
    SubmissionConfigurationSnapshot? snapshot,
    SubmissionCredentialProvider? legacy,
    SubmissionRunLifetime? lifetime,
    UserAccountSubmissionScope? scope,
    bool restore = false,
    bool required = false,
    ParticipantHttp? transport,
  }) async {
    final result = await http.runWithClient(
      () => SubmissionParticipantRuntime.open(
        snapshot: snapshot ?? participantSnapshot(),
        legacyCredentials: legacy ?? ParticipantLegacyCredentials(),
        lifetime: lifetime ?? SubmissionRunLifetime(id: 'runtime'),
        authenticationScope: scope,
        restoreParticipantAuthentication: restore,
        requiresAuthentication: required,
      ),
      () => transport ?? (throw StateError('Unexpected auth construction')),
    );
    owners.add(result);
    return result;
  }

  test(
    'legacy open remains inert even when explicit restore is requested',
    () async {
      // Given a legacy snapshot and an observable independently owned credential port.
      final legacy = ParticipantLegacyCredentials();
      final lifetime = SubmissionRunLifetime(id: 'legacy');
      // When restore is requested without any participant declaration.
      final owner = await open(
        snapshot: participantSnapshot(declared: false),
        legacy: legacy,
        lifetime: lifetime,
        restore: true,
      );
      // Then no auth backend/client, native call or credential lookup was constructed.
      expect(owner.requiresAuthentication, isFalse);
      expect(owner.credentials, same(legacy));
      expect(owner.authenticationContext, isNull);
      expect(owner.binding, isNull);
      expect(owner.isCurrent, isTrue);
      expect(owner.permits(participantTarget()), isTrue);
      expect(owner.permits(participantTarget(id: 'outside')), isTrue);
      expect(native.calls, isEmpty);
      expect(legacy.calls, isEmpty);
      final closing = owner.close();
      expect(owner.close(), same(closing));
      expect(owner.isCurrent, isFalse);
      await closing;
      expect(lifetime.isCurrent, isTrue);
      expect(await legacy.bearerToken('server'), 'SYNTHETIC.LEGACY=');
    },
  );

  for (final declared in [false, true]) {
    test(
      'required mode without accepted scope is blocked with declaration $declared',
      () async {
        // Given explicit participant policy and no accepted owner, with observable legacy IO.
        final legacy = ParticipantLegacyCredentials();
        // When the runtime opens inertly, including explicit restore on missing config.
        final owner = await open(
          snapshot: participantSnapshot(declared: declared),
          legacy: legacy,
          required: true,
          restore: !declared,
        );
        final provider =
            owner.credentials as AuthenticatedSubmissionCredentialProvider;
        final legacyToken = await provider.bearerToken('server');
        final boundToken = await provider.bearerTokenFor(
          binding: participantBinding(),
          connection: participantTarget(),
        );
        // Then both ports deny without manufacturing identity, auth IO or legacy fallback.
        expect(owner.requiresAuthentication, isTrue);
        expect(owner.authenticationContext, isNull);
        expect(owner.binding, isNull);
        expect(owner.isCurrent, isFalse);
        expect(owner.permits(participantTarget()), declared);
        expect(legacyToken, isNull);
        expect(boundToken, isNull);
        expect(legacy.calls, isEmpty);
        expect(native.calls, isEmpty);
        expect('$owner', 'SubmissionParticipantRuntime');
      },
    );
  }

  for (final mismatch in ['missing declaration', 'profile', 'base']) {
    test('scope rejects $mismatch before callback or IO', () async {
      // Given a real accepted owner whose callback visibly counts invocation.
      final accepted = await login();
      var callbacks = 0;
      final scope = accepted.scope(
        isCurrent: () {
          callbacks++;
          return true;
        },
      );
      final calls = List<String>.of(native.calls);
      final requests = accepted.transport.requests.length;
      final snapshot = participantSnapshot(
        declared: mismatch != 'missing declaration',
        profileId: mismatch == 'profile' ? 'other' : participantProfileId,
        base: mismatch == 'base'
            ? 'https://elsewhere.test/account/'
            : participantBase,
      );
      // When composition is attempted across the absent or mismatched authority.
      final error = await participantCapture(
        () => open(snapshot: snapshot, scope: scope),
      );
      // Then exact authority admission fails safely and has no credential/current callback.
      expectParticipantUnavailable(error);
      expect(callbacks, 0);
      expect(native.calls, calls);
      expect(accepted.transport.requests, hasLength(requests));
    });
  }

  test('borrowed scope opens without callback and survives helper close', () async {
    // Given an actual accepted A backend and independently owned root scope.
    final accepted = await login();
    var callbacks = 0;
    final scope = accepted.scope(
      isCurrent: () {
        callbacks++;
        return true;
      },
    );
    final calls = List<String>.of(native.calls);
    // When a batch borrows the exact scope, even with restore explicitly enabled.
    final owner = await open(scope: scope, restore: true);
    // Then open does not invoke the callback, read native storage or construct auth IO.
    expect(callbacks, 0);
    expect(native.calls, calls);
    expect(owner.credentials, same(scope));
    expect(owner.binding, same(scope.binding));
    expect(owner.authenticationContext, same(scope.context));
    expect(owner.isCurrent, isTrue);
    await owner.close();
    // When the root owner performs a later advanced lookup after batch cleanup.
    final token = await scope.bearerTokenFor(
      binding: scope.binding,
      connection: participantTarget(),
    );
    // Then borrowing left the root backend, protected record and scope current.
    expect(token, ParticipantLogin.access('A'));
    expect(scope.context.isCurrent, isTrue);
    expect(accepted.transport.closeCalls, 0);
    expect(native.calls, [...calls, 'read']);
    expect(native.document()['userAccountId'], 'A');
  });

  test('only exact declared target definitions are permitted', () async {
    // Given A accepted for two targets and a same-origin outsider in the snapshot.
    final accepted = await login();
    final owner = await open(scope: accepted.scope());
    // When each id, endpoint and bearer flag edge is probed without dispatch.
    final permitted = [
      owner.permits(participantTarget()),
      owner.permits(participantTarget(id: 'lake', path: '/delivery/')),
      owner.permits(participantTarget(id: 'outside')),
      owner.permits(participantTarget(path: '/another')),
      owner.permits(participantTarget(authenticated: false)),
    ];
    // Then no same-origin inference or incomplete definition match expands trust.
    expect(permitted, [true, true, false, false, false]);
  });

  test('real restore publishes only accepted A binding and ACCESS', () async {
    // Given credentials seeded by actual login, then owned handles closed without logout.
    final accepted = await login();
    await accepted.close();
    final saved = native.read();
    final transport = ParticipantHttp()..json(participantAccount('A'));
    final legacy = ParticipantLegacyCredentials();
    // When explicit headless restoration uses the actual backend/client/native CAS path.
    final owner = await open(
      restore: true,
      transport: transport,
      legacy: legacy,
    );
    final token =
        await (owner.credentials as AuthenticatedSubmissionCredentialProvider)
            .bearerTokenFor(
              binding: owner.binding!,
              connection: participantTarget(),
            );
    // Then actual accepted account identity, get-my-account and readonly ACCESS agree.
    expect(owner.binding, participantBinding());
    expect(owner.authenticationContext!.binding, same(owner.binding));
    expect(owner.isCurrent, isTrue);
    expect(token, ParticipantLogin.access('A'));
    expect(token, isNot(ParticipantLogin.refresh('A')));
    expect(transport.requests.single.url.path, '/account/get-my-account');
    expect(
      transport.requests.single.headers['Authorization'],
      'Bearer ${ParticipantLogin.access('A')}',
    );
    expect(native.read(), saved);
    expect(legacy.calls, isEmpty);
    await owner.close();
    expect(transport.closeCalls, 1);
    expect(native.document()['userAccountId'], 'A');
    expect(native.calls.where((call) => call == 'clear'), isEmpty);
  });

  test('real restored B never adopts persisted A intent', () async {
    // Given a protected B session seeded by real login and a separate saved A binding.
    final accepted = await login(account: 'B');
    await accepted.close();
    final transport = ParticipantHttp()..json(participantAccount('B'));
    final owner = await open(restore: true, transport: transport);
    final calls = List<String>.of(native.calls);
    // When A attempts to use the advanced credentials of the accepted B composition.
    final token =
        await (owner.credentials as AuthenticatedSubmissionCredentialProvider)
            .bearerTokenFor(
              binding: participantBinding(),
              connection: participantTarget(),
            );
    // Then B identity is exact and A denial precedes protected lookup or erasure.
    expect(owner.binding, participantBinding(account: 'B'));
    expect(token, isNull);
    expect(native.calls, calls);
    expect(native.document()['userAccountId'], 'B');
  });

  test('a newer native B session never supplies credentials to an accepted A runtime', () async {
    // Given actual accepted A and an inert runtime borrowing that exact scope.
    final accepted = await login();
    final owner = await open(scope: accepted.scope());
    // When a separate actual login accepts B into the same protected profile.
    await login(account: 'B');
    final retained = native.read();
    final token =
        await (owner.credentials as AuthenticatedSubmissionCredentialProvider)
            .bearerTokenFor(
              binding: owner.binding!,
              connection: participantTarget(),
            );
    // Then protected ownership rechecking denies A without adopting or erasing B.
    expect(owner.binding, participantBinding());
    expect(token, isNull);
    expect(native.document()['userAccountId'], 'B');
    expect(native.read(), retained);
    expect(native.calls.where((call) => call == 'clear'), isEmpty);
  });

  for (final credential in ['absent', 'refused']) {
    test(
      '$credential protected credentials restore to readable blocked mode',
      () async {
        // Given either no protected entry or a genuinely seeded session refused by authority.
        if (credential == 'refused') {
          final accepted = await login();
          await accepted.close();
        }
        final transport = ParticipantHttp();
        if (credential == 'refused') transport.json({}, status: 403);
        final legacy = ParticipantLegacyCredentials();
        // When the real restore path reports no accepted account.
        final owner = await open(
          restore: true,
          transport: transport,
          legacy: legacy,
        );
        final token = await owner.credentials.bearerToken('server');
        // Then no dummy identity or legacy bearer can turn this into usable authentication.
        expect(owner.requiresAuthentication, isTrue);
        expect(owner.authenticationContext, isNull);
        expect(owner.binding, isNull);
        expect(owner.isCurrent, isFalse);
        expect(token, isNull);
        expect(legacy.calls, isEmpty);
        expect(transport.requests, hasLength(credential == 'absent' ? 0 : 1));
      },
    );
  }

  test('restore 401 follows the existing single protected rotation', () async {
    // Given real retained A credentials and a controlled 401 then valid rotation/account.
    final accepted = await login();
    await accepted.close();
    final transport = ParticipantHttp()
      ..json({}, status: 401)
      ..json(participantRotation('A'))
      ..json(participantAccount('A'));
    // When owned restore performs its existing backend protocol once.
    final owner = await open(restore: true, transport: transport);
    final token =
        await (owner.credentials as AuthenticatedSubmissionCredentialProvider)
            .bearerTokenFor(
              binding: owner.binding!,
              connection: participantTarget(),
            );
    // Then only get-my-account/refresh/get-my-account ran, without a runtime retry.
    expect(transport.requests.map((request) => request.url.path), [
      '/account/get-my-account',
      '/account/refresh-access-token',
      '/account/get-my-account',
    ]);
    expect(owner.binding, participantBinding());
    expect(token, ParticipantLogin.access('A', rotated: true));
    expect(native.document()['accessToken'], token);
  });

  test(
    'stop during held native restore cannot publish and joins owned cleanup',
    () async {
      // Given a real retained session whose next native restore read is held.
      final accepted = await login();
      await accepted.close();
      final saved = native.read();
      final entered = Completer<void>();
      final release = Completer<Object?>();
      native.onRead = (_) {
        entered.complete();
        return release.future;
      };
      final transport = ParticipantHttp();
      final lifetime = SubmissionRunLifetime(id: 'stopped_restore');
      var settled = false;
      final opening =
          participantCapture(
            () => open(restore: true, transport: transport, lifetime: lifetime),
          ).then((error) {
            settled = true;
            return error;
          });
      await entered.future;
      // When stop retires ownership before the accepted native read settles.
      lifetime.retire();
      await Future<void>.value();
      expect(settled, isFalse);
      release.complete(saved);
      final error = await opening;
      // Then no scope or auth request publishes, and every owned handle is drained.
      expectParticipantUnavailable(error);
      expect(transport.requests, isEmpty);
      expect(transport.closeCalls, 1);
      expect(native.calls.where((call) => call == 'close'), hasLength(2));
      expect(native.read(), saved);
    },
  );

  test('owned close retires held credential lookup and joins native close', () async {
    // Given actual owned restored A and a later accepted native lookup held open.
    final accepted = await login();
    await accepted.close();
    final transport = ParticipantHttp()..json(participantAccount('A'));
    final owner = await open(restore: true, transport: transport);
    final entered = Completer<void>();
    final nativeClosed = Completer<void>();
    final release = Completer<Object?>();
    final saved = native.read();
    native.onRead = (_) {
      entered.complete();
      return release.future;
    };
    native.onClose = (_) async {
      nativeClosed.complete();
      return null;
    };
    final lookup =
        (owner.credentials as AuthenticatedSubmissionCredentialProvider)
            .bearerTokenFor(
              binding: owner.binding!,
              connection: participantTarget(),
            );
    await entered.future;
    // When helper close retires ownership while the accepted lookup remains held.
    final closing = owner.close();
    var finished = false;
    final observed = closing.then((_) => finished = true);
    await nativeClosed.future;
    // Then retirement and owned HTTP close precede the unresolved native drain.
    expect(owner.isCurrent, isFalse);
    expect(owner.close(), same(closing));
    expect(finished, isFalse);
    expect(transport.closeCalls, 1);
    release.complete(saved);
    final token = await lookup;
    await observed;
    expect(token, isNull);
    expect(finished, isTrue);
    expect(native.read(), saved);
  });

  test('retired restore with failed staged rollback fails open safely after owned cleanup', () async {
    // Given retained A and a real 401 rotation held at its protected candidate write.
    final accepted = await login();
    await accepted.close();
    final entered = Completer<void>();
    final release = Completer<void>();
    native.onReplace = (args) async {
      entered.complete();
      await release.future;
      return native.replace(args);
    };
    var removals = 0;
    native.onRemove = (args) async {
      if (removals++ == 0) return native.remove(args);
      throw PlatformException(code: 'unavailable', message: 'PRIVATE.ROLLBACK');
    };
    final transport = ParticipantHttp()
      ..json({}, status: 401)
      ..json(participantRotation('A'))
      ..json(participantAccount('A'));
    final lifetime = SubmissionRunLifetime(id: 'failed_rollback');
    final opening = participantCapture(
      () => open(lifetime: lifetime, restore: true, transport: transport),
    );
    await entered.future;
    // When retirement withdraws publication and the actual staged rollback then fails.
    lifetime.retire();
    release.complete();
    final error = await opening;
    // Then cleanup failure cannot become a usable or empty successful auth composition.
    expectParticipantUnavailable(error);
    expect('$error', isNot(contains('PRIVATE')));
    expect(transport.closeCalls, 1);
    expect(native.calls.where((call) => call == 'close'), hasLength(2));
    expect(removals, greaterThanOrEqualTo(2));
    expect(lifetime.isCurrent, isFalse);
    native.onRemove = null;
  });

  for (final failure in ['native', 'http', 'both']) {
    test(
      'owned $failure close failure is safe honest and attempts every handle',
      () async {
        // Given actual restored ownership whose owned HTTP/native cleanup may fail.
        final accepted = await login();
        await accepted.close();
        final transport = ParticipantHttp()..json(participantAccount('A'));
        final owner = await open(restore: true, transport: transport);
        owners.remove(owner);
        transport.failClose = failure != 'native';
        if (failure != 'http') {
          native.onClose = (_) async => throw PlatformException(
            code: 'unavailable',
            message: 'PRIVATE.CLOSE',
          );
        }
        // When the returned close future is observed directly by an actual awaiter.
        final closing = owner.close();
        final error = await participantCapture(() => closing);
        // Then the same future retains a fixed honest error while all owners were attempted.
        expectParticipantUnavailable(error);
        expect(owner.close(), same(closing));
        expect(owner.isCurrent, isFalse);
        expect(transport.closeCalls, 1);
        expect(native.calls.where((call) => call == 'close'), hasLength(2));
        expect(native.value, isNotNull);
        expect(native.calls.where((call) => call == 'clear'), isEmpty);
      },
    );
  }
}

// Shared only by the two host specification libraries, never production exports.
const participantCredentialChannel = MethodChannel(
  'org.textus.flutter.core/authentication_credentials',
);
const participantProfileId = 'participant.main';
const participantBase = 'https://authority.example.test/account/';

HttpSubmissionConnection participantTarget({
  String id = 'server',
  String path = '/submit',
  bool authenticated = true,
}) => HttpSubmissionConnection(
  id: id,
  endpoint: Uri.parse('https://recipient.example.test$path'),
  requiresBearerToken: authenticated,
);

SubmissionConfigurationSnapshot participantSnapshot({
  bool declared = true,
  String profileId = participantProfileId,
  String base = participantBase,
}) => SubmissionConfigurationSnapshot(
  driveConnections: [],
  httpConnections: [
    participantTarget(),
    participantTarget(id: 'lake', path: '/delivery/'),
    participantTarget(id: 'outside'),
  ],
  participantAuthentication: declared
      ? SubmissionParticipantAuthenticationConfiguration(
          authorityProfileId: profileId,
          authorityBaseUri: base,
          trustedConnectionIds: ['server', 'lake'],
        )
      : null,
);

SubmissionAuthenticationBinding participantBinding({String account = 'A'}) =>
    SubmissionAuthenticationBinding(
      authority: UserAccountHttpProfile.fromString(
        profileId: participantProfileId,
        serviceBaseUri: participantBase,
      ),
      userAccountId: account,
    );

Map<String, Object?> participantAccount(String account) => {
  'id': account,
  'handle': 'Synthetic label',
};

Map<String, Object?> participantRotation(String account) => {
  'user_account_id': account,
  'access_session_id': 'synthetic/access-$account-v2',
  'access_token': ParticipantLogin.access(account, rotated: true),
  'refresh_session_id': 'synthetic/refresh-$account-v2',
  'refresh_token': ParticipantLogin.refresh(account, rotated: true),
  'authenticated': true,
};

Future<Object?> participantCapture<T>(Future<T> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

void expectParticipantUnavailable(Object? error) => expect(
  error,
  isA<StateError>().having(
    (error) => error.message,
    'fixed safe message',
    'Participant submission authentication is unavailable',
  ),
);

final class ParticipantLogin {
  ParticipantLogin() {
    backend = http.runWithClient(
      () => UserAccountHttpAuthenticationBackend(
        profile: UserAccountHttpProfile.fromString(
          profileId: participantProfileId,
          serviceBaseUri: participantBase,
        ),
      ),
      () => transport,
    );
    client = UserAccountAuthenticationClient(
      backend: backend,
      ownsBackend: true,
    );
  }

  final ParticipantHttp transport = ParticipantHttp();
  late final UserAccountHttpAuthenticationBackend backend;
  late final UserAccountAuthenticationClient client;

  static String access(String account, {bool rotated = false}) =>
      'SYNTHETIC.ACCESS.$account.${rotated ? 'v2' : 'v1'}=';
  static String refresh(String account, {bool rotated = false}) =>
      'SYNTHETIC.REFRESH.$account.${rotated ? 'v2' : 'v1'}==';

  Future<void> signIn({String account = 'A'}) async {
    transport.json({
      'user_account_id': account,
      'credential_id': 'synthetic/credential-$account',
      'access_session_id': 'synthetic/access-$account-v1',
      'access_token': access(account),
      'refresh_session_id': 'synthetic/refresh-$account-v1',
      'refresh_token': refresh(account),
      'authenticated': true,
    });
    transport.json(participantAccount(account));
    await client.signIn(identifier: 'synthetic', password: 'synthetic');
    expect(client.snapshot.isAuthenticated, isTrue);
  }

  UserAccountSubmissionScope scope({bool Function()? isCurrent}) =>
      backend.createSubmissionScope(
        trustedTargets: [
          participantTarget(),
          participantTarget(id: 'lake', path: '/delivery/'),
          participantTarget(id: 'outside'),
        ],
        isRunCurrent: isCurrent ?? () => true,
      );

  Future<void> close() => client.close();
}

final class ParticipantLegacyCredentials
    implements SubmissionCredentialProvider {
  final calls = <String>[];

  @override
  Future<String?> bearerToken(String connectionId) async {
    calls.add(connectionId);
    return 'SYNTHETIC.LEGACY=';
  }
}

final class ParticipantHttp extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final responses =
      <FutureOr<http.StreamedResponse> Function(http.BaseRequest)>[];
  FutureOr<http.StreamedResponse> Function(http.BaseRequest)? handler;
  int closeCalls = 0;
  bool failClose = false;
  void Function()? onClosed;

  void json(Object? body, {int status = 200}) =>
      responses.add((_) => reply(body, status: status));

  static http.StreamedResponse reply(Object? body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (handler != null) return await handler!(request);
    if (responses.isEmpty) throw StateError('Unexpected synthetic HTTP');
    return await responses.removeAt(0)(request);
  }

  @override
  void close() {
    closeCalls++;
    onClosed?.call();
    if (failClose) throw StateError('PRIVATE.HTTP.CLOSE');
  }
}

final class ParticipantNativeStore {
  final calls = <String>[];
  final handles = <String, String>{};
  Uint8List? value;
  String? revision;
  int sequence = 100;
  FutureOr<Object?> Function(Map)? onRead;
  FutureOr<Object?> Function(Map)? onReplace;
  FutureOr<Object?> Function(Map)? onRemove;
  FutureOr<Object?> Function(Map)? onClose;

  Map<String, dynamic> document() =>
      jsonDecode(utf8.decode(value!)) as Map<String, dynamic>;
  Object? read() => value == null
      ? null
      : {'revision': revision, 'value': Uint8List.fromList(value!)};

  Object? replace(Map args) {
    if (args['expectedRevision'] != revision) return null;
    value = Uint8List.fromList(args['value'] as Uint8List);
    revision = (++sequence).toRadixString(16).padLeft(32, '0');
    return revision;
  }

  Object? remove(Map args) {
    if (value == null || args['expectedRevision'] != revision) return false;
    value = null;
    revision = null;
    return true;
  }

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final args = call.arguments as Map;
    handles[args['handleId'] as String] = call.method;
    return switch (call.method) {
      'read' => onRead == null ? read() : await onRead!(args),
      'replace' => onReplace == null ? replace(args) : await onReplace!(args),
      'remove' => onRemove == null ? remove(args) : await onRemove!(args),
      'close' => onClose == null ? null : await onClose!(args),
      _ => throw StateError('Unexpected synthetic native method'),
    };
  }
}
