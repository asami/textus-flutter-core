import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('submission immutable request v1 and record v2 values', () {
    test(
      'M1 deep snapshots, exact roundtrip, UTC and immutable collections',
      () {
        // Given mutable nested consumer context and provider checkpoint data.
        final nested = <String, Object?>{
          'values': <Object?>[
            null,
            {'text': '  原文\n '},
          ],
        };
        final original = CaptureMaterialReference(
          id: 'original',
          mediaType: 'audio/wav',
          byteLength: 8,
          capturedAt: DateTime.parse('2026-10-10T10:00:00+09:00'),
          originalName: 'voice.wav',
          extensions: nested,
        );
        final material = SubmissionMaterial(
          key: 'audio',
          original: original,
          provenance: nested,
        );
        final materialList = [material];
        final request = _request(
          materials: materialList,
          document: nested,
          payload: nested,
          extensions: nested,
        );
        final reservation = SubmissionStorageReservation(
          key: 'audio',
          providerId: 'driveProvider',
          data: nested,
        );
        final receipt = SubmissionMaterialReceipt(
          key: 'audio',
          providerId: 'driveProvider',
          remoteId: 'remote/description',
          accessConnectionId: 'drive',
          storedAt: _at,
          metadata: nested,
        );
        final acknowledgement = SubmissionAcknowledgement(
          requestId: request.id,
          subjectId: request.subjectId,
          serverId: 'server/description',
          receivedAt: _at,
          extensions: nested,
        );
        final failure = _failure();
        final reservations = {'audio': reservation};
        final receipts = {'audio': receipt};
        final history = [failure];
        final record = SubmissionRecord(
          request: request,
          state: SubmissionState.submitted,
          claimCount: 2,
          updatedAt: _at,
          reservations: reservations,
          receipts: receipts,
          failureHistory: history,
          acknowledgement: acknowledgement,
        );
        final packet = SubmissionPacket(request: request, receipts: receipts);

        // When all mutable inputs and detached encoded JSON are changed afterwards.
        (nested['values']! as List).add('changed');
        materialList.clear();
        reservations.clear();
        receipts.clear();
        history.clear();
        final detached = SubmissionCodec.requestToJson(request);
        (detached['document']! as Map)['changed'] = true;
        final pairs = <(Object, Object)>[
          (
            request,
            SubmissionCodec.requestFromJson(
              _wire(SubmissionCodec.requestToJson(request)),
            ),
          ),
          (
            material,
            SubmissionCodec.materialFromJson(
              _wire(SubmissionCodec.materialToJson(material)),
            ),
          ),
          (
            reservation,
            SubmissionCodec.reservationFromJson(
              _wire(SubmissionCodec.reservationToJson(reservation)),
            ),
          ),
          (
            receipt,
            SubmissionCodec.receiptFromJson(
              _wire(SubmissionCodec.receiptToJson(receipt)),
            ),
          ),
          (
            acknowledgement,
            SubmissionCodec.acknowledgementFromJson(
              _wire(SubmissionCodec.acknowledgementToJson(acknowledgement)),
            ),
          ),
          (
            failure,
            SubmissionCodec.failureFromJson(
              _wire(SubmissionCodec.failureToJson(failure)),
            ),
          ),
          (
            record,
            SubmissionCodec.recordFromJson(
              _wire(SubmissionCodec.recordToJson(record)),
            ),
          ),
        ];

        // Then every value roundtrips deeply, hashes equally, and owns frozen data.
        for (final pair in pairs) {
          expect(pair.$2, pair.$1);
          expect(pair.$2.hashCode, pair.$1.hashCode);
        }
        for (final map in [
          original.extensions,
          material.provenance,
          request.document,
          request.payload,
          request.extensions,
          reservation.data,
          receipt.metadata,
          acknowledgement.extensions,
        ]) {
          expect((map['values']! as List).length, 2);
          expect(() => map['other'] = true, throwsUnsupportedError);
          expect(() => (map['values']! as List).add(1), throwsUnsupportedError);
          expect(
            () => ((map['values']! as List)[1] as Map)['text'] = 'edited',
            throwsUnsupportedError,
          );
        }
        expect(() => request.materials.clear(), throwsUnsupportedError);
        expect(() => record.reservations.clear(), throwsUnsupportedError);
        expect(() => record.receipts.clear(), throwsUnsupportedError);
        expect(() => record.failureHistory.clear(), throwsUnsupportedError);
        expect(() => packet.receipts.clear(), throwsUnsupportedError);
        expect(record.lastFailure, isNull);
        expect(request.createdAt.isUtc, isTrue);
        expect(original.capturedAt, _at);
        final packetJson = SubmissionCodec.packetToJson(packet);
        expect(packetJson.keys.toSet(), {
          'version',
          'requestId',
          'kind',
          'subjectId',
          'createdAt',
          'payload',
          'extensions',
          'materials',
        });
        expect(packetJson.containsKey('document'), isFalse);
        expect(packetJson['payload'], request.payload);
        expect((packetJson['materials'] as List).single, {
          ...SubmissionCodec.materialToJson(material),
          'receipt': SubmissionCodec.receiptToJson(receipt),
        });
        expect(SubmissionCodec.recordToJson(record).keys.toSet(), {
          'version',
          'request',
          'state',
          'claimCount',
          'updatedAt',
          'leaseToken',
          'leaseExpiresAt',
          'nextAttemptAt',
          'reservations',
          'receipts',
          'failureHistory',
          'acknowledgement',
          'transportCheckpoint',
        });
        expect(
          SubmissionCodec.requestFromJson({
            ...SubmissionCodec.requestToJson(request),
            'createdAt': '2026-10-10T10:00:00+09:00',
          }),
          request,
        );
      },
    );

    test('M1 every field participates in ordinary value equality', () {
      // Given valid models and independent one-field wire alterations.
      final request = _request();
      final material = request.materials.single;
      final reservation = _reservation();
      final receipt = _receipt();
      final ack = _ack();
      final failure = _failure();
      final cases =
          <
            (
              Object,
              Map<String, Object?>,
              Object Function(Map<String, Object?>),
              Map<String, Object?>,
            )
          >[
            (
              request,
              SubmissionCodec.requestToJson(request),
              SubmissionCodec.requestFromJson,
              {
                'id': 'different',
                'kind': 'otherKind',
                'subjectId': 'otherSubject',
                'createdAt': _later.toIso8601String(),
                'document': {'edited': 1},
                'payload': {'edited': 2},
                'materials': [
                  SubmissionCodec.materialToJson(
                    SubmissionMaterial(
                      key: 'different',
                      original: material.original,
                    ),
                  ),
                ],
                'transportConnectionId': 'otherServer',
                'storageConnectionId': 'otherDrive',
                'extensions': {'edited': 3},
              },
            ),
            (
              material,
              SubmissionCodec.materialToJson(material),
              SubmissionCodec.materialFromJson,
              {
                'key': 'other',
                'original': {
                  ...material.original.toJson(),
                  'id': 'otherOriginal',
                },
                'provenance': {'edited': 1},
              },
            ),
            (
              reservation,
              SubmissionCodec.reservationToJson(reservation),
              SubmissionCodec.reservationFromJson,
              {
                'key': 'other',
                'providerId': 'otherProvider',
                'data': {'edited': true},
              },
            ),
            (
              receipt,
              SubmissionCodec.receiptToJson(receipt),
              SubmissionCodec.receiptFromJson,
              {
                'key': 'other',
                'providerId': 'otherProvider',
                'remoteId': 'other remote',
                'accessConnectionId': 'otherDrive',
                'storedAt': _later.toIso8601String(),
                'metadata': {'edited': true},
              },
            ),
            (
              ack,
              SubmissionCodec.acknowledgementToJson(ack),
              SubmissionCodec.acknowledgementFromJson,
              {
                'requestId': 'other',
                'subjectId': 'otherSubject',
                'serverId': 'other server',
                'receivedAt': _later.toIso8601String(),
                'extensions': {'edited': true},
              },
            ),
            (
              failure,
              SubmissionCodec.failureToJson(failure),
              SubmissionCodec.failureFromJson,
              {
                'stage': 'transport',
                'code': 'otherCode',
                'message': 'Other safe message',
                'retryable': false,
                'occurredAt': _later.toIso8601String(),
                'claimCount': 2,
              },
            ),
          ];
      // When each constructor field is changed via its strict public decoder.
      for (final item in cases) {
        for (final change in item.$4.entries) {
          final changed = item.$3({...item.$2, change.key: change.value});
          // Then equality distinguishes the altered value without identity hashes.
          expect(changed, isNot(item.$1), reason: change.key);
        }
      }
      // Given a fully checkpointed current lease and its preceding failure history.
      final record = SubmissionRecord(
        request: request,
        state: SubmissionState.submitting,
        claimCount: 2,
        updatedAt: _at,
        leaseToken: 'lease1',
        leaseExpiresAt: _later,
        reservations: {'audio': reservation},
        receipts: {'audio': receipt},
        failureHistory: [failure],
      );
      final wire = SubmissionCodec.recordToJson(record);
      // When every remaining record field varies within a valid state combination.
      final altered = <Map<String, Object?>>[
        {
          ...wire,
          'request': {
            ...SubmissionCodec.requestToJson(request),
            'payload': {'other': true},
          },
        },
        {
          ...wire,
          'state': 'readyToSubmit',
          'leaseToken': null,
          'leaseExpiresAt': null,
        },
        {...wire, 'claimCount': 3},
        {...wire, 'updatedAt': _later.toIso8601String()},
        {...wire, 'leaseToken': 'lease2'},
        {
          ...wire,
          'leaseExpiresAt': _later
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
        {
          ...wire,
          'reservations': {
            'audio': {
              ...SubmissionCodec.reservationToJson(reservation),
              'data': {'new': 1},
            },
          },
        },
        {
          ...wire,
          'receipts': {
            'audio': {
              ...SubmissionCodec.receiptToJson(receipt),
              'remoteId': 'other',
            },
          },
        },
        {...wire, 'failureHistory': []},
        {
          ...wire,
          'state': 'submissionFailed',
          'leaseToken': null,
          'leaseExpiresAt': null,
          'failureHistory': [
            {...SubmissionCodec.failureToJson(failure), 'claimCount': 2},
          ],
          'nextAttemptAt': _later.toIso8601String(),
        },
        {
          ...wire,
          'state': 'submitted',
          'leaseToken': null,
          'leaseExpiresAt': null,
          'acknowledgement': SubmissionCodec.acknowledgementToJson(ack),
        },
      ];
      // Then valid variations remain unequal, including acknowledgement/retry time.
      for (final value in altered) {
        expect(SubmissionCodec.recordFromJson(value), isNot(record));
      }
      final failed = SubmissionCodec.recordFromJson(altered[9]);
      expect(failed.lastFailure, failed.failureHistory.last);
      expect(
        SubmissionCodec.recordFromJson({
          ...altered[9],
          'nextAttemptAt': _later
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        }),
        isNot(failed),
      );
      final submitted = SubmissionCodec.recordFromJson(altered[10]);
      expect(
        SubmissionCodec.recordFromJson({
          ...altered[10],
          'acknowledgement': {
            ...SubmissionCodec.acknowledgementToJson(ack),
            'serverId': 'another server',
          },
        }),
        isNot(submitted),
      );
      // Given safe wake notices and the same immutable durable record.
      final notice = SubmissionSchedulingFailure(
        code: 'wakeUnavailable',
        message: 'Safe notice',
      );
      final sameNotice = SubmissionSchedulingFailure(
        code: 'wakeUnavailable',
        message: 'Safe notice',
      );
      final commit = SubmissionCommitResult(
        record: submitted,
        schedulingFailure: notice,
      );
      final run = SubmissionRunResult(
        outcome: SubmissionRunOutcome.submitted,
        record: submitted,
      );
      // When result values are constructed independently or one field changes.
      final sameCommit = SubmissionCommitResult(
        record: submitted,
        schedulingFailure: sameNotice,
      );
      final sameRun = SubmissionRunResult(
        outcome: SubmissionRunOutcome.submitted,
        record: submitted,
      );
      // Then every result/notice field uses ordinary equality and hashing.
      expect(notice, sameNotice);
      expect(notice.hashCode, sameNotice.hashCode);
      expect(
        notice,
        isNot(
          SubmissionSchedulingFailure(code: 'other', message: 'Safe notice'),
        ),
      );
      expect(
        notice,
        isNot(
          SubmissionSchedulingFailure(
            code: 'wakeUnavailable',
            message: 'Other notice',
          ),
        ),
      );
      expect(commit, sameCommit);
      expect(commit.hashCode, sameCommit.hashCode);
      expect(commit, isNot(SubmissionCommitResult(record: submitted)));
      expect(
        commit,
        isNot(
          SubmissionCommitResult(record: record, schedulingFailure: notice),
        ),
      );
      expect(run, sameRun);
      expect(run.hashCode, sameRun.hashCode);
      expect(
        run,
        isNot(
          SubmissionRunResult(
            outcome: SubmissionRunOutcome.progress,
            record: submitted,
          ),
        ),
      );
      expect(
        run,
        isNot(
          const SubmissionRunResult(outcome: SubmissionRunOutcome.submitted),
        ),
      );
      expect(
        SubmissionPacket(request: request, receipts: {'audio': receipt}),
        SubmissionPacket(request: request, receipts: {'audio': receipt}),
      );
      expect(
        SubmissionPacket(
          request: request,
          receipts: {'audio': receipt},
        ).hashCode,
        SubmissionPacket(
          request: request,
          receipts: {'audio': receipt},
        ).hashCode,
      );
      expect(
        SubmissionPacket(request: request, receipts: {'audio': receipt}),
        isNot(
          SubmissionPacket(
            request: SubmissionCodec.requestFromJson({
              ...SubmissionCodec.requestToJson(request),
              'payload': {'other': true},
            }),
            receipts: {'audio': receipt},
          ),
        ),
      );
      expect(
        SubmissionPacket(request: request, receipts: {'audio': receipt}),
        isNot(
          SubmissionPacket(
            request: request,
            receipts: {
              'audio': SubmissionCodec.receiptFromJson({
                ...SubmissionCodec.receiptToJson(receipt),
                'remoteId': 'other',
              }),
            },
          ),
        ),
      );
    });

    test('M2 rejects unsafe identities, duplicate keys and invalid JSON', () {
      // Given unsafe logical ids and malformed/cyclic/nonfinite JSON containers.
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      final badJson = <Map<String, Object?>>[
        cyclic,
        {'n': double.nan},
        {'n': double.infinity},
        {'v': Object()},
        {
          'v': <int, Object?>{1: 'bad key'},
        },
      ];
      final material = _request().materials.single;
      // When public constructors receive each invalid form.
      final constructors = <void Function()>[
        for (final id in ['', ' ', '../bad', 'path/name', 'a.b'])
          () => _request(id: id),
        () => _request(materials: [material, material]),
        () => _request(storage: null),
        () => _request(materials: [], storage: 'drive'),
        for (final json in badJson) () => _request(payload: json),
        for (final json in badJson)
          () => SubmissionMaterial(
            key: 'audio',
            original: material.original,
            provenance: json,
          ),
        for (final json in badJson)
          () => SubmissionStorageReservation(
            key: 'audio',
            providerId: 'provider',
            data: json,
          ),
        () => SubmissionMaterialReceipt(
          key: 'audio',
          providerId: '../bad',
          remoteId: 'x',
          accessConnectionId: 'drive',
          storedAt: _at,
        ),
        () => SubmissionAcknowledgement(
          requestId: 'commit1',
          subjectId: 'subject1',
          serverId: ' ',
          receivedAt: _at,
        ),
        () => SubmissionPacket(request: _request(), receipts: {}),
      ];
      // Then constructors reject unsafe intent without changing original schema.
      for (final action in constructors) {
        expect(action, throwsArgumentError);
      }
      final empty = _request(
        materials: [],
        storage: null,
        extensions: {'armId': 'opaque/unknown arm', 'title': null},
      );
      expect(empty.materials, isEmpty);
      expect(
        SubmissionCodec.requestFromJson(SubmissionCodec.requestToJson(empty)),
        empty,
      );
    });

    test('M2 exact keys, scalar/calendar/version and state relationships', () {
      // Given complete request v1/record v2 JSON and nested model decoders.
      final request = _request();
      final ready = SubmissionRecord(
        request: request,
        state: SubmissionState.readyToSubmit,
        claimCount: 0,
        updatedAt: _at,
      );
      final json = SubmissionCodec.requestToJson(request);
      final record = SubmissionCodec.recordToJson(ready);
      final decoders =
          <(Map<String, Object?>, Object Function(Map<String, Object?>))>[
            (json, SubmissionCodec.requestFromJson),
            (record, SubmissionCodec.recordFromJson),
            (
              SubmissionCodec.materialToJson(request.materials.single),
              SubmissionCodec.materialFromJson,
            ),
            (
              SubmissionCodec.reservationToJson(_reservation()),
              SubmissionCodec.reservationFromJson,
            ),
            (
              SubmissionCodec.receiptToJson(_receipt()),
              SubmissionCodec.receiptFromJson,
            ),
            (
              SubmissionCodec.acknowledgementToJson(_ack()),
              SubmissionCodec.acknowledgementFromJson,
            ),
            (
              SubmissionCodec.failureToJson(_failure()),
              SubmissionCodec.failureFromJson,
            ),
          ];
      // When any exact-schema key is omitted or an unknown key is inserted.
      for (final pair in decoders) {
        for (final key in pair.$1.keys) {
          final missing = {...pair.$1}..remove(key);
          // Then every missing key, including nullable keys, fails observably.
          expect(() => pair.$2(missing), throwsFormatException, reason: key);
        }
        expect(
          () => pair.$2({...pair.$1, 'unknown': true}),
          throwsFormatException,
        );
      }
      // Given malformed scalar/time values and contradictory lifecycle fields.
      final invalidRequests = <Map<String, Object?>>[
        {...json, 'version': 2},
        {...json, 'version': 1.0},
        {...json, 'id': 1},
        {...json, 'id': '../unsafe'},
        {...json, 'materials': {}},
        {
          ...json,
          'materials': [
            json['materials'] is List
                ? (json['materials'] as List).single
                : null,
            (json['materials'] as List).single,
          ],
        },
        {
          ...json,
          'payload': {'number': double.nan},
        },
        {...json, 'document': null},
        for (final date in [
          '2026-02-31T01:00:00Z',
          '2026-10-10T25:00:00Z',
          '2026-10-10T01:00:00',
          '2026-10-10T01:00:00+24:00',
          'bad',
        ])
          {...json, 'createdAt': date},
      ];
      final invalidRecords = <Map<String, Object?>>[
        {...record, 'version': 0},
        {...record, 'state': 'unknown'},
        {...record, 'claimCount': 1.0},
        {...record, 'claimCount': -1},
        {...record, 'leaseToken': 'lease'},
        {...record, 'leaseExpiresAt': _later.toIso8601String()},
        {...record, 'nextAttemptAt': _later.toIso8601String()},
        {...record, 'state': 'submitting', 'claimCount': 1},
        {...record, 'state': 'submissionFailed', 'claimCount': 1},
        {
          ...record,
          'state': 'submitted',
          'claimCount': 1,
          'acknowledgement': SubmissionCodec.acknowledgementToJson(_ack()),
        },
        {
          ...record,
          'reservations': {
            'unknown': SubmissionCodec.reservationToJson(_reservation()),
          },
        },
        {
          ...record,
          'receipts': {'audio': SubmissionCodec.receiptToJson(_receipt())},
        },
        {
          ...record,
          'acknowledgement': SubmissionCodec.acknowledgementToJson(_ack()),
        },
        {
          ...record,
          'failureHistory': [SubmissionCodec.failureToJson(_failure())],
        },
      ];
      // When strict decoders read the malformed persistence values.
      for (final value in invalidRequests) {
        // Then invalid scalars, times, duplicate keys and nested JSON are refused.
        expect(
          () => SubmissionCodec.requestFromJson(value),
          throwsFormatException,
        );
      }
      for (final value in invalidRecords) {
        expect(
          () => SubmissionCodec.recordFromJson(value),
          throwsFormatException,
        );
      }
      expect(
        () => SubmissionCodec.failureFromJson({
          ...SubmissionCodec.failureToJson(_failure()),
          'retryable': 'true',
        }),
        throwsFormatException,
      );
      expect(
        () => SubmissionCodec.receiptFromJson({
          ...SubmissionCodec.receiptToJson(_receipt()),
          'remoteId': ' ',
        }),
        throwsFormatException,
      );
      expect(
        () => SubmissionCodec.failureFromJson({
          ...SubmissionCodec.failureToJson(_failure()),
          'claimCount': 0,
        }),
        throwsFormatException,
      );

      // Given a valid complete submitted record and a retryable failed record.
      final submitted = SubmissionCodec.recordToJson(
        SubmissionRecord(
          request: request,
          state: SubmissionState.submitted,
          claimCount: 1,
          updatedAt: _at,
          reservations: {'audio': _reservation()},
          receipts: {'audio': _receipt()},
          acknowledgement: _ack(),
        ),
      );
      final failed = SubmissionCodec.recordToJson(
        SubmissionRecord(
          request: request,
          state: SubmissionState.submissionFailed,
          claimCount: 1,
          updatedAt: _at,
          failureHistory: [_failure()],
          nextAttemptAt: _later,
        ),
      );
      // When acknowledgement/provider/history/lease/retry relationships are corrupted.
      final contradictory = <Map<String, Object?>>[
        {
          ...submitted,
          'acknowledgement': {
            ...SubmissionCodec.acknowledgementToJson(_ack()),
            'requestId': 'wrong',
          },
        },
        {
          ...submitted,
          'acknowledgement': {
            ...SubmissionCodec.acknowledgementToJson(_ack()),
            'subjectId': 'wrong',
          },
        },
        {
          ...submitted,
          'leaseToken': 'unexpected',
          'leaseExpiresAt': _later.toIso8601String(),
        },
        {
          ...submitted,
          'receipts': {
            'audio': {
              ...SubmissionCodec.receiptToJson(_receipt()),
              'providerId': 'wrongProvider',
            },
          },
        },
        {
          ...submitted,
          'receipts': {
            'audio': {
              ...SubmissionCodec.receiptToJson(_receipt()),
              'key': 'wrongKey',
            },
          },
        },
        {...failed, 'nextAttemptAt': null},
        {...failed, 'nextAttemptAt': _at.toIso8601String()},
        {
          ...failed,
          'failureHistory': [
            {...SubmissionCodec.failureToJson(_failure()), 'retryable': false},
          ],
        },
        {
          ...failed,
          'failureHistory': [
            SubmissionCodec.failureToJson(_failure()),
            SubmissionCodec.failureToJson(_failure()),
          ],
        },
        {
          ...failed,
          'failureHistory': [
            {...SubmissionCodec.failureToJson(_failure()), 'claimCount': 2},
          ],
        },
        {
          ...record,
          'state': 'submitting',
          'claimCount': 1,
          'leaseToken': 'owner',
          'leaseExpiresAt': null,
        },
        {
          ...record,
          'state': 'submitting',
          'claimCount': 0,
          'leaseToken': 'owner',
          'leaseExpiresAt': _later.toIso8601String(),
        },
      ];
      // Then complete decoders refuse every inconsistent persisted relationship.
      for (final value in contradictory) {
        expect(
          () => SubmissionCodec.recordFromJson(value),
          throwsFormatException,
        );
      }
    });
  });
}

