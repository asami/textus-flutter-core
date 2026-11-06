import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('CORE-CONFIG-05 participant declaration', () {
    test('construction and authority projection are inert and token free', () {
      // Given counting network, timer and microtask boundaries with no session.
      var networkCalls = 0;
      var timerCalls = 0;
      var microtaskCalls = 0;
      // When the real DTO and its authority projection are constructed.
      final observed = HttpOverrides.runZoned(
        () => runZoned(
          () {
            final value = _configuration();
            final authority = value.authority;
            return (configuration: value, authority: authority);
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              timerCalls++;
              return parent.createTimer(zone, duration, callback);
            },
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              timerCalls++;
              return parent.createPeriodicTimer(zone, duration, callback);
            },
            scheduleMicrotask: (self, parent, zone, callback) {
              microtaskCalls++;
              parent.scheduleMicrotask(zone, callback);
            },
          ),
        ),
        createHttpClient: (context) {
          networkCalls++;
          throw StateError('Unexpected network construction');
        },
      );
      // Then construction allocates no work and emits only the closed safe DTO.
      expect(networkCalls, 0);
      expect(timerCalls, 0);
      expect(microtaskCalls, 0);
      final configuration = observed.configuration;
      expect(observed.authority.profileId, 'operator.main');
      expect(
        observed.authority.serviceBaseUri,
        Uri.parse('https://authority.example/account/'),
      );
      expect(observed.authority.requestTimeout, const Duration(seconds: 15));
      expect(configuration.toJson(), _literalParticipant());
      expect(
        configuration.toString(),
        'SubmissionParticipantAuthenticationConfiguration',
      );
      expect(configuration.authority, isNot(same(configuration.authority)));
      expect(
        jsonEncode(configuration.toJson()),
        isNot(contains(RegExp('token|credential|session|userAccount|queue'))),
      );
    });

    test('roundtrip detaches inputs and every output while freezing IDs', () {
      // Given an ordered mutable operator list and an independent literal map.
      final supplied = ['server', 'second'];
      final literal = _literalParticipant(ids: ['server', 'second']);
      // When the public constructor/codec freeze input and wire copies mutate.
      final configuration = _configuration(ids: supplied);
      final restored =
          SubmissionParticipantAuthenticationConfiguration.fromJson(literal);
      supplied.clear();
      (literal['trustedConnectionIds']! as List).clear();
      final wire = configuration.toJson();
      (wire['trustedConnectionIds']! as List).clear();
      wire['authorityProfileId'] = 'changed';
      final frozenFailure = _capture(
        () => configuration.trustedConnectionIds.clear(),
      );
      // Then immutable values retain exact order and fresh detached encodings.
      expect(configuration.trustedConnectionIds, ['server', 'second']);
      expect(restored, configuration);
      expect(restored.toJson(), _literalParticipant(ids: ['server', 'second']));
      expect(configuration.toJson(), restored.toJson());
      expect(frozenFailure, isA<UnsupportedError>());
    });

    test(
      'equality and hashing include profile canonical base and ordered IDs',
      () {
        // Given equal values and one distinct value for each operator identity edge.
        final first = _configuration(ids: ['server', 'second']);
        final equivalent = _configuration(
          base: 'https://authority.example/account',
          ids: ['server', 'second'],
        );
        final changed = [
          _configuration(profile: 'operator.other', ids: ['server', 'second']),
          _configuration(
            base: 'https://other.example/account/',
            ids: ['server', 'second'],
          ),
          _configuration(ids: ['second', 'server']),
          _configuration(ids: ['server']),
          _configuration(ids: ['server', 'third']),
        ];
        // When values are compared and inserted into an ordinary value set.
        final equal = first == equivalent;
        final equalHash = first.hashCode == equivalent.hashCode;
        final distinct = changed.map((value) => first != value).toList();
        final values = {first, equivalent, ...changed};
        // Then equal canonical identity coalesces and every changed edge separates.
        expect(equal, isTrue);
        expect(equalHash, isTrue);
        expect(distinct, everyElement(isTrue));
        expect(values, hasLength(6));
        expect(first == Object(), isFalse);
      },
    );

    for (final raw in [
      'https://authority.example/account',
      'https://authority.example/account///',
    ]) {
      test('constructor canonicalizes but stored base refuses $raw', () {
        // Given an explicit raw base accepted by the existing profile parser.
        final retained = {..._literalParticipant(), 'authorityBaseUri': raw};
        // When construction canonicalizes and retained JSON is decoded once.
        final configuration = _configuration(base: raw);
        final failure = _capture(
          () => SubmissionParticipantAuthenticationConfiguration.fromJson(
            retained,
          ),
        );
        // Then raw operator input is usable but stored identity is not repaired.
        expect(
          configuration.authorityBaseUri,
          Uri.parse('https://authority.example/account/'),
        );
        _expectSafeFormat(failure);
      });
    }

    test('accepts 128 IDs and exactly 65536 encoded UTF8 bytes', () {
      // Given exact cardinality and byte limits, calculated from real encoding.
      final ids = [for (var index = 0; index < 128; index++) 'target_$index'];
      const prefix = 'https://authority.example/a';
      final baseline = _configuration(base: '$prefix/');
      final padding = 65536 - utf8.encode(jsonEncode(baseline.toJson())).length;
      final exactBase = '$prefix${'x' * padding}/';
      // When both boundary values are constructed and the exact body roundtrips.
      final maximumIds = _configuration(ids: ids);
      final exact = _configuration(base: exactBase);
      final restored =
          SubmissionParticipantAuthenticationConfiguration.fromJson(
            exact.toJson(),
          );
      final overflow = _capture(
        () => _configuration(base: '${prefix}x${'x' * padding}/'),
      );
      // Then the inclusive limits survive and one additional byte is rejected.
      expect(maximumIds.trustedConnectionIds, ids);
      expect(utf8.encode(jsonEncode(exact.toJson())), hasLength(65536));
      expect(restored, exact);
      _expectSafeArgument(overflow);
    });

    final invalidInputs =
        <({String name, String profile, String base, List<String> ids})>[
          for (final profile in [
            '',
            ' operator',
            'operator ',
            'PRIVATE_MARKER/',
            'x' * 129,
            'é',
          ])
            (
              name: 'profile ${profile.length} $profile',
              profile: profile,
              base: 'https://authority.example/account/',
              ids: ['server'],
            ),
          for (final base in [
            '',
            'PRIVATE_MARKER',
            '/relative/PRIVATE_MARKER',
            'https:///PRIVATE_MARKER',
            'https://user:PRIVATE_MARKER@authority.example/account/',
            'https://authority.example/account/?PRIVATE_MARKER',
            'https://authority.example/account/#PRIVATE_MARKER',
            'https://authority.example/a/../PRIVATE_MARKER',
            'https://authority.example/a/./PRIVATE_MARKER',
            'https://authority.example/%2e%2e/PRIVATE_MARKER',
            'https://authority.example/%2e/PRIVATE_MARKER',
            'https://authority.example/a%2fPRIVATE_MARKER/',
            'https://authority.example/a%5cPRIVATE_MARKER/',
            'https://authority.example/a\\PRIVATE_MARKER/',
            'https://authority.example/a%00PRIVATE_MARKER/',
            'https://authority.example/a%0dPRIVATE_MARKER/',
            'https://authority.example/a%7fPRIVATE_MARKER/',
            'https://authority.example/a\nPRIVATE_MARKER/',
            'http://localhost/PRIVATE_MARKER/',
            'http://127.0.0.1/PRIVATE_MARKER/',
            'http://192.168.1.2/PRIVATE_MARKER/',
            'http://public.example/PRIVATE_MARKER/',
            'ftp://authority.example/PRIVATE_MARKER/',
            'https://authority.example/${'é' * 12000}/',
          ])
            (
              name:
                  'base case ${base.length} ${base.length < 200 ? base : 'oversized UTF8'}',
              profile: 'operator.main',
              base: base,
              ids: ['server'],
            ),
          for (final ids in <List<String>>[
            [],
            ['server', 'server'],
            [''],
            [' target'],
            ['target '],
            ['PRIVATE_MARKER/target'],
            ['a.b'],
            ['-target'],
            ['é'],
            ['x' * 129],
            [for (var index = 0; index < 129; index++) 'target_$index'],
          ])
            (
              name:
                  'IDs ${ids.length} ${ids.length < 3 ? ids : 'over capacity'}',
              profile: 'operator.main',
              base: 'https://authority.example/account/',
              ids: ids,
            ),
        ];
    for (final input in invalidInputs) {
      test('rejects invalid ${input.name} without retaining values', () {
        // Given one invalid raw operator value in otherwise valid constructor input.
        final profile = input.profile;
        final base = input.base;
        final ids = input.ids;
        // When the real constructor validates the proposed declaration once.
        final failure = _capture(
          () => _configuration(profile: profile, base: base, ids: ids),
        );
        // Then one fixed ArgumentError retains no raw value or underlying cause.
        _expectSafeArgument(failure);
      });
    }

    final invalidParticipantJson = <String, Object?>{
      'null object': null,
      'list object': [],
      'scalar object': 'PRIVATE_MARKER',
      'nonstring key': {1: 'PRIVATE_MARKER'},
      'unknown version': {..._literalParticipant(), 'version': 2},
      'fractional version': {..._literalParticipant(), 'version': 1.0},
      'extra credential': {..._literalParticipant(), 'token': 'PRIVATE_MARKER'},
      for (final key in _literalParticipant().keys)
        'missing $key': {..._literalParticipant()}..remove(key),
      for (final key in _literalParticipant().keys)
        'null $key': {..._literalParticipant(), key: null},
      'wrong profile type': {
        ..._literalParticipant(),
        'authorityProfileId': true,
      },
      'wrong base type': {..._literalParticipant(), 'authorityBaseUri': []},
      'wrong IDs type': {
        ..._literalParticipant(),
        'trustedConnectionIds': 'server',
      },
      'wrong ID element': {
        ..._literalParticipant(),
        'trustedConnectionIds': [null],
      },
      'wrong numeric ID': {
        ..._literalParticipant(),
        'trustedConnectionIds': [1],
      },
      for (var index = 0; index < invalidInputs.length; index++)
        'invalid constructor value $index': {
          'version': 1,
          'authorityProfileId': invalidInputs[index].profile,
          'authorityBaseUri': invalidInputs[index].base,
          'trustedConnectionIds': invalidInputs[index].ids,
        },
    };
    for (final entry in invalidParticipantJson.entries) {
      test('closed DTO rejects ${entry.key}', () {
        // Given a corrupt retained value, never an instruction to repair identity.
        final retained = entry.value;
        // When the real closed DTO decoder processes that value exactly once.
        final failure = _capture(
          () => SubmissionParticipantAuthenticationConfiguration.fromJson(
            retained,
          ),
        );
        // Then a safe FormatException signals corruption without empty fallback.
        _expectSafeFormat(failure);
      });
    }
  });

  group('CORE-CONFIG-05 snapshot compatibility', () {
    test(
      'literal v1 and v2 retain targets selections references without adoption',
      () {
        // Given independent literal schemas used before participant configuration.
        final v2 = _literalSnapshot();
        final v1 = {..._literalSnapshot(), 'version': 1}
          ..remove('referenceAccessBindings');
        final expectedV1Projection = {
          ..._literalSnapshot(),
          'referenceAccessBindings': <String, Object?>{},
        };
        // When genuine snapshot decoding reads both historical versions.
        final old = SubmissionConfigurationSnapshot.fromJson(v1);
        final current = SubmissionConfigurationSnapshot.fromJson(v2);
        final constructed = SubmissionConfigurationSnapshot(
          driveConnections: current.driveConnections,
          httpConnections: current.httpConnections,
          selectedStorageConnectionId: 'drive',
          selectedTransportConnectionId: 'server',
          referenceAccessBindings: {
            'server': ['drive'],
            'second': <String>[],
          },
        );
        // Then the existing v2 shape/byte order survives and no HTTP target is adopted.
        expect(old.participantAuthentication, isNull);
        expect(current.participantAuthentication, isNull);
        expect(constructed.participantAuthentication, isNull);
        expect(old.toJson(), expectedV1Projection);
        expect(jsonEncode(current.toJson()), jsonEncode(v2));
        expect(jsonEncode(constructed.toJson()), jsonEncode(v2));
        expect(
          current.toJson().containsKey('participantAuthentication'),
          isFalse,
        );
        expect(old.referenceAccessBindings, isEmpty);
        expect(current.referenceAccessBindings, {
          'server': ['drive'],
          'second': <String>[],
        });
      },
    );

    test('v3 retains targets selections and independent reference declarations', () {
      // Given mutable literal v3 with one trusted target and another same-origin target.
      final literal = _literalV3();
      final suppliedIds = ['server'];
      final suppliedBindings = {
        'server': ['drive'],
        'second': <String>[],
      };
      final suppliedDrive = [_drive()];
      final suppliedHttp = [_http('server'), _http('second')];
      // When real snapshots freeze inputs and their detached wire maps mutate.
      final snapshot = SubmissionConfigurationSnapshot(
        driveConnections: suppliedDrive,
        httpConnections: suppliedHttp,
        selectedStorageConnectionId: 'drive',
        selectedTransportConnectionId: 'server',
        referenceAccessBindings: suppliedBindings,
        participantAuthentication: _configuration(ids: suppliedIds),
      );
      final restored = SubmissionConfigurationSnapshot.fromJson(literal);
      suppliedIds.clear();
      suppliedBindings['server']!.clear();
      suppliedBindings.clear();
      suppliedDrive.clear();
      suppliedHttp.clear();
      (literal['driveConnections']! as List).clear();
      (literal['httpConnections']! as List).clear();
      ((literal['participantAuthentication']! as Map)['trustedConnectionIds']
              as List)
          .clear();
      final wire = snapshot.toJson();
      (wire['driveConnections']! as List).clear();
      (wire['httpConnections']! as List).clear();
      ((wire['referenceAccessBindings']! as Map)['server'] as List).clear();
      ((wire['participantAuthentication']! as Map)['trustedConnectionIds']
              as List)
          .clear();
      final frozenFailure = _capture(
        () => snapshot.referenceAccessBindings['server']!.clear(),
      );
      // Then every accepted value survives, and resolver access adds no trusted ID.
      expect(snapshot.toJson(), _literalV3());
      expect(restored.toJson(), _literalV3());
      expect(snapshot.participantAuthentication!.trustedConnectionIds, [
        'server',
      ]);
      expect(snapshot.httpConnections.map((value) => value.id), [
        'server',
        'second',
      ]);
      expect(snapshot.referenceAccessBindings, {
        'server': ['drive'],
        'second': <String>[],
      });
      expect(snapshot.selectedStorageConnectionId, 'drive');
      expect(snapshot.selectedTransportConnectionId, 'server');
      expect(frozenFailure, isA<UnsupportedError>());
    });

    test(
      'participant mode does not require a selection or resolver access grant',
      () {
        // Given a registered bearer HTTP target with no selected target or reference map.
        final participant = _configuration();
        // When a full snapshot is constructed in explicit participant mode.
        final snapshot = SubmissionConfigurationSnapshot(
          driveConnections: [],
          httpConnections: [_http('server')],
          participantAuthentication: participant,
        );
        final restored = SubmissionConfigurationSnapshot.fromJson(
          snapshot.toJson(),
        );
        // Then the declaration survives independently of absent selection/reference access.
        expect(restored.participantAuthentication, participant);
        expect(restored.selectedTransportConnectionId, isNull);
        expect(restored.referenceAccessBindings, isEmpty);
        expect(restored.toJson()['version'], 3);
      },
    );

    final invalidTargets =
        <
          ({
            String name,
            List<String> trusted,
            List<HttpSubmissionConnection> http,
            String? selected,
          })
        >[
          (
            name: 'missing trusted target',
            trusted: ['missing'],
            http: [_http('server')],
            selected: null,
          ),
          (
            name: 'Drive kind',
            trusted: ['drive'],
            http: [_http('server')],
            selected: null,
          ),
          (
            name: 'anonymous target',
            trusted: ['server'],
            http: [_http('server', bearer: false)],
            selected: null,
          ),
          (
            name: 'untrusted same-origin selection',
            trusted: ['server'],
            http: [_http('server'), _http('second')],
            selected: 'second',
          ),
          (
            name: 'untrusted different-origin selection',
            trusted: ['server'],
            http: [
              _http('server'),
              _http('second', host: 'other.example'),
            ],
            selected: 'second',
          ),
          (
            name: 'one invalid target among valid IDs',
            trusted: ['server', 'missing'],
            http: [_http('server')],
            selected: 'server',
          ),
        ];
    for (final input in invalidTargets) {
      test('snapshot constructor rejects ${input.name} before publication', () {
        // Given explicit trust IDs inconsistent with exact registered target intent.
        final participant = _configuration(ids: input.trusted);
        // When the real snapshot constructor validates the complete proposed state.
        final failure = _capture(
          () => SubmissionConfigurationSnapshot(
            driveConnections: [_drive()],
            httpConnections: input.http,
            selectedTransportConnectionId: input.selected,
            referenceAccessBindings: {
              'server': ['drive'],
            },
            participantAuthentication: participant,
          ),
        );
        // Then no invalid snapshot is published and resolver access cannot authorize it.
        _expectSafeArgument(failure);
      });
      test(
        'v3 decoder rejects ${input.name} without replacing it with empty state',
        () {
          // Given a retained v3 body with invalid exact target membership or selection.
          final retained = {
            ..._literalV3(),
            'httpConnections': input.http
                .map((value) => value.toJson())
                .toList(),
            'selectedTransportConnectionId': input.selected,
            'referenceAccessBindings': {
              'server': ['drive'],
            },
            'participantAuthentication': _literalParticipant(
              ids: input.trusted,
            ),
          };
          // When the real snapshot codec validates this body once.
          final failure = _capture(
            () => SubmissionConfigurationSnapshot.fromJson(retained),
          );
          // Then the shared safe decoding convention reports corrupt persisted intent.
          _expectSafeFormat(failure);
        },
      );
    }

    final invalidSnapshots = <String, Map<String, Object?>>{
      'unknown version': {..._literalV3(), 'version': 4},
      'fractional version': {..._literalV3(), 'version': 3.0},
      'extra key': {..._literalV3(), 'token': 'PRIVATE_MARKER'},
      for (final key in _literalV3().keys)
        'missing $key': {..._literalV3()}..remove(key),
      for (final key in [
        'version',
        'driveConnections',
        'httpConnections',
        'referenceAccessBindings',
        'participantAuthentication',
      ])
        'null $key': {..._literalV3(), key: null},
      for (final key in _literalV3().keys)
        'wrong type $key': {..._literalV3(), key: true},
      'null Drive definition': {
        ..._literalV3(),
        'driveConnections': [null],
      },
      'null HTTP definition': {
        ..._literalV3(),
        'httpConnections': [null],
      },
      'corrupt Drive definition': {
        ..._literalV3(),
        'driveConnections': [
          {'token': 'PRIVATE_MARKER'},
        ],
      },
      'corrupt HTTP definition': {
        ..._literalV3(),
        'httpConnections': [
          {'token': 'PRIVATE_MARKER'},
        ],
      },
      'corrupt reference value': {
        ..._literalV3(),
        'referenceAccessBindings': {
          'server': [null],
        },
      },
      'unknown reference HTTP target': {
        ..._literalV3(),
        'referenceAccessBindings': {
          'missing': ['drive'],
        },
      },
      'unknown reference Drive target': {
        ..._literalV3(),
        'referenceAccessBindings': {
          'server': ['missing'],
        },
      },
      'unknown storage selection': {
        ..._literalV3(),
        'selectedStorageConnectionId': 'missing',
      },
      'unknown transport selection': {
        ..._literalV3(),
        'selectedTransportConnectionId': 'missing',
      },
      'wrong-kind storage selection': {
        ..._literalV3(),
        'selectedStorageConnectionId': 'server',
      },
      'wrong-kind transport selection': {
        ..._literalV3(),
        'selectedTransportConnectionId': 'drive',
      },
      for (final key in _literalParticipant().keys)
        'participant missing $key': {
          ..._literalV3(),
          'participantAuthentication': {..._literalParticipant()}..remove(key),
        },
      for (final key in _literalParticipant().keys)
        'participant null $key': {
          ..._literalV3(),
          'participantAuthentication': {..._literalParticipant(), key: null},
        },
      for (final key in _literalParticipant().keys)
        'participant wrong type $key': {
          ..._literalV3(),
          'participantAuthentication': {..._literalParticipant(), key: true},
        },
      'participant unknown version': {
        ..._literalV3(),
        'participantAuthentication': {..._literalParticipant(), 'version': 2},
      },
      'participant extra key': {
        ..._literalV3(),
        'participantAuthentication': {
          ..._literalParticipant(),
          'session': 'PRIVATE_MARKER',
        },
      },
      'participant noncanonical base': {
        ..._literalV3(),
        'participantAuthentication': {
          ..._literalParticipant(),
          'authorityBaseUri': 'https://authority.example/account',
        },
      },
      'participant invalid profile': {
        ..._literalV3(),
        'participantAuthentication': {
          ..._literalParticipant(),
          'authorityProfileId': 'PRIVATE_MARKER/',
        },
      },
      'participant development HTTP': {
        ..._literalV3(),
        'participantAuthentication': {
          ..._literalParticipant(),
          'authorityBaseUri': 'http://localhost/account/',
        },
      },
      'v2 forbids participant key': {..._literalV3(), 'version': 2},
      'v1 forbids participant key': {..._literalV3(), 'version': 1}
        ..remove('referenceAccessBindings'),
    };
    for (final entry in invalidSnapshots.entries) {
      test('closed snapshot rejects ${entry.key}', () {
        // Given one corrupt closed snapshot without fallback state or credentials.
        final retained = entry.value;
        // When the real snapshot decoder reads the retained value once.
        final failure = _capture(
          () => SubmissionConfigurationSnapshot.fromJson(retained),
        );
        // Then safe corruption reporting preserves the distinction from an absent store.
        _expectSafeFormat(failure);
      });
    }

    test(
      'existing base store implementer needs no participant setter',
      () async {
        // Given a base-only external-style implementer with its original interface.
        final implementation = _LegacyConfigurationStore();
        final SubmissionConfigurationStore store = implementation;
        // When a generic caller reads and retires that unchanged base contract.
        final snapshot = await store.snapshot();
        await store.close();
        // Then legacy state remains usable without claiming the optional capability.
        expect(snapshot.toJson(), _literalSnapshot());
        expect(snapshot.participantAuthentication, isNull);
        expect(store, isNot(isA<SubmissionParticipantConfigurationStore>()));
        expect(implementation.reads, 1);
        expect(implementation.closed, isTrue);
      },
    );
  });
}

