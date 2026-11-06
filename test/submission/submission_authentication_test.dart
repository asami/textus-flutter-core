import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';

void main() {
  group('local authentication identity values', () {
    test('opaque identity snapshots are inert, exact and safely printable', () {
      // Given a canonical authority and an opaque account with Unicode/whitespace.
      final authority = _authority();
      const account = '  利用者/opaque:α\n ';
      var calls = 0;
      // When binding and borrowed lifetime values are constructed.
      final binding = SubmissionAuthenticationBinding(
        authority: authority,
        userAccountId: account,
      );
      final context = SubmissionAuthenticationContext(
        binding: binding,
        isCurrent: () {
          calls++;
          throw StateError('private-lifetime');
        },
      );
      // Then construction invokes no callback and keeps exact identity only.
      expect(calls, 0);
      expect(binding.authorityProfileId, authority.profileId);
      expect(binding.authorityBaseUri, authority.serviceBaseUri);
      expect(binding.userAccountId, account);
      expect(binding.toString(), 'SubmissionAuthenticationBinding');
      expect(context.toString(), 'SubmissionAuthenticationContext');
      expect(context.binding, same(binding));
      // When the lifetime is explicitly observed and the callback throws.
      final current = context.isCurrent;
      // Then failure withdraws the local fence without exposing private errors.
      expect(current, isFalse);
      expect(calls, 1);
    });

    test(
      'all three exact identity fields participate in equality and hashing',
      () {
        // Given independently constructed equivalent and distinct local identities.
        final binding = _binding();
        final equal = _binding();
        final different = [
          _binding(account: 'B'),
          _binding(account: ' A '),
          _binding(profile: 'another.profile'),
          _binding(base: 'https://other.example/account/'),
        ];
        // When equal values are used as keys and distinct identities compared.
        final identities = {binding, equal, ...different};
        // Then equal values share a stable hash and every identity edge separates.
        expect(binding, equal);
        expect(binding.hashCode, equal.hashCode);
        expect(binding.hashCode, binding.hashCode);
        expect(identities.length, 5);
        for (final value in different) {
          expect(value, isNot(binding));
        }
      },
    );

    for (final account in ['', ' \t\n ']) {
      test(
        'blank account ${account.length} is rejected without reflection',
        () {
          // Given a valid authority and an absent opaque account identity.
          final authority = _authority();
          // When construction applies existing AuthenticatedUserAccount validation.
          final error = _captureError(
            () => SubmissionAuthenticationBinding(
              authority: authority,
              userAccountId: account,
            ),
          );
          // Then it rejects the value with the existing fixed safe diagnostic.
          expect(
            error,
            isA<ArgumentError>().having(
              (error) => error.message,
              'safe message',
              'Invalid account identity',
            ),
          );
        },
      );
    }

    test('binding v1 detaches maps and retains canonical development identity', () {
      // Given explicit LAN identity admitted by the existing profile parser.
      final binding = _binding(base: 'http://192.168.1.2/account/');
      final input = binding.toJson();
      // When closed v1 is decoded and caller/output maps are subsequently edited.
      final restored = SubmissionAuthenticationBinding.fromJson(input);
      input['userAccountId'] = 'B';
      final output = restored.toJson()..['authorityProfileId'] = 'changed';
      // Then the immutable binding remains exact and each encoding is detached.
      expect(restored, binding);
      expect(restored.toJson(), {
        'version': 1,
        'authorityProfileId': 'authority.main',
        'authorityBaseUri': 'http://192.168.1.2/account/',
        'userAccountId': 'A',
      });
      expect(output, isNot(restored.toJson()));
      expect(identical(restored.toJson(), restored.toJson()), isFalse);
    });

    final invalidBindings = <String, Object?>{
      'null': null,
      'array': <Object?>[],
      'missing key': _binding().toJson()..remove('userAccountId'),
      'extra key': {..._binding().toJson(), 'credential': 'private-input'},
      'unknown version': {..._binding().toJson(), 'version': 2},
      'version scalar': {..._binding().toJson(), 'version': '1'},
      'account type': {..._binding().toJson(), 'userAccountId': 1},
      'blank account': {..._binding().toJson(), 'userAccountId': '  '},
      'profile type': {..._binding().toJson(), 'authorityProfileId': null},
      'invalid profile': {
        ..._binding().toJson(),
        'authorityProfileId': 'private/input',
      },
      'base type': {..._binding().toJson(), 'authorityBaseUri': true},
      'malformed base': {
        ..._binding().toJson(),
        'authorityBaseUri': 'private-input',
      },
      'noncanonical base': {
        ..._binding().toJson(),
        'authorityBaseUri': 'https://authority.example/account',
      },
      'repeated slash': {
        ..._binding().toJson(),
        'authorityBaseUri': 'https://authority.example/account///',
      },
      'unsafe authority': {
        ..._binding().toJson(),
        'authorityBaseUri': 'https://private-input@authority.example/',
      },
      'query': {
        ..._binding().toJson(),
        'authorityBaseUri': 'https://authority.example/?private-input',
      },
      'traversal': {
        ..._binding().toJson(),
        'authorityBaseUri': 'https://authority.example/private-input/../',
      },
      'public http': {
        ..._binding().toJson(),
        'authorityBaseUri': 'http://private-input.example/',
      },
    };
    for (final entry in invalidBindings.entries) {
      test('closed binding schema rejects ${entry.key} safely', () {
        // Given a malformed retained identity, including private marker inputs.
        final input = entry.value;
        // When the closed binding decoder interprets the retained value.
        final error = _captureError(
          () => SubmissionAuthenticationBinding.fromJson(input),
        );
        // Then rejection is fixed and never echoes the private marker.
        expect(
          error,
          isA<FormatException>().having(
            (error) => error.toString(),
            'safe error',
            isNot(contains('private-input')),
          ),
        );
      });
    }
  });

  group('request persistence and immutable intent', () {
    late SubmissionFixture fixture;
    setUp(() async {
      // Given isolated native originals/database ownership for each scenario.
      // When a real FileCaptureStore/SQLite fixture is allocated.
      fixture = await SubmissionFixture.create();
      // Then the scenario owns its handles without altering a global factory.
    });
    tearDown(() async {
      // Given the scenario's borrowed services and owned queues.
      // When fixture disposal drains services before closing queues.
      await fixture.dispose();
      // Then only the isolated temporary disk artifacts are removed.
    });

    for (final tkl in [false, true]) {
      test(
        'bound ${tkl ? 'TKL' : 'legacy route'} uses exact local v3',
        () async {
          // Given immutable opaque JSON and real saved photo/audio references.
          final legacy = await fixture.request();
          final binding = _binding(account: '  利用者/α  ');
          final request = _request(legacy, binding: binding, tkl: tkl);
          // When complete local intent is encoded and decoded.
          final encoded = SubmissionCodec.requestToJson(request);
          final restored = SubmissionCodec.requestFromJson(encoded);
          // Then v3 requires a nonnull binding and an always-present TKL slot.
          expect(encoded.keys.toSet(), {
            ..._commonKeys,
            'tklDelivery',
            'authenticationBinding',
          });
          expect(encoded['version'], 3);
          expect(encoded['authenticationBinding'], binding.toJson());
          expect(encoded['tklDelivery'], tkl ? isA<Map>() : isNull);
          expect(restored, request);
          expect(restored.hashCode, request.hashCode);
          expect(restored.authenticationBinding, binding);
          expect(restored.document, legacy.document);
          expect(restored.payload, legacy.payload);
          expect(restored.materials, legacy.materials);
          expect(() => restored.materials.clear(), throwsUnsupportedError);
          expect(() => restored.document.clear(), throwsUnsupportedError);
          // When a detached encoded map changes its binding after decode.
          (encoded['authenticationBinding']! as Map)['userAccountId'] = 'B';
          // Then accepted intent and its equality remain tied to A.
          expect(restored.authenticationBinding, binding);
          expect(restored, request);
          expect(
            _request(
              legacy,
              binding: _binding(account: 'B'),
              tkl: tkl,
            ),
            isNot(request),
          );
          expect(_request(legacy, tkl: tkl), isNot(request));
        },
      );

      test('unbound v${tkl ? 2 : 1} retains exact existing JSON', () async {
        // Given an explicitly unbound request with unchanged selected routing.
        final original = await fixture.request(withMaterials: false);
        final request = _request(original, tkl: tkl);
        final delivery = request.tklDelivery;
        final expected = <String, Object?>{
          'version': tkl ? 2 : 1,
          'id': original.id,
          'kind': original.kind,
          'subjectId': original.subjectId,
          'createdAt': original.createdAt.toIso8601String(),
          'document': original.document,
          'payload': original.payload,
          'materials': <Object?>[],
          'transportConnectionId': original.transportConnectionId,
          'storageConnectionId': null,
          'extensions': original.extensions,
          if (tkl)
            'tklDelivery': {
              'requestId': delivery!.requestId,
              'contribution': delivery.contribution,
            },
        };
        // When the original local versions are encoded and round-tripped.
        final encoded = SubmissionCodec.requestToJson(request);
        final restored = SubmissionCodec.requestFromJson(encoded);
        // Then exact key omission and unbound identity survive without adoption.
        expect(encoded, expected);
        expect(encoded.keys.toSet(), {..._commonKeys, if (tkl) 'tklDelivery'});
        expect(restored, request);
        expect(restored.authenticationBinding, isNull);
        expect(SubmissionCodec.requestToJson(restored), expected);
      });
    }

    test(
      'v3 rejects missing/null/extra/invalid binding and invalid TKL values',
      () async {
        // Given a valid bound local request and independent malformed schema copies.
        final request = _request(await fixture.request(), binding: _binding());
        final valid = SubmissionCodec.requestToJson(request);
        final invalid = <Map<String, Object?>>[
          {...valid}..remove('authenticationBinding'),
          {...valid}..remove('tklDelivery'),
          {...valid, 'authenticationBinding': null},
          {...valid, 'authenticationBinding': 'private-input'},
          {
            ...valid,
            'authenticationBinding': {..._binding().toJson(), 'extra': true},
          },
          {...valid, 'tklDelivery': false},
          {...valid, 'tklDelivery': <String, Object?>{}},
          {...valid, 'extra': true},
          {...valid, 'version': 4},
          {...valid, 'version': 1},
          {...valid, 'version': 2},
        ];
        for (final json in invalid) {
          // When a malformed local version is offered to the closed request decoder.
          final error = _captureError(
            () => SubmissionCodec.requestFromJson(json),
          );
          // Then no schema is repaired, adopted or reflected into an error.
          expect(
            error,
            isA<FormatException>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('private-input')),
            ),
          );
        }
      },
    );

    test(
      'server packet v1 contains the exact preexisting selected fields',
      () async {
        // Given bound local intent and actual original references with controlled receipts.
        final request = _request(await fixture.request(), binding: _binding());
        final receipts = <String, SubmissionMaterialReceipt>{};
        for (final material in request.materials) {
          final reservation = fixture.storage.reservation(
            material.key,
            request.id,
          );
          receipts[material.key] = await fixture.storage.upload(
            request: request,
            material: material,
            reservation: reservation,
            bytes: await fixture.materials.readMaterial(material.original),
          );
        }
        // When the existing selected-field server packet is encoded.
        final packet = SubmissionCodec.packetToJson(
          SubmissionPacket(request: request, receipts: receipts),
        );
        // Then local document, binding and authority never enlarge the wire schema.
        expect(packet, {
          'version': 1,
          'requestId': request.id,
          'kind': request.kind,
          'subjectId': request.subjectId,
          'createdAt': request.createdAt.toIso8601String(),
          'payload': request.payload,
          'extensions': request.extensions,
          'materials': [
            for (final material in request.materials)
              {
                ...SubmissionCodec.materialToJson(material),
                'receipt': SubmissionCodec.receiptToJson(
                  receipts[material.key]!,
                ),
              },
          ],
        });
        expect(packet.containsKey('document'), isFalse);
        expect(packet.containsKey('authenticationBinding'), isFalse);
        expect(packet.containsKey('authorityBaseUri'), isFalse);
      },
    );

    test(
      'real SQLite reopen retains binding and rejects every identity conflict',
      () async {
        // Given saved originals and bound A intent in a real SQLite queue.
        final original = await fixture.request();
        final request = _request(original, binding: _binding());
        var queue = await fixture.openQueue();
        final accepted = await queue.enqueue(request);
        await queue.close();
        // When a new native handle reads and idempotently enqueues the equal value.
        queue = await fixture.openQueue();
        final duplicate = await queue.enqueue(
          _request(original, binding: _binding()),
        );
        // Then binding, originals and complete intent retain exact identity.
        expect(duplicate, accepted);
        expect(await queue.find(request.id), accepted);
        expect(duplicate.request.authenticationBinding, _binding());
        final conflicts = [
          _request(original, binding: _binding(account: 'B')),
          _request(original, binding: _binding(profile: 'other')),
          _request(original, binding: _binding(base: 'https://other.example/')),
          original,
        ];
        for (final conflict in conflicts) {
          // When the same Commit ID is offered under another participant or legacy intent.
          await expectLater(queue.enqueue(conflict), throwsStateError);
          // Then the accepted row cannot be overwritten or adopted.
          expect(await queue.find(request.id), accepted);
        }
      },
    );

    test(
      'an unbound persisted row cannot be adopted by a bound same ID',
      () async {
        // Given a real unbound queue row that predates participant binding.
        final original = await fixture.request();
        var queue = await fixture.openQueue();
        final accepted = await queue.enqueue(original);
        await queue.close();
        queue = await fixture.openQueue();
        // When bound A intent attempts to reuse its Commit ID.
        await expectLater(
          queue.enqueue(_request(original, binding: _binding())),
          throwsStateError,
        );
        // Then existing v1 JSON remains unbound and unchanged.
        expect(await queue.find(original.id), accepted);
        expect(
          SubmissionCodec.requestToJson(
            (await queue.find(original.id))!.request,
          )['version'],
          1,
        );
      },
    );
  });
}