final _at = DateTime.utc(2026, 10, 10, 1);
final _later = _at.add(const Duration(minutes: 5));

SubmissionRequest _request({
  String id = 'commit1',
  List<SubmissionMaterial>? materials,
  String? storage = 'drive',
  Map<String, Object?> document = const {},
  Map<String, Object?> payload = const {},
  Map<String, Object?> extensions = const {},
}) {
  // Given immutable original reference defaults or explicit mutable test inputs.
  final actual =
      materials ??
      [
        SubmissionMaterial(
          key: 'audio',
          original: CaptureMaterialReference(
            id: 'original',
            mediaType: 'audio/wav',
            byteLength: 8,
            capturedAt: _at,
          ),
        ),
      ];
  // When the public constructor snapshots every consumer field.
  final request = SubmissionRequest(
    id: id,
    kind: 'bookMaterial',
    subjectId: 'subject1',
    createdAt: _at,
    document: document,
    payload: payload,
    materials: actual,
    transportConnectionId: 'server',
    storageConnectionId: storage,
    extensions: extensions,
  );
  // Then callers receive the actual value whose behavior is asserted above.
  return request;
}

SubmissionStorageReservation _reservation() {
  // Given a safe material/provider pair and opaque provider data.
  final data = <String, Object?>{'file': 'remote'};
  // When the public reservation constructor snapshots that data.
  final reservation = SubmissionStorageReservation(
    key: 'audio',
    providerId: 'driveProvider',
    data: data,
  );
  // Then callers assert the actual immutable value and its wire representation.
  return reservation;
}