SubmissionParticipantAuthenticationConfiguration _configuration({
  String profile = 'operator.main',
  String base = 'https://authority.example/account/',
  List<String> ids = const ['server'],
}) => SubmissionParticipantAuthenticationConfiguration(
  authorityProfileId: profile,
  authorityBaseUri: base,
  trustedConnectionIds: ids,
);

Map<String, Object?> _literalParticipant({
  List<String> ids = const ['server'],
}) => {
  'version': 1,
  'authorityProfileId': 'operator.main',
  'authorityBaseUri': 'https://authority.example/account/',
  'trustedConnectionIds': ids.toList(),
};

Map<String, Object?> _literalSnapshot() => {
  'version': 2,
  'driveConnections': [
    {
      'version': 1,
      'type': 'googleDrive',
      'id': 'drive',
      'accountId': 'owner@example.test',
      'folderId': 'Folder',
    },
  ],
  'httpConnections': [
    {
      'version': 1,
      'type': 'http',
      'id': 'server',
      'endpoint': 'https://recipient.example/submit',
      'requiresBearerToken': true,
    },
    {
      'version': 1,
      'type': 'http',
      'id': 'second',
      'endpoint': 'https://recipient.example/submit',
      'requiresBearerToken': true,
    },
  ],
  'selectedStorageConnectionId': 'drive',
  'selectedTransportConnectionId': 'server',
  'referenceAccessBindings': {
    'server': ['drive'],
    'second': <String>[],
  },
};