const _commonKeys = {
  'version',
  'id',
  'kind',
  'subjectId',
  'createdAt',
  'document',
  'payload',
  'materials',
  'transportConnectionId',
  'storageConnectionId',
  'extensions',
};

UserAccountHttpProfile _authority({
  String profile = 'authority.main',
  String base = 'https://authority.example/account/',
}) => UserAccountHttpProfile.fromString(
  profileId: profile,
  serviceBaseUri: base,
  allowDevelopmentHttp: true,
);

SubmissionAuthenticationBinding _binding({
  String account = 'A',
  String profile = 'authority.main',
  String base = 'https://authority.example/account/',
}) => SubmissionAuthenticationBinding(
  authority: _authority(profile: profile, base: base),
  userAccountId: account,
);

SubmissionRequest _request(
  SubmissionRequest original, {
  SubmissionAuthenticationBinding? binding,
  bool tkl = false,
}) => SubmissionRequest(
  id: original.id,
  kind: original.kind,
  subjectId: original.subjectId,
  createdAt: original.createdAt,
  document: original.document,
  payload: original.payload,
  materials: original.materials,
  transportConnectionId: original.transportConnectionId,
  storageConnectionId: tkl ? null : original.storageConnectionId,
  extensions: original.extensions,
  authenticationBinding: binding,
  tklDelivery: tkl
      ? TklMaterialDeliveryRequest(
          requestId: original.id,
          contribution: {'originals': <Object?>[], 'opaque': ' 原文 '},
        )
      : null,
);

Object? _captureError(Object? Function() operation) {
  try {
    operation();
  } catch (error) {
    return error;
  }
  return null;
}
