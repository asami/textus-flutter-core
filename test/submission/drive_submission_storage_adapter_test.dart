import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_http_fixture.dart';

void main() {
  late SubmissionHttpFixture fixture;
  setUp(() {
    // Given independently owned credentials and a controlled HTTP client.
    fixture = SubmissionHttpFixture();
    // When constructing the public storage adapter without invoking operations.
    fixture.drive();
    // Then neither token retrieval nor IO occurs during construction.
    expect(fixture.client.requests, isEmpty);
    expect(fixture.credentials.calls, isEmpty);
  });
  tearDown(() {
    // Given every test's held operations have been released by local finally.
    final client = fixture.client;
    // When the fixture owner closes its client.
    fixture.dispose();
    // Then only test teardown has closed the borrowed port.
    expect(client.closed, isTrue);
  });

  group('HB3 persisted preparation and direct-call binding', () {
    test('exact generateIds reserves immutable identity without upload', () async {
      // Given an immutable original and an explicit Google generated-id response.
      final request = fixture.request();
      fixture.client.handler = (captured) {
        // Given the actual request dispatched by the concrete Drive adapter.
        expect(captured.method, 'GET');
        expect(
          captured.uri,
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/generateIds?count=1&space=drive&type=files',
          ),
        );
        expect(captured.followsRedirects, isFalse);
        expect(
          captured.headers['authorization'],
          'Bearer ${ControlledSubmissionCredentials.secret}',
        );
        // When the controlled Google response includes one id and unknown fields.
        final response = submissionJsonResponse({
          'ids': ['File_1'],
          'space': 'drive',
          'kind': 'drive#generatedIds',
          'unknown': true,
        });
        // Then prepare must tolerate the extra Google field but upload nothing.
        return response;
      };
      // When preparation allocates a reservation through the public port.
      final reservation = await fixture.drive().prepare(
        request: request,
        material: request.materials.single,
      );
      // Then the exact immutable checkpoint roundtrips through accepted A codec.
      expect(reservation, fixture.reservation(request));
      expect(
        SubmissionCodec.reservationFromJson(
          SubmissionCodec.reservationToJson(reservation),
        ),
        reservation,
      );
      expect(
        () => reservation.data['fileId'] = 'other',
        throwsUnsupportedError,
      );
      expect(fixture.client.requests.single.bytes, isEmpty);
      expect(fixture.credentials.calls, ['drive']);
      expect(
        jsonEncode(SubmissionCodec.reservationToJson(reservation)),
        isNot(contains(ControlledSubmissionCredentials.secret)),
      );
      expect(fixture.client.closed, isFalse);
    });

    final invalidGenerated = <Object?>[
      null,
      [],
      {},
      {'ids': [], 'space': 'drive', 'kind': 'drive#generatedIds'},
      {
        'ids': ['a', 'b'],
        'space': 'drive',
        'kind': 'drive#generatedIds',
      },
      {
        'ids': [7],
        'space': 'drive',
        'kind': 'drive#generatedIds',
      },
      {
        'ids': ['bad/id'],
        'space': 'drive',
        'kind': 'drive#generatedIds',
      },
      {
        'ids': ['a' * 257],
        'space': 'drive',
        'kind': 'drive#generatedIds',
      },
      {
        'ids': ['a'],
        'space': 'appDataFolder',
        'kind': 'drive#generatedIds',
      },
      {
        'ids': ['a'],
        'space': 'drive',
        'kind': 'other',
      },
    ];
    for (var index = 0; index < invalidGenerated.length; index++) {
      test(
        'generated response $index never creates an uploadable checkpoint',
        () async {
          // Given a controlled malformed generateIds response.
          final request = fixture.request();
          fixture.client.respond(
            submissionJsonResponse(invalidGenerated[index]),
          );
          // When the concrete adapter attempts preparation.
          final preparing = fixture.drive().prepare(
            request: request,
            material: request.materials.single,
          );
          // Then only one GET occurs and no unsafe reservation is returned.
          await expectLater(
            preparing,
            throwsA(submissionFailure('invalidResponse')),
          );
          expect(fixture.client.requests.map((request) => request.method), [
            'GET',
          ]);
        },
      );
    }

    for (final mismatch in ['connection', 'key', 'reference']) {
      test('$mismatch rejects before credentials or network', () async {
        // Given a request and direct material that do not bind exactly.
        final request = fixture.request(
          storageId: mismatch == 'connection' ? 'other' : 'drive',
        );
        final material = mismatch == 'key'
            ? fixture.request(key: 'other').materials.single
            : mismatch == 'reference'
            ? fixture.request(originalId: 'other').materials.single
            : request.materials.single;
        // When a direct call bypasses the service's normal material selection.
        final preparing = fixture.drive().prepare(
          request: request,
          material: material,
        );
        // Then a fixed nonretryable configuration failure prevents all IO.
        await expectLater(
          preparing,
          throwsA(
            submissionFailure(
              mismatch == 'connection'
                  ? 'connectionMismatch'
                  : 'materialMismatch',
              stage: SubmissionFailureStage.configuration,
            ),
          ),
        );
        expect(fixture.credentials.calls, isEmpty);
        expect(fixture.client.requests, isEmpty);
      });
    }

    for (final field in [
      'version',
      'fileId',
      'connectionId',
      'accountId',
      'folderId',
      'requestId',
      'materialKey',
      'originalId',
      'mediaType',
      'byteLength',
      'extra',
      'missing',
      'provider',
      'key',
    ]) {
      test('rehydrated reservation $field mismatch prevents upload', () async {
        // Given one malformed binding in a persisted reservation.
        final request = fixture.request();
        final json = SubmissionCodec.reservationToJson(
          fixture.reservation(request),
        );
        final data = json['data']! as Map<String, Object?>;
        if (field == 'provider' || field == 'key') {
          json[field == 'provider' ? 'providerId' : 'key'] = 'other';
        } else if (field == 'extra') {
          data['session'] = 'private-session';
        } else if (field == 'missing') {
          data.remove('folderId');
        } else {
          data[field] = switch (field) {
            'version' => 2,
            'byteLength' => 7,
            'fileId' => 'bad/id',
            _ => 'other',
          };
        }
        final reservation = SubmissionCodec.reservationFromJson(json);
        // When upload receives this actual rehydrated checkpoint.
        final uploading = fixture.drive().upload(
          request: request,
          material: request.materials.single,
          reservation: reservation,
          bytes: Uint8List(6),
        );
        // Then no token/network call precedes the safe configuration rejection.
        await expectLater(
          uploading,
          throwsA(
            submissionFailure(
              'reservationMismatch',
              stage: SubmissionFailureStage.configuration,
            ),
          ),
        );
        expect(fixture.client.requests, isEmpty);
        expect(fixture.credentials.calls, isEmpty);
      });
    }

    test('incorrect actual byte length fails before token retrieval', () async {
      // Given a six-byte immutable original and a truncated caller read.
      final request = fixture.request();
      // When direct upload supplies only five bytes.
      final uploading = fixture.drive().upload(
        request: request,
        material: request.materials.single,
        reservation: fixture.reservation(request),
        bytes: Uint8List(5),
      );
      // Then the original cannot be uploaded with an inconsistent length.
      await expectLater(
        uploading,
        throwsA(
          submissionFailure(
            'originalLengthMismatch',
            stage: SubmissionFailureStage.configuration,
          ),
        ),
      );
      expect(fixture.credentials.calls, isEmpty);
      expect(fixture.client.requests, isEmpty);
    });
  });

  group('HB4 unchanged binary resumable uploads and secret privacy', () {
    for (final specimen in [
      ('image/jpeg', Uint8List.fromList([255, 216, 0, 1, 255, 217])),
      ('audio/wav', Uint8List.fromList([82, 73, 70, 70, 0, 1, 2, 3])),
      ('image/jpeg', Uint8List(5 * 1024 * 1024 + 1)..[5242880] = 231),
    ]) {
      test(
        '${specimen.$1} ${specimen.$2.length} bytes use exact POST then binary PUT',
        () async {
          // Given captured original bytes, including a file over five MiB.
          final bytes = specimen.$2;
          final request = fixture.request(
            length: bytes.length,
            mediaType: specimen.$1,
          );
          configureUpload(fixture, request, bytes);
          // When the concrete adapter sends the persisted reservation.
          final receipt = await fixture.drive().upload(
            request: request,
            material: request.materials.single,
            reservation: fixture.reservation(request),
            bytes: bytes,
          );
          // Then metadata binds the original and only unchanged bytes reach PUT.
          expect(receipt.remoteId, 'File_1');
          expect(
            receipt.storedAt,
            DateTime.utc(2026, 10, 10, 1, 0, 0, 123, 456),
          );
          expect(
            receipt.metadata['createdTime'],
            SubmissionHttpFixture.createdTime,
          );
          expect(receipt.metadata.keys.toSet(), {
            'version',
            'connectionId',
            'accountId',
            'folderId',
            'originalId',
            'mediaType',
            'byteLength',
            'createdTime',
          });
          expect(
            jsonEncode(SubmissionCodec.receiptToJson(receipt)),
            allOf(
              isNot(contains(ControlledSubmissionCredentials.secret)),
              isNot(contains('private-session')),
              isNot(contains('private-remote-marker')),
            ),
          );
          expect(fixture.client.requests.map((value) => value.method), [
            'POST',
            'PUT',
          ]);
          expect(fixture.client.requests.last.bytes, orderedEquals(bytes));
          expect(fixture.client.closed, isFalse);
        },
      );
    }

    test('128-character identities use exact two bounded property segments', () async {
      // Given the maximum accepted ASCII identity length in all three bindings.
      final request = fixture.request(
        id: 'r' * 128,
        key: 'm' * 128,
        originalId: 'o' * 128,
      );
      configureUpload(fixture, request, Uint8List(6));
      // When the concrete resumable creation dispatches the metadata.
      await fixture.drive().upload(
        request: request,
        material: request.materials.single,
        reservation: fixture.reservation(request),
        bytes: Uint8List(6),
      );
      // Then each identity is preserved without hashes and Google limit overflow.
      final properties =
          fixture.client.requests.first.json['appProperties']! as Map;
      expect(properties, {
        'request0': 'r' * 64,
        'request1': 'r' * 64,
        'material0': 'm' * 64,
        'material1': 'm' * 64,
        'original0': 'o' * 64,
        'original1': 'o' * 64,
      });
      for (final entry in properties.entries) {
        // Given an actual property dispatched on the creation request.
        final length = utf8.encode('${entry.key}${entry.value}').length;
        // When checking the Google key-plus-value byte bound.
        final withinLimit = length <= 124;
        // Then every transmitted binding remains within that service contract.
        expect(withinLimit, isTrue);
      }
    });

    test('invocation snapshots bytes before a held credential await', () async {
      // Given a held token grant and caller-owned mutable original bytes.
      final entered = Completer<void>();
      final grant = Completer<String?>();
      fixture.credentials.handler = (_) {
        // Given credential lookup entered by this actual upload.
        entered.complete();
        // When the grant is held, the caller may mutate its own byte buffer.
        final future = grant.future;
        // Then no HTTP request can precede credential release.
        return future;
      };
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      final original = Uint8List.fromList(bytes);
      final request = fixture.request();
      configureUpload(fixture, request, original);
      // When upload is invoked and the caller mutates bytes after token entry.
      final uploading = fixture.drive().upload(
        request: request,
        material: request.materials.single,
        reservation: fixture.reservation(request),
        bytes: bytes,
      );
      try {
        await submissionEntered(entered);
        expect(fixture.client.requests, isEmpty);
        bytes.fillRange(0, bytes.length, 99);
        grant.complete(ControlledSubmissionCredentials.secret);
        final receipt = await uploading;
        // Then PUT contains the invocation snapshot and leaves caller data owned.
        expect(fixture.client.requests.last.bytes, orderedEquals(original));
        expect(bytes, everyElement(99));
        expect(receipt.metadata['byteLength'], 6);
      } finally {
        // Given the held grant must not outlive this test's fixture.
        final held = grant;
        // When a failing assertion leaves the grant pending, release it.
        if (!held.isCompleted) {
          held.complete(ControlledSubmissionCredentials.secret);
        }
        await uploading.catchError((Object error) => throw error);
        // Then this test owns no unresolved credential completion at teardown.
      }
    });

    for (final mode in ['missing', 'malformed', 'throw']) {
      test('$mode credential fails safely without HTTP', () async {
        // Given a missing/invalid/failing ephemeral credential provider.
        final request = fixture.request();
        fixture.credentials.handler = (_) {
          // Given credential lookup for the exact configured connection.
          final outcome = mode;
          // When the controlled provider returns its chosen unsafe outcome.
          if (outcome == 'throw') {
            throw StateError(ControlledSubmissionCredentials.secret);
          }
          // Then missing/malformed tokens reach validation without any network.
          return outcome == 'missing' ? null : 'unsafe token\r\nsecret';
        };
        // When prepare requests credentials through the public adapter.
        final preparing = fixture.drive().prepare(
          request: request,
          material: request.materials.single,
        );
        // Then attribution/privacy is retained with no raw provider cause.
        await expectLater(
          preparing,
          throwsA(
            submissionFailure(
              mode == 'throw' ? 'credentialUnavailable' : 'authRequired',
              stage: SubmissionFailureStage.configuration,
              retryable: mode == 'throw',
            ),
          ),
        );
        expect(fixture.client.requests, isEmpty);
        expect(fixture.credentials.calls, ['drive']);
      });
    }
  });

  group('HB5 retry verifies remote identity and safe upload locations', () {
    for (final conflictStage in ['POST', 'PUT']) {
      test(
        '$conflictStage 409 performs one verification GET and reuses identity',
        () async {
          // Given an existing remote effect whose local receipt was lost.
          final request = fixture.request();
          final material = request.materials.single;
          fixture.client.handler = (captured) {
            // Given the same persisted reservation is retried after a lost result.
            final method = captured.method;
            // When creation/PUT reports conflict, return remote metadata only on GET.
            if (method == conflictStage) return submissionEmptyResponse(409);
            if (method == 'POST') {
              return submissionEmptyResponse(
                200,
                headers: {'location': SubmissionHttpFixture.uploadLocation},
              );
            }
            expect(method, 'GET');
            expect(captured.uri.path, '/drive/v3/files/File_1');
            expect(captured.uri.queryParameters, {
              'supportsAllDrives': 'true',
              'fields':
                  'id,mimeType,size,parents,trashed,appProperties,createdTime',
            });
            // Then a matching metadata read, not 409 alone, proves safe identity.
            return submissionJsonResponse(
              fixture.file(request, material, 'File_1'),
            );
          };
          // When the actual Drive adapter retries this reservation.
          final receipt = await fixture.drive().upload(
            request: request,
            material: material,
            reservation: fixture.reservation(request),
            bytes: Uint8List(6),
          );
          // Then one matching receipt uses remote creation time and the reserved id.
          expect(receipt.remoteId, 'File_1');
          expect(
            receipt.metadata['createdTime'],
            SubmissionHttpFixture.createdTime,
          );
          expect(
            receipt.storedAt,
            DateTime.utc(2026, 10, 10, 1, 0, 0, 123, 456),
          );
          expect(
            fixture.client.requests.map((value) => value.method),
            conflictStage == 'POST' ? ['POST', 'GET'] : ['POST', 'PUT', 'GET'],
          );
        },
      );
    }

    final invalidMetadata = <String, Object?>{
      'id': 'OtherFile',
      'mimeType': 'audio/wav',
      'size': '7',
      'parents': ['OtherFolder'],
      'trashed': true,
      'appProperties': {'request0': 'other'},
      'badSize': '06',
      'negativeSize': '-6',
      'sizeType': 6,
      'badTime': '2026-02-30T10:00:00Z',
      'noZone': '2026-10-10T10:00:00',
      'tooPrecise': '2026-10-10T10:00:00.1234567890Z',
      'parentType': [7],
      'missing': null,
    };
    for (final entry in invalidMetadata.entries) {
      test('remote ${entry.key} never yields a receipt after 409', () async {
        // Given a conflict followed by one mismatched or malformed remote field.
        final request = fixture.request();
        final metadata = fixture.file(
          request,
          request.materials.single,
          'File_1',
        );
        final target = switch (entry.key) {
          'badSize' || 'negativeSize' || 'sizeType' => 'size',
          'badTime' || 'noZone' || 'tooPrecise' => 'createdTime',
          'parentType' => 'parents',
          _ => entry.key,
        };
        if (entry.key == 'missing') {
          metadata.remove('createdTime');
        } else {
          metadata[target] = entry.value;
        }
        fixture.client.handler = (captured) {
          // Given the same persisted file id is retried after a remote effect.
          final method = captured.method;
          // When creation conflicts, the next GET returns the selected metadata.
          final response = method == 'POST'
              ? submissionEmptyResponse(409)
              : submissionJsonResponse(metadata);
          // Then the actual adapter must reject the malformed/mismatched binding.
          return response;
        };
        // When the adapter verifies the existing reserved remote file.
        final uploading = fixture.drive().upload(
          request: request,
          material: request.materials.single,
          reservation: fixture.reservation(request),
          bytes: Uint8List(6),
        );
        // Then malformed fields and valid-but-wrong binding have distinct safe codes.
        final malformed = ![
          'id',
          'mimeType',
          'size',
          'parents',
          'trashed',
          'appProperties',
        ].contains(entry.key);
        await expectLater(
          uploading,
          throwsA(
            submissionFailure(
              malformed ? 'invalidRemoteMetadata' : 'remoteBindingMismatch',
            ),
          ),
        );
        expect(fixture.client.requests.map((value) => value.method), [
          'POST',
          'GET',
        ]);
      });
    }

    for (final status in [404, 308]) {
      test('$status cannot acknowledge an original', () async {
        // Given unavailable conflict verification or an incomplete binary upload.
        final request = fixture.request();
        fixture.client.handler = (captured) {
          // Given this controlled stage-specific response sequence.
          final method = captured.method;
          // When creation conflicts or starts a session, expose the final status.
          if (method == 'POST') {
            return status == 404
                ? submissionEmptyResponse(409)
                : submissionEmptyResponse(
                    200,
                    headers: {'location': SubmissionHttpFixture.uploadLocation},
                  );
          }
          // Then neither 404 verification nor 308 partial upload is a receipt.
          return submissionEmptyResponse(status);
        };
        // When direct upload reaches the selected controlled remote outcome.
        final uploading = fixture.drive().upload(
          request: request,
          material: request.materials.single,
          reservation: fixture.reservation(request),
          bytes: Uint8List(6),
        );
        // Then durable queue retry remains permitted without invented success.
        await expectLater(
          uploading,
          throwsA(
            submissionFailure(
              status == 404 ? 'verificationUnavailable' : 'uploadIncomplete',
              retryable: true,
            ),
          ),
        );
      });
    }

    final badLocations = <String?>[
      null,
      'http://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://foreign.test/upload/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://secret@www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://www.googleapis.com:444/upload/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://www.googleapis.com/other?uploadType=resumable&upload_id=x',
      '${SubmissionHttpFixture.uploadLocation}#fragment',
      '${SubmissionHttpFixture.uploadLocation}&uploadType=resumable',
      '${SubmissionHttpFixture.uploadLocation}&upload_id=other',
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=%20',
    ];
    for (var index = 0; index < badLocations.length; index++) {
      test('unsafe session location $index is rejected before PUT', () async {
        // Given an initiation response with a disallowed transient location.
        final request = fixture.request();
        fixture.client.respond(
          submissionEmptyResponse(
            200,
            headers: {
              if (badLocations[index] != null) 'location': badLocations[index]!,
            },
          ),
        );
        // When the adapter validates the concrete initiation Location.
        final uploading = fixture.drive().upload(
          request: request,
          material: request.materials.single,
          reservation: fixture.reservation(request),
          bytes: Uint8List(6),
        );
        // Then no request forwards a token to that location and no location persists.
        await expectLater(
          uploading,
          throwsA(submissionFailure('invalidUploadLocation')),
        );
        expect(fixture.client.requests.map((value) => value.method), ['POST']);
      });
    }
  });

  group('HB8 total deadline and run retirement', () {
    test('one total deadline spans credential and held creation headers', () async {
      // Given credential and creation delays that individually fit the deadline.
      final request = fixture.request();
      final sent = Completer<void>();
      final headers = Completer<http.StreamedResponse>();
      final grant = Completer<String?>();
      final entered = Completer<void>();
      fixture.credentials.handler = (_) {
        // Given a credential hold starts before any HTTP request.
        entered.complete();
        // When the test releases its account-specific grant partway through the deadline.
        final result = grant.future;
        // Then the remaining HTTP allowance must use the same monotonic operation clock.
        return result;
      };
      fixture.client.handler = (_) {
        // Given creation entered after credential retrieval consumed deadline time.
        sent.complete();
        // When the remaining headers are held until the total allowance expires.
        final result = headers.future;
        // Then a separate new deadline for send would incorrectly permit follow-up.
        return result;
      };
      // When one operation spans both deliberately held stages.
      final uploading = fixture
          .drive(operationTimeout: const Duration(milliseconds: 120))
          .upload(
            request: request,
            material: request.materials.single,
            reservation: fixture.reservation(request),
            bytes: Uint8List(6),
          );
      try {
        await submissionEntered(entered);
        await Future<void>.delayed(const Duration(milliseconds: 70));
        grant.complete(ControlledSubmissionCredentials.secret);
        await submissionEntered(sent);
        await expectLater(
          uploading.timeout(const Duration(milliseconds: 90)),
          throwsA(submissionFailure('operationTimeout', retryable: true)),
        );
        headers.complete(
          submissionEmptyResponse(
            200,
            headers: {'location': SubmissionHttpFixture.uploadLocation},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        // Then the late initiation result cannot reset the clock or dispatch PUT.
        expect(fixture.client.requests.map((value) => value.method), ['POST']);
      } finally {
        // Given both stage completers belong to the test, including on failure.
        final pending = headers;
        // When cleanup settles any held stages with harmless controlled results.
        if (!grant.isCompleted) {
          grant.complete(ControlledSubmissionCredentials.secret);
        }
        if (!pending.isCompleted) {
          pending.complete(submissionEmptyResponse(200));
        }
        // Then no controlled send/credential future survives teardown unresolved.
      }
    });

    test(
      'cancellation during final PUT stream cannot yield a late receipt',
      () async {
        // Given completed creation and a held final PUT metadata stream.
        final request = fixture.request();
        final entered = Completer<void>();
        final cancelled = Completer<void>();
        final cancellation = Completer<void>();
        final controller = StreamController<List<int>>(
          onCancel: () {
            // Given the final PUT response subscription is operation-owned.
            final signal = cancelled;
            // When cancellation detaches that subscription.
            if (!signal.isCompleted) signal.complete();
            // Then the scenario can observe cleanup before releasing late metadata.
          },
        );
        fixture.client.handler = (captured) {
          // Given creation has one valid fixed-host transient session.
          final method = captured.method;
          // When PUT has already sent its unchanged original and returns held headers.
          if (method == 'POST') {
            return submissionEmptyResponse(
              200,
              headers: {'location': SubmissionHttpFixture.uploadLocation},
            );
          }
          expect(method, 'PUT');
          entered.complete();
          // Then remote completion may exist, while local receipt remains unavailable.
          return http.StreamedResponse(controller.stream, 201);
        };
        // When explicit cancellation retires the operation during the final body read.
        final uploading = fixture
            .drive(cancellation: cancellation.future)
            .upload(
              request: request,
              material: request.materials.single,
              reservation: fixture.reservation(request),
              bytes: Uint8List(6),
            );
        try {
          await submissionEntered(entered);
          cancellation.complete();
          await expectLater(
            uploading,
            throwsA(submissionFailure('operationCancelled', retryable: true)),
          );
          await submissionEntered(cancelled);
          controller.add(
            utf8.encode(
              jsonEncode(
                fixture.file(request, request.materials.single, 'File_1'),
              ),
            ),
          );
          await controller.close();
          // Then late valid metadata cannot create a receipt or trigger verification.
          expect(fixture.client.requests.map((value) => value.method), [
            'POST',
            'PUT',
          ]);
          expect(fixture.client.closed, isFalse);
        } finally {
          // Given both cancellation and response resources are owned by this test.
          final owned = controller;
          // When cleanup closes any remaining held stream and signal.
          if (!cancellation.isCompleted) cancellation.complete();
          if (!owned.isClosed) await owned.close();
          // Then no live stream or unresolved cancellation completer remains.
        }
      },
    );

    for (final predicate in [() => false, () => throw StateError('private')]) {
      test(
        'retired or throwing entry predicate performs no token or HTTP IO',
        () async {
          // Given an owner already retired at the public operation boundary.
          final request = fixture.request();
          // When prepare checks its borrowed owner predicate.
          final preparing = fixture
              .drive(isRunCurrent: predicate)
              .prepare(request: request, material: request.materials.single);
          // Then retirement has a fixed retryable failure before any IO.
          await expectLater(
            preparing,
            throwsA(submissionFailure('operationCancelled', retryable: true)),
          );
          expect(fixture.credentials.calls, isEmpty);
          expect(fixture.client.requests, isEmpty);
        },
      );
    }

    test('token deadline discards a late grant and sends nothing', () async {
      // Given a held credential grant and a bounded real operation timer.
      final entered = Completer<void>();
      final grant = Completer<String?>();
      fixture.credentials.handler = (_) {
        // Given token lookup has entered its controlled hold.
        entered.complete();
        // When the late grant stays pending past the operation deadline.
        final pending = grant.future;
        // Then the HTTP stage remains unreachable until the owner permits it.
        return pending;
      };
      final request = fixture.request();
      // When a total deadline expires while credential lookup is held.
      final preparing = fixture
          .drive(operationTimeout: const Duration(milliseconds: 30))
          .prepare(request: request, material: request.materials.single);
      try {
        await submissionEntered(entered);
        await expectLater(
          preparing,
          throwsA(submissionFailure('operationTimeout', retryable: true)),
        );
        grant.complete(ControlledSubmissionCredentials.secret);
        await Future<void>.delayed(Duration.zero);
        // Then late credentials cannot dispatch any follow-up request.
        expect(fixture.client.requests, isEmpty);
      } finally {
        // Given all controlled grants must settle before test teardown.
        final held = grant;
        // When a failure leaves it unresolved, release the late grant.
        if (!held.isCompleted) {
          held.complete(ControlledSubmissionCredentials.secret);
        }
        // Then fixture teardown owns no unresolved credential completer.
      }
    });

    test(
      'cancellation aborts held headers and observes a late send error',
      () async {
        // Given a non-cooperative held HTTP client response and explicit cancellation.
        final entered = Completer<void>();
        final pending = Completer<http.StreamedResponse>();
        final cancellation = Completer<void>();
        final aborted = Completer<void>();
        fixture.client.handler = (captured) {
          // Given the actual abortable request reached the borrowed client.
          captured.abort.then((_) => aborted.complete());
          entered.complete();
          // When response headers are held until the operation has retired.
          final response = pending.future;
          // Then the test can prove abortion and safe late-error observation.
          return response;
        };
        final request = fixture.request();
        // When the operation is cancelled during the held send.
        final preparing = fixture
            .drive(cancellation: cancellation.future)
            .prepare(request: request, material: request.materials.single);
        try {
          await submissionEntered(entered);
          cancellation.complete();
          await expectLater(
            preparing,
            throwsA(submissionFailure('operationCancelled', retryable: true)),
          );
          await submissionEntered(aborted);
          pending.completeError(
            StateError(ControlledSubmissionCredentials.secret),
          );
          await Future<void>.delayed(Duration.zero);
          // Then one aborted GET cannot return a late reservation or dispatch another request.
          expect(fixture.client.requests.length, 1);
          expect(fixture.client.closed, isFalse);
        } finally {
          // Given the test owns both cancellation and held client completions.
          final held = pending;
          // When cleanup must release either remaining signal.
          if (!cancellation.isCompleted) cancellation.complete();
          if (!held.isCompleted) held.complete(submissionEmptyResponse(200));
          // Then no test-owned unresolved response remains at teardown.
        }
      },
    );

    for (final mode in ['cancel', 'deadline', 'oversize']) {
      test('$mode cancels a held response stream and forbids PUT', () async {
        // Given a live initiation stream with observable subscription cancellation.
        final entered = Completer<void>();
        final cancelled = Completer<void>();
        final cancellation = Completer<void>();
        final stream = StreamController<List<int>>(
          onCancel: () {
            // Given this controller observes the adapter's owned subscription.
            final signal = cancelled;
            // When the adapter cancels its current response stream.
            if (!signal.isCompleted) signal.complete();
            // Then the scenario can await actual stream cleanup.
          },
        );
        fixture.client.handler = (_) {
          // Given a creation response whose body has not completed.
          entered.complete();
          // When headers are available, expose the test-owned held stream.
          final response = http.StreamedResponse(
            stream.stream,
            200,
            headers: {'location': SubmissionHttpFixture.uploadLocation},
          );
          // Then the deadline covers response streaming before any PUT.
          return response;
        };
        final request = fixture.request();
        // When cancellation/deadline/body bound retires that stream.
        final uploading = fixture
            .drive(
              cancellation: cancellation.future,
              operationTimeout: mode == 'deadline'
                  ? const Duration(milliseconds: 30)
                  : const Duration(seconds: 1),
            )
            .upload(
              request: request,
              material: request.materials.single,
              reservation: fixture.reservation(request),
              bytes: Uint8List(6),
            );
        try {
          await submissionEntered(entered);
          if (mode == 'cancel') cancellation.complete();
          if (mode == 'oversize') stream.add(Uint8List(262145));
          await expectLater(
            uploading,
            throwsA(
              submissionFailure(switch (mode) {
                'cancel' => 'operationCancelled',
                'deadline' => 'operationTimeout',
                _ => 'invalidResponse',
              }, retryable: mode != 'oversize'),
            ),
          );
          await submissionEntered(cancelled);
          // Then the abandoned creation stream cannot yield a receipt or binary PUT.
          expect(fixture.client.requests.map((value) => value.method), [
            'POST',
          ]);
          expect(fixture.client.closed, isFalse);
        } finally {
          // Given the stream and cancellation completer belong to this test.
          final owned = stream;
          // When cleanup retires all held work.
          if (!cancellation.isCompleted) cancellation.complete();
          await owned.close();
          // Then fixture teardown has no open held response stream.
        }
      });
    }

    test('retirement after creation completes never dispatches PUT', () async {
      // Given a current owner and a completed controlled creation response.
      var current = true;
      final request = fixture.request();
      fixture.client.handler = (_) {
        // Given the POST has reached the controlled Google endpoint.
        final body = Stream<List<int>>.value(const []).map((chunk) {
          // Given creation response streaming resumes under the current owner.
          final unchanged = chunk;
          // When the owner retires before the response stream completes.
          current = false;
          // Then the adapter must recheck retirement before any PUT.
          return unchanged;
        });
        // When its response stream completes after retirement.
        final response = http.StreamedResponse(
          body,
          200,
          headers: {'location': SubmissionHttpFixture.uploadLocation},
        );
        // Then the local receipt is still unavailable and no follow-up is allowed.
        return response;
      };
      // When upload observes retirement immediately after its completed POST.
      final uploading = fixture
          .drive(isRunCurrent: () => current)
          .upload(
            request: request,
            material: request.materials.single,
            reservation: fixture.reservation(request),
            bytes: Uint8List(6),
          );
      // Then safe cancellation fences PUT even after an already sent remote effect.
      await expectLater(
        uploading,
        throwsA(submissionFailure('operationCancelled', retryable: true)),
      );
      expect(fixture.client.requests.map((value) => value.method), ['POST']);
    });

    for (final timeout in [
      Duration.zero,
      const Duration(seconds: -1),
      const Duration(seconds: 46),
    ]) {
      test('invalid total deadline $timeout rejects at construction', () {
        // Given a duration outside the frozen positive-at-most-45s contract.
        final supplied = timeout;
        // When either adapter is constructed with it.
        void drive() => fixture.drive(operationTimeout: supplied);
        void transport() => fixture.transport(operationTimeout: supplied);
        // Then no operation, timer, token or HTTP request is started.
        expect(drive, throwsArgumentError);
        expect(transport, throwsArgumentError);
        expect(fixture.client.requests, isEmpty);
        expect(fixture.credentials.calls, isEmpty);
      });
    }
  });
}

void configureUpload(
  SubmissionHttpFixture fixture,
  SubmissionRequest request,
  Uint8List bytes,
) {
  // Given a complete immutable original and persisted file identity.
  final material = request.materials.single;
  // When the controlled HTTP client observes concrete creation and binary PUT.
  fixture.client.handler = (captured) {
    // Given a request emitted by the actual adapter, with ephemeral auth only.
    expect(
      captured.headers['authorization'],
      'Bearer ${ControlledSubmissionCredentials.secret}',
    );
    expect(captured.followsRedirects, isFalse);
    expect(
      utf8.decode(captured.bytes, allowMalformed: true),
      isNot(contains(ControlledSubmissionCredentials.secret)),
    );
    // When resumable binary creation is initiated on the fixed Google endpoint.
    if (captured.method == 'POST') {
      expect(captured.uri.scheme, 'https');
      expect(captured.uri.host, 'www.googleapis.com');
      expect(captured.uri.path, '/upload/drive/v3/files');
      expect(captured.uri.queryParameters, {
        'uploadType': 'resumable',
        'supportsAllDrives': 'true',
        'fields': 'id,mimeType,size,parents,trashed,appProperties,createdTime',
      });
      expect(
        captured.headers['x-upload-content-length'],
        bytes.length.toString(),
      );
      expect(
        captured.headers['x-upload-content-type'],
        material.original.mediaType,
      );
      expect(captured.json['id'], 'File_1');
      expect(captured.json['name'], '${request.id}_${material.key}');
      expect(captured.json['mimeType'], material.original.mediaType);
      expect(captured.json['parents'], [fixture.driveConnection.folderId]);
      return submissionEmptyResponse(
        200,
        headers: {'location': SubmissionHttpFixture.uploadLocation},
      );
    }
    // Then the one PUT contains unchanged bytes, exact MIME/length and safe metadata.
    expect(captured.method, 'PUT');
    expect(captured.uri, Uri.parse(SubmissionHttpFixture.uploadLocation));
    expect(captured.headers['content-type'], material.original.mediaType);
    expect(captured.headers['content-length'], bytes.length.toString());
    expect(captured.bytes, orderedEquals(bytes));
    return submissionJsonResponse(
      fixture.file(request, material, 'File_1'),
      status: 201,
    );
  };
  // Then upload scenarios assert the actual returned public receipt and PUT body.
}