SubmissionMaterialReceipt _receipt() {
  // Given a descriptive remote id and a UTC acknowledgement time.
  const remoteId = 'remote';
  // When the public receipt is created independently of server acceptance.
  final receipt = SubmissionMaterialReceipt(
    key: 'audio',
    providerId: 'driveProvider',
    remoteId: remoteId,
    accessConnectionId: 'drive',
    storedAt: _at,
  );
  // Then callers can assert receipt values without implying Submitted state.
  return receipt;
}

SubmissionAcknowledgement _ack() {
  // Given an immutable request/subject pair and descriptive fake server identity.
  const serverId = 'serverIdentity';
  // When explicit acceptance is constructed through the public API.
  final acknowledgement = SubmissionAcknowledgement(
    requestId: 'commit1',
    subjectId: 'subject1',
    serverId: serverId,
    receivedAt: _at,
  );
  // Then record/codec assertions can check the matching identity relationships.
  return acknowledgement;
}

SubmissionFailure _failure() {
  // Given a safe retryable storage failure in the first executing claim.
  const count = 1;
  // When the public value records its exact stage/time/count.
  final failure = SubmissionFailure(
    stage: SubmissionFailureStage.storage,
    code: 'temporarilyUnavailable',
    message: 'Safe storage failure',
    retryable: true,
    occurredAt: _at,
    claimCount: count,
  );
  // Then tests can assert immutable historical failure semantics after retry.
  return failure;
}

Map<String, Object?> _wire(Map<String, Object?> value) {
  // Given encoded public wire JSON.
  final encoded = jsonEncode(value);
  // When JSON crosses a serialization boundary independently of the model.
  final decoded = Map<String, Object?>.from(jsonDecode(encoded) as Map);
  // Then roundtrip assertions exercise a detached persisted representation.
  return decoded;
}