Map<String, Object?> _literalV3() => {
  ..._literalSnapshot(),
  'version': 3,
  'participantAuthentication': _literalParticipant(),
};

DriveSubmissionConnection _drive() => DriveSubmissionConnection(
  id: 'drive',
  accountId: 'owner@example.test',
  folderId: 'Folder',
);

HttpSubmissionConnection _http(
  String id, {
  bool bearer = true,
  String host = 'recipient.example',
}) => HttpSubmissionConnection(
  id: id,
  endpoint: Uri.parse('https://$host/submit'),
  requiresBearerToken: bearer,
);

Object? _capture(void Function() operation) {
  try {
    operation();
    return null;
  } catch (error) {
    return error;
  }
}

void _expectSafeArgument(Object? failure) {
  expect(failure, isA<ArgumentError>());
  final error = failure! as ArgumentError;
  expect(error.message, 'Invalid participant submission configuration');
  expect(error.name, isNull);
  expect(error.invalidValue, isNull);
  expect(error.toString(), isNot(contains('PRIVATE_MARKER')));
}

void _expectSafeFormat(Object? failure) {
  expect(failure, isA<FormatException>());
  final error = failure! as FormatException;
  expect(error.source, isNull);
  expect(error.offset, isNull);
  expect(
    error.message,
    isIn([
      'Expected a string-keyed object',
      'Invalid submission schema keys',
      'Unsupported submission version',
      'Unsupported configuration version',
      'Expected integer',
      'Expected string',
      'Expected array',
      'Expected boolean',
      'Invalid connection type',
      'Invalid HTTP connection',
      'Invalid submission value',
      'Invalid submission authority identity',
    ]),
  );
  expect(error.toString(), isNot(contains('PRIVATE_MARKER')));
}

/// Deliberately implements only the original public base interface.
final class _LegacyConfigurationStore implements SubmissionConfigurationStore {
  var reads = 0;
  var closed = false;

  @override
  Future<SubmissionConfigurationSnapshot> snapshot() async {
    reads++;
    return SubmissionConfigurationSnapshot.fromJson(_literalSnapshot());
  }

  @override
  Future<void> putDrive(DriveSubmissionConnection connection) =>
      throw UnsupportedError('Unused base port');

  @override
  Future<void> putHttp(HttpSubmissionConnection connection) =>
      throw UnsupportedError('Unused base port');

  @override
  Future<void> select({
    String? storageConnectionId,
    String? transportConnectionId,
  }) => throw UnsupportedError('Unused base port');

  @override
  Future<void> setReferenceAccess({
    required String transportConnectionId,
    required List<String> storageConnectionIds,
  }) => throw UnsupportedError('Unused base port');

  @override
  Future<void> close() async {
    closed = true;
  }
}
