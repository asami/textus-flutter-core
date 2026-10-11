import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_http_fixture.dart';

void main() {
  group('HB2 safe explicit connection definitions', () {
    test('closed roundtrip selects exact encoded targets without credentials', () async {
      // Given valid account/folder and encoded HTTPS definitions.
      final fixture = SubmissionHttpFixture();
      addTearDown(fixture.dispose);
      final drive = DriveSubmissionConnection.fromJson(
        jsonDecode(jsonEncode(fixture.driveConnection.toJson()))
            as Map<String, Object?>,
      );
      final server = HttpSubmissionConnection.fromJson(
        jsonDecode(jsonEncode(fixture.httpConnection.toJson()))
            as Map<String, Object?>,
      );
      fixture.client.handler = (captured) {
        // Given an actual operation using the rehydrated configured endpoint.
        expect(captured.uri, server.endpoint);
        // When the controlled HTTP server returns explicit acceptance.
        final response = submissionJsonResponse(
          fixture.acknowledgement(fixture.request(withMaterial: false)),
        );
        // Then the exact endpoint is observable before acknowledgement parsing.
        return response;
      };
      // When the public transport borrows the decoded definition.
      final acknowledgement = await HttpSubmissionTransport(
        connection: server,
        client: fixture.client,
        credentials: fixture.credentials,
      ).submit(fixture.packet(fixture.request(withMaterial: false)));
      // Then definitions preserve identity and wire behavior without secret fields.
      expect(drive.id, fixture.driveConnection.id);
      expect(drive.accountId, fixture.driveConnection.accountId);
      expect(drive.folderId, fixture.driveConnection.folderId);
      expect(
        server.endpoint.toString(),
        fixture.httpConnection.endpoint.toString(),
      );
      expect(server.requiresBearerToken, isTrue);
      expect(acknowledgement.requestId, 'commit1');
      expect(
        jsonEncode([drive.toJson(), server.toJson()]),
        isNot(contains(ControlledSubmissionCredentials.secret)),
      );
    });

    for (final value in ['', 'bad/id', ' a', 'a' * 129, '_first']) {
      test('unsafe connection identity is rejected: ${value.length}', () {
        // Given an identity outside the accepted A token contract.
        final id = value;
        // When either public definition is constructed.
        void drive() => DriveSubmissionConnection(
          id: id,
          accountId: 'account',
          folderId: 'folder',
        );
        void server() => HttpSubmissionConnection(
          id: id,
          endpoint: Uri.parse('https://example.test/submit'),
        );
        // Then neither definition can enter queue configuration.
        expect(drive, throwsArgumentError);
        expect(server, throwsArgumentError);
      });
    }

    for (final account in [
      '',
      '  ',
      'a\nsecret',
      'a\rsecret',
      'a\u0000secret',
      '界' * 86,
    ]) {
      test('invalid account is rejected: ${account.length}', () {
        // Given an invalid account, including UTF-8 byte length overflow.
        final supplied = account;
        // When the public Drive target is constructed.
        void construct() => DriveSubmissionConnection(
          id: 'drive',
          accountId: supplied,
          folderId: 'folder',
        );
        // Then rejection is safe and contains no supplied account.
        expect(
          construct,
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('secret')),
            ),
          ),
        );
      });
    }

    for (final folder in ['', 'a/b', 'a b', 'a' * 257, 'a\n']) {
      test('invalid Drive identity is rejected: ${folder.length}', () {
        // Given a folder outside the Google safe identity vocabulary.
        final supplied = folder;
        // When a public Drive definition is created.
        void construct() => DriveSubmissionConnection(
          id: 'drive',
          accountId: 'account',
          folderId: supplied,
        );
        // Then invalid configuration fails synchronously before any IO.
        expect(construct, throwsArgumentError);
      });
    }

    for (final endpoint in [
      'http://example.test/submit',
      '/submit',
      'https://example.test',
      'https://secret@example.test/submit',
      'https://example.test/submit?',
      'https://example.test/submit?token=secret',
      'https://example.test/submit#',
      'https://example.test/submit#secret',
      'https:///submit',
    ]) {
      test('unsafe endpoint rejects without echo: $endpoint', () {
        // Given a URI that cannot be a configured submission endpoint.
        final uri = Uri.parse(endpoint);
        // When the immutable HTTP connection is constructed.
        void construct() =>
            HttpSubmissionConnection(id: 'server', endpoint: uri);
        // Then rejection is synchronous and does not reflect credentials.
        expect(
          construct,
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('secret')),
            ),
          ),
        );
      });
    }

    for (final type in ['drive', 'http']) {
      for (final mutation in [
        'extra',
        'missing',
        'version',
        'versionType',
        'type',
        'id',
        'fieldType',
      ]) {
        test('closed $type decoding rejects $mutation', () {
          // Given a valid closed version 1 definition with one malformed clause.
          final fixture = SubmissionHttpFixture();
          addTearDown(fixture.dispose);
          final json = type == 'drive'
              ? fixture.driveConnection.toJson()
              : fixture.httpConnection.toJson();
          switch (mutation) {
            case 'extra':
              json['token'] = 'secret';
            case 'missing':
              json.remove('id');
            case 'version':
              json['version'] = 2;
            case 'versionType':
              json['version'] = 1.0;
            case 'type':
              json['type'] = 'other';
            case 'id':
              json['id'] = 'secret/unsafe';
            case 'fieldType':
              json[type == 'drive' ? 'accountId' : 'requiresBearerToken'] = 9;
          }
          // When decoding through the public strict factory.
          void decode() {
            if (type == 'drive') {
              DriveSubmissionConnection.fromJson(json);
            } else {
              HttpSubmissionConnection.fromJson(json);
            }
          }

          // Then rejection is a safe FormatException with no reflected input.
          expect(
            decode,
            throwsA(
              isA<FormatException>().having(
                (error) => error.toString(),
                'safe format error',
                isNot(contains('secret')),
              ),
            ),
          );
          expect(fixture.client.requests, isEmpty);
          expect(fixture.credentials.calls, isEmpty);
        });
      }
    }
  });
}
