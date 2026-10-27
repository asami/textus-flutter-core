import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

String golden(String name) =>
    File('test/fixtures/cncf_display_reference_v1/$name.json')
        .readAsStringSync();
Map<String, Object?> fixture(String name) =>
    Map<String, Object?>.from(jsonDecode(golden(name)) as Map);
final initial = fixture('detail-initial');
final resourceId =
    ((initial['model']! as Map)['resource'] as Map)['entityId']! as String;
const title = CncfDisplayFieldLocator('main', 'title');
const description = CncfDisplayFieldLocator('main', 'description');

CncfDisplayReadProfile profile({
  String? mutationRevision = 'ess-reference-mutation-1',
}) => CncfDisplayReadProfile(
  componentId: 'org.simplemodeling.textus.EditingStudio',
  resourceType: 'collecting-reference',
  listScreenId: 'collecting-resources',
  detailScreenId: 'capture-detail',
  definitionRevision: 'ess-reference-definition-1',
  mutationRevision: mutationRevision,
  semanticContract: Map<String, Object?>.from(
    initial['semanticContract']! as Map,
  ),
  provenance: Map<String, Object?>.from(initial['provenance']! as Map),
);

http.Response rawReply(String raw, {int status = 200}) => http.Response.bytes(
  utf8.encode(raw),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response reply(Object? value, {int status = 200}) =>
    rawReply(jsonEncode({'data': value}), status: status);

Map<String, Object?> result({
  String outcome = 'updated',
  String revision = '2',
  String? pending,
  Map<String, Object?>? context,
}) {
  final source = fixture('mutation-descriptor');
  final detail = fixture('detail-initial');
  ((detail['model']! as Map)['resource'] as Map)['revision'] = revision;
  if (context != null) detail['presentationContext'] = context;
  return {
    'schema': 'cncf.display-mutation-result.v1',
    'version': 1,
    'componentId': source['componentId'],
    'resourceType': source['resourceType'],
    'definition': source['definition'],
    'provenance': source['provenance'],
    'outcome': outcome,
    // A raw marker is replaced by wireResult; never parse a Long through double.
    'resource': {'entityId': resourceId, 'revision': '@receipt-revision@'},
    'projection': pending == null
        ? {'type': 'ready', 'display': detail}
        : {'type': 'pending', 'reason': pending},
    'retryCommand': false,
    'presentationContext': ?context,
  };
}

String wireResult(Map<String, Object?> value, {String revision = '2'}) =>
    jsonEncode({'data': value}).replaceFirst('"@receipt-revision@"', revision);

Matcher code(String value, {bool? unknown}) => isA<CncfDisplayReadException>()
    .having((error) => error.code, 'code', value)
    .having(
      (error) => unknown == null || error.outcomeUnknown == unknown,
      'outcome classification',
      isTrue,
    );

final class Harness {
  Harness({
    this.descriptorData,
    this.detailData,
    this.detailReply,
    this.updateReply,
    Future<String?> Function()? token,
    Duration timeout = const Duration(seconds: 2),
    CncfDisplayReadProfile? selectedProfile,
  }) {
    transport = MockClient((request) async {
      requests.add(request);
      if (request.method == 'PUT') {
        final respond = updateReply;
        if (respond != null) return respond(request);
        return rawReply(wireResult(result()));
      }
      if (request.url.path.endsWith('describeMutation.json')) {
        return reply(descriptorData ?? fixture('mutation-descriptor'));
      }
      final respond = detailReply;
      if (respond != null) return respond(request);
      return reply(detailData ?? fixture('detail-initial'));
    });
    service = CncfDisplayReadClient(
      profile: selectedProfile ?? profile(),
      endpoint: Uri.parse('https://studio.test/rest/v1/editing-studio/'),
      client: transport,
      bearerToken: token ?? () async => 'private-test-token',
      timeout: timeout,
    );
  }
  final Map<String, Object?>? descriptorData;
  final Map<String, Object?>? detailData;
  final Future<http.Response> Function(http.Request)? detailReply;
  final Future<http.Response> Function(http.Request)? updateReply;
  final requests = <http.Request>[];
  late final http.Client transport;
  late final CncfDisplayReadClient service;
  late CncfDisplayMutationDescriptor descriptor;
  late CncfDisplayRead observation;
  Future<void> prepare() async {
    descriptor = await service.describeMutation();
    observation = await service.read(resourceId);
  }

  Future<CncfDisplayMutationResult> update({
    List<CncfDisplayTextChange>? changes,
  }) => service.update(
    descriptor: descriptor,
    observation: observation,
    changes: changes ?? const [CncfDisplayTextChange(title, '日本の民話・改訂')],
  );
  void close() {
    service.dispose();
    transport.close();
  }
}

void main() {
  group('formal mutation descriptor', () {
    test('should preserve producer order, scoped identity and independent states', () async {
      // Given the unchanged producer descriptor and separately selected authority.
      final harness = Harness();
      addTearDown(harness.close);
      // When descriptor admission completes without a resource or command body.
      final descriptor = await harness.service.describeMutation();
      // Then ordered fields, explicit bindings and distinct support/availability survive.
      expect(descriptor.fields.map((field) => field.locator.fieldId), [
        'title',
        'stage',
        'description',
      ]);
      expect(descriptor.fields.map((field) => field.bindingId), [
        'write.title',
        null,
        'write.description',
      ]);
      expect(descriptor.fields.map((field) => field.isEditableText), [
        true,
        false,
        true,
      ]);
      expect(descriptor.supports('create'), isFalse);
      expect(descriptor.isAvailable('create'), isTrue);
      expect(title, const CncfDisplayFieldLocator('main', 'title'));
      expect(
        title.hashCode,
        const CncfDisplayFieldLocator('main', 'title').hashCode,
      );
      expect(title, isNot(const CncfDisplayFieldLocator('other', 'title')));
      expect(() => descriptor.fields.clear(), throwsUnsupportedError);
      expect(
        () => descriptor.fields.first.web['hidden'] = true,
        throwsUnsupportedError,
      );
      expect(harness.requests.single.method, 'GET');
      expect(harness.requests.single.bodyBytes, isEmpty);
      expect(harness.requests.single.url.queryParameters, {
        'resourceType': 'collecting-reference',
        'screenId': 'capture-detail',
        'textus.output.shape': 'envelope',
      });
    });

    for (final mutation in <String, void Function(Map<String, Object?>)>{
      'unknown root': (wire) => wire['extra'] = true,
      'null field': (wire) =>
          (wire['fields']! as List).first['bindingId'] = null,
      'foreign component': (wire) => wire['componentId'] = 'foreign',
      'foreign resource': (wire) => wire['resourceType'] = 'foreign',
      'foreign provenance': (wire) =>
          (wire['provenance']! as Map)['sourceId'] = 'foreign',
      'definition revision': (wire) =>
          (wire['definition']! as Map)['revision'] = 'foreign',
      'mutation revision': (wire) =>
          (wire['definition']! as Map)['mutationRevision'] = 'foreign',
      'unknown definition': (wire) =>
          (wire['definition']! as Map)['extra'] = 'foreign',
      'duplicate locator': (wire) =>
          (wire['fields']! as List).add((wire['fields']! as List).first),
      'duplicate binding': (wire) =>
          (wire['fields']! as List).last['bindingId'] = 'write.title',
      'unbound editable': (wire) =>
          ((wire['fields']! as List).first as Map).remove('bindingId'),
      'unknown kind': (wire) =>
          (wire['fields']! as List).first['acceptedKinds'] = ['image'],
      'empty kinds': (wire) =>
          (wire['fields']! as List).first['acceptedKinds'] = [],
      'duplicate kinds': (wire) =>
          (wire['fields']! as List).first['acceptedKinds'] = ['text', 'text'],
      'wrong support tag': (wire) =>
          (wire['capabilities']! as Map)['update'] = 'enabled',
      'wrong availability tag': (wire) =>
          (wire['availability']! as Map)['update'] = 'supported',
      'wrong editability tag': (wire) =>
          (wire['fields']! as List).first['editability'] = 'writable',
      'unknown web': (wire) =>
          (wire['fields']! as List).first['web']['path'] = 'internal',
      'wrong web flag': (wire) =>
          (wire['fields']! as List).first['web']['hidden'] = 'false',
      'null validation': (wire) =>
          (wire['fields']! as List).first['web']['validation'] = null,
      'noncanonical decimal': (wire) =>
          (wire['fields']! as List).first['web']['validation'] = {
            'min': '01.0',
          },
      'negative length': (wire) =>
          (wire['fields']! as List).first['web']['validation'] = {
            'minLength': -1,
          },
      'fractional length': (wire) =>
          (wire['fields']! as List).first['web']['validation'] = {
            'maxLength': 1.0,
          },
      'overflow length': (wire) =>
          (wire['fields']! as List).first['web']['validation'] = {
            'maxLength': 2147483648,
          },
    }.entries) {
      test('should reject descriptor ${mutation.key}', () async {
        // Given one malformed descriptor member at a defined public boundary.
        final data = fixture('mutation-descriptor');
        mutation.value(data);
        final harness = Harness(descriptorData: data);
        addTearDown(harness.close);
        // When the descriptor is fetched, Then admission fails without any command.
        await expectLater(
          harness.service.describeMutation(),
          throwsA(isA<CncfDisplayReadException>()),
        );
        expect(
          harness.requests.where((request) => request.method == 'PUT'),
          isEmpty,
        );
      });
    }

    test(
      'should retain inert canonical hints and scoped repeated field names',
      () async {
        // Given canonical decimal/Int hints and the same field ID in another section.
        final data = fixture('mutation-descriptor');
        final first = (data['fields']! as List).first as Map;
        first['web']['validation'] = {
          'min': '-1.00',
          'max': '1E+2147483648',
          'step': '1E-2147483647',
          'minLength': 0,
          'maxLength': 2147483647,
          'pattern': 'inert[',
        };
        first['web']['values'] = ['one', 'two'];
        first['web']['controlType'] = 'text';
        first['web']['placeholder'] = '説明';
        first['web']['help'] = 'private hint';
        final scoped = Map<String, Object?>.from(first)
          ..['sectionId'] = 'secondary'
          ..['bindingId'] = 'write.secondary';
        (data['fields']! as List).add(scoped);
        final harness = Harness(descriptorData: data);
        addTearDown(harness.close);
        // When the descriptor is admitted, Then hints remain immutable data, never evaluated.
        final descriptor = await harness.service.describeMutation();
        expect(
          descriptor.fields.last.locator,
          const CncfDisplayFieldLocator('secondary', 'title'),
        );
        expect(
          descriptor.fields.first.web['validation'],
          first['web']['validation'],
        );
        expect(descriptor.fields.first.web['values'], ['one', 'two']);
      },
    );

    test('should preserve bound readonly identity and all five admitted kinds as metadata', () async {
      // Given current readonly veto on an explicit binding with all known value kinds.
      final data = fixture('mutation-descriptor');
      final first = (data['fields']! as List).first as Map;
      first['editability'] = 'read-only';
      first['acceptedKinds'] = [
        'text',
        'number',
        'boolean',
        'timestamp',
        'missing',
      ];
      final harness = Harness(descriptorData: data);
      addTearDown(harness.close);
      // When descriptor admission runs, Then bound readonly retains its ID without granting edit.
      final descriptor = await harness.service.describeMutation();
      expect(descriptor.fields.first.bindingId, 'write.title');
      expect(descriptor.fields.first.acceptedKinds, first['acceptedKinds']);
      expect(descriptor.fields.first.isEditableText, isFalse);
    });

    for (final lexical in {
      'fractional version': golden('mutation-descriptor')
          .replaceFirst('"version":1', '"version":1.0'),
      'exponent version': golden('mutation-descriptor')
          .replaceFirst('"version":1', '"version":1e0'),
      'escaped duplicate web key': golden(
        'mutation-descriptor',
      ).replaceFirst('"hidden":false', r'"hidden":false,"\u0068idden":false'),
      'duplicate definition key': golden('mutation-descriptor')
          .replaceFirst('"screenId":', '"screenId":"foreign","screenId":'),
      'trailing top value': '${golden('mutation-descriptor')} false',
      'unfinished object': '{"schema":',
    }.entries) {
      test('should reject descriptor ${lexical.key} from raw JSON', () async {
        // Given raw JSON with nonliteral version, duplicate decoded keys or invalid syntax.
        final transport = MockClient(
          (_) async => rawReply('{"data":${lexical.value}}'),
        );
        final service = CncfDisplayReadClient(
          profile: profile(),
          endpoint: Uri.parse('https://studio.test/'),
          client: transport,
          bearerToken: () async => 'token',
        );
        addTearDown(() {
          service.dispose();
          transport.close();
        });
        // When strict raw admission runs, Then no collapsed or recovered value is admitted.
        await expectLater(
          service.describeMutation(),
          throwsA(isA<CncfDisplayReadException>()),
        );
      });
    }
  });

  group('exact Text update', () {
    test('should send producer bytes with physical selectors, observation and fresh tokens', () async {
      // Given independent producer descriptor/read/request goldens and per-call tokens.
      var tokenCalls = 0;
      final harness = Harness(token: () async => 'token-${++tokenCalls}');
      addTearDown(harness.close);
      await harness.prepare();
      // When one title update is submitted against the admitted Detail.
      final receipt = await harness.update();
      final request = harness.requests.last;
      // Then actual UTF8 bytes match the producer request; observation stays in one header.
      expect(request.method, 'PUT');
      expect(request.url.path, '/rest/v1/editing-studio/display/update.json');
      expect(request.url.queryParameters, {
        'resourceType': 'collecting-reference',
        'screenId': 'capture-detail',
        'textus.output.shape': 'envelope',
      });
      expect(
        utf8.decode(request.bodyBytes),
        golden('mutation-update-title').trimRight(),
      );
      expect(
        jsonDecode(utf8.decode(request.bodyBytes)),
        fixture('mutation-update-title'),
      );
      expect(request.headers['If-Match'], '"revision-1"');
      expect(request.headers['Content-Type'], 'application/json');
      expect(request.followRedirects, isFalse);
      expect(
        harness.requests.map((request) => request.headers['Authorization']),
        ['Bearer token-1', 'Bearer token-2', 'Bearer token-3'],
      );
      expect(receipt.outcome, 'updated');
      expect(receipt.revision, '2');
      expect(receipt.display!.resources.single.revision, '2');
      expect(receipt.retryCommand, isFalse);
      expect(harness.requests, hasLength(3));
    });

    test('should preserve every submitted UTF16 unit, order, omission and empty Text', () async {
      // Given leading/trailing space, newline, Japanese, a pair and isolated surrogates.
      final exact =
          ' \n日本😀${String.fromCharCode(0xd800)}${String.fromCharCode(0xdc00)} '
          '${String.fromCharCode(0xd800)}X${String.fromCharCode(0xdc00)}';
      final harness = Harness();
      addTearDown(harness.close);
      await harness.prepare();
      // When description then title are sent, including an empty description.
      await harness.update(
        changes: [
          const CncfDisplayTextChange(description, ''),
          CncfDisplayTextChange(title, exact),
        ],
      );
      final bytes = harness.requests.last.bodyBytes;
      final body = jsonDecode(utf8.decode(bytes)) as Map;
      // Then exact code units and caller order survive escaped ASCII before UTF8 encoding.
      expect(bytes.every((unit) => unit < 128), isTrue);
      expect(body['changes'].map((dynamic field) => field['fieldId']), [
        'description',
        'title',
      ]);
      expect(body['changes'][0]['value']['text'], '');
      expect(
        (body['changes'][1]['value']['text'] as String).codeUnits,
        exact.codeUnits,
      );
      await harness.update();
      expect(
        (jsonDecode(harness.requests.last.body) as Map)['changes'],
        hasLength(1),
      );
      expect(
        harness.requests.where((request) => request.method == 'PUT'),
        hasLength(2),
      );
    });

    test(
      'should retain unchanged receipt for an equal current submission',
      () async {
        // Given an equal submitted title and an unchanged receipt at the original revision.
        final harness = Harness(
          updateReply: (_) async => rawReply(
            wireResult(
              result(outcome: 'unchanged', revision: '1'),
              revision: '1',
            ),
          ),
        );
        addTearDown(harness.close);
        await harness.prepare();
        // When the caller submits exact current Text, Then Core keeps the unchanged receipt.
        final receipt = await harness.update(
          changes: const [CncfDisplayTextChange(title, '日本の民話')],
        );
        expect(receipt.outcome, 'unchanged');
        expect(receipt.revision, harness.observation.resources.single.revision);
        expect(harness.requests, hasLength(3));
      },
    );

    for (final flag in [
      'hidden',
      'system',
      'readonly',
      'multiple',
      'editability',
      'kind',
      'support',
      'availability',
      'hiddenAvailability',
    ]) {
      test('should veto current $flag independently before dispatch', () async {
        // Given an explicitly bound field with one current veto or unsupported operation.
        final data = fixture('mutation-descriptor');
        final first = (data['fields']! as List).first;
        if (flag == 'editability') {
          first['editability'] = 'read-only';
        } else if (flag == 'kind') {
          first['acceptedKinds'] = ['number'];
        } else if (flag == 'support') {
          (data['capabilities']! as Map)['update'] = 'unsupported';
        } else if (flag == 'availability' || flag == 'hiddenAvailability') {
          (data['availability']! as Map)['update'] = flag == 'availability'
              ? 'disabled'
              : 'hidden';
        } else {
          first['web'][flag] = true;
        }
        final harness = Harness(descriptorData: data);
        addTearDown(harness.close);
        await harness.prepare();
        if (flag == 'editability') {
          expect(harness.descriptor.fields.first.bindingId, 'write.title');
        }
        // When Text update admission runs, Then no PUT or authorization lookup follows.
        await expectLater(
          harness.update(),
          throwsA(isA<CncfDisplayReadException>()),
        );
        expect(harness.requests, hasLength(2));
      });
    }

    test('should reject missing configuration, unknown, readonly and duplicate changes locally', () async {
      // Given a legacy read profile without a mutation pin and a configured descriptor owner.
      final legacy = Harness(selectedProfile: profile(mutationRevision: null));
      final harness = Harness();
      addTearDown(legacy.close);
      addTearDown(harness.close);
      // When mutation is requested without its pin, Then HTTP is never attempted.
      await expectLater(
        legacy.service.describeMutation(),
        throwsA(code('mutationUnconfigured')),
      );
      expect(legacy.requests, isEmpty);
      await harness.prepare();
      for (final changes in [
        <CncfDisplayTextChange>[],
        const [
          CncfDisplayTextChange(CncfDisplayFieldLocator('other', 'title'), 'x'),
        ],
        const [
          CncfDisplayTextChange(CncfDisplayFieldLocator('main', 'stage'), 'x'),
        ],
        const [
          CncfDisplayTextChange(title, 'x'),
          CncfDisplayTextChange(title, 'y'),
        ],
      ]) {
        // When a local changeset lacks a unique writable bound Text field.
        // Then the entire changeset rejects before physical dispatch.
        await expectLater(
          harness.update(changes: changes),
          throwsA(isA<CncfDisplayReadException>()),
        );
      }
      expect(harness.requests, hasLength(2));
      expect(
        () => profile(mutationRevision: ''),
        throwsA(isA<CncfDisplayReadException>()),
      );
    });

    test(
      'should reject a foreign descriptor and List observation before dispatch',
      () async {
        // Given a genuine descriptor admitted against a different pinned definition.
        final otherData = fixture('mutation-descriptor');
        (otherData['definition']! as Map)['mutationRevision'] =
            'other-revision';
        final other = Harness(
          descriptorData: otherData,
          selectedProfile: profile(mutationRevision: 'other-revision'),
        );
        final harness = Harness();
        addTearDown(other.close);
        addTearDown(harness.close);
        await other.prepare();
        await harness.prepare();
        // When descriptor authority or formal Detail selection is mismatched.
        // Then source-compatible public objects cannot bypass update admission.
        await expectLater(
          harness.service.update(
            descriptor: other.descriptor,
            observation: harness.observation,
            changes: const [CncfDisplayTextChange(title, 'x')],
          ),
          throwsA(code('definitionMismatch')),
        );
        final list = CncfDisplayRead.decode(
          fixture('list-initial'),
          profile(),
          detail: false,
        );
        await expectLater(
          harness.service.update(
            descriptor: harness.descriptor,
            observation: list,
            changes: const [CncfDisplayTextChange(title, 'x')],
          ),
          throwsA(isA<CncfDisplayReadException>()),
        );
        expect(harness.requests, hasLength(2));
      },
    );
  });

  group('receipts and lexical admission', () {
    final integerLocations = <String, void Function(Map<String, Object?>)>{
      'read version': (wire) => wire['version'] = '@integer-token@',
      'ABI version': (wire) =>
          (wire['abi']! as Map)['version'] = '@integer-token@',
      'semantic version': (wire) =>
          (wire['semanticContract']! as Map)['version'] = '@integer-token@',
      'context envelope version': (wire) =>
          (wire['presentationContext']! as Map)['version'] = '@integer-token@',
      'known context family version': (wire) =>
          ((wire['presentationContext']! as Map)['families']
                  as List)[0]['version'] =
              '@integer-token@',
      'unknown context family version': (wire) =>
          ((wire['presentationContext']! as Map)['families']
                  as List)[1]['version'] =
              '@integer-token@',
    };
    for (final location in integerLocations.entries) {
      for (final spelling in ['1.0', '1e0']) {
        for (final detail in [false, true]) {
          test(
            'should reject raw ${location.key} $spelling in standalone ${detail ? 'read' : 'query'} without publishing context',
            () async {
              // Given a valid current flow and a raw read with one noninteger structural token.
              final currentContext = fixture('context-variant-ja');
              final current = fixture('detail-initial')
                ..['presentationContext'] = currentContext;
              final candidateContext = fixture('context-locale-ja');
              (candidateContext['families']! as List).add({
                'name': 'example.optional',
                'version': 1,
                'data': <String, Object?>{},
              });
              final candidate = fixture(
                detail ? 'detail-initial' : 'list-initial',
              )..['presentationContext'] = candidateContext;
              location.value(candidate);
              final raw = jsonEncode({'data': candidate})
                  .replaceFirst('"@integer-token@"', spelling);
              var reads = 0;
              final harness = Harness(
                detailReply: (_) async =>
                    ++reads == 2 ? rawReply(raw) : reply(current),
              );
              addTearDown(harness.close);
              await harness.prepare();
              // When the real client receives the malformed read, Then no observation is admitted.
              await expectLater(
                detail
                    ? harness.service.read(resourceId)
                    : harness.service.query(),
                throwsA(code('integerLiteralInvalid', unknown: false)),
              );
              expect(harness.requests, hasLength(3));
              // When a later read is explicit, Then only the previous valid context is carried.
              await harness.service.read(resourceId);
              expect(harness.requests, hasLength(4));
              expect(
                jsonDecode(
                  harness.requests.last.headers['X-CNCF-Presentation-Context']!,
                ),
                currentContext,
              );
            },
          );
        }

        test(
          'should reject raw Ready ${location.key} $spelling as unknown without replay or context publication',
          () async {
            // Given a valid observation and Ready bytes with one noninteger nested structural token.
            final currentContext = fixture('context-variant-ja');
            final current = fixture('detail-initial')
              ..['presentationContext'] = currentContext;
            final candidateContext = fixture('context-locale-ja');
            (candidateContext['families']! as List).add({
              'name': 'example.optional',
              'version': 1,
              'data': <String, Object?>{},
            });
            final wire = result(context: candidateContext)
              ..remove('presentationContext');
            location.value(
              (wire['projection']! as Map)['display'] as Map<String, Object?>,
            );
            final raw = wireResult(wire)
                .replaceFirst('"@integer-token@"', spelling);
            final harness = Harness(
              detailData: current,
              updateReply: (_) async => rawReply(raw),
            );
            addTearDown(harness.close);
            await harness.prepare();
            // When the dispatched acknowledgement is decoded, Then no receipt is admitted or replayed.
            await expectLater(
              harness.update(),
              throwsA(code('integerLiteralInvalid', unknown: true)),
            );
            expect(harness.requests, hasLength(3));
            expect(
              harness.requests.where((request) => request.method == 'PUT'),
              hasLength(1),
            );
            // When a later read is explicit, Then rejected Ready context has never replaced the flow.
            await harness.service.read(resourceId);
            expect(harness.requests, hasLength(4));
            expect(
              jsonDecode(
                harness.requests.last.headers['X-CNCF-Presentation-Context']!,
              ),
              currentContext,
            );
          },
        );
      }
    }

    for (final location in ['envelope', 'known family', 'unknown family']) {
      for (final spelling in ['1.0', '1e0']) {
        test(
          'should reject raw outer context $location version $spelling without publishing or replaying',
          () async {
            // Given a valid flow and Pending receipt whose outer context has a noninteger version.
            final currentContext = fixture('context-variant-ja');
            final current = fixture('detail-initial')
              ..['presentationContext'] = currentContext;
            final candidateContext = fixture('context-locale-ja');
            final families = candidateContext['families']! as List;
            families.add({
              'name': 'example.optional',
              'version': 1,
              'data': <String, Object?>{},
            });
            if (location == 'envelope') {
              candidateContext['version'] = '@integer-token@';
            } else {
              families[location == 'known family' ? 0 : 1]['version'] =
                  '@integer-token@';
            }
            final raw = wireResult(
              result(pending: 'view-not-current', context: candidateContext),
            ).replaceFirst('"@integer-token@"', spelling);
            final harness = Harness(
              detailData: current,
              updateReply: (_) async => rawReply(raw),
            );
            addTearDown(harness.close);
            await harness.prepare();
            // When the dispatched response is decoded, Then the malformed acknowledgement remains unknown.
            await expectLater(
              harness.update(),
              throwsA(code('integerLiteralInvalid', unknown: true)),
            );
            expect(harness.requests, hasLength(3));
            expect(
              harness.requests.where((request) => request.method == 'PUT'),
              hasLength(1),
            );
            // When a safe read is explicitly requested, Then the current valid context is still carried.
            await harness.service.read(resourceId);
            expect(harness.requests, hasLength(4));
            expect(
              jsonDecode(
                harness.requests.last.headers['X-CNCF-Presentation-Context']!,
              ),
              currentContext,
            );
          },
        );
      }
    }

    for (final source in ['read', 'query', 'Ready', 'Pending']) {
      test(
        'should admit $source with inert optional-family numeric data beyond Int limits',
        () async {
          // Given valid structural integer versions and unknown data with unrelated numeric properties.
          final supported = fixture('context-locale-ja');
          final context = fixture('context-locale-ja');
          (context['families']! as List).add({
            'name': 'example.optional',
            'version': 1,
            'data': {
              'large': '@large-number@',
              'fraction': '@fraction@',
              'numericString': '9007199254740993',
              'version': '@data-version@',
              'abi': {'version': '@data-abi-version@'},
              'empty': null,
            },
          });
          String rawNumbers(String raw) => raw
              .replaceFirst('"@large-number@"', '9007199254740993')
              .replaceFirst('"@fraction@"', '1.0')
              .replaceFirst('"@data-version@"', '1e0')
              .replaceFirst('"@data-abi-version@"', '1.0');
          final standalone = source == 'read' || source == 'query';
          final wire = result(
            context: context,
            pending: source == 'Pending' ? 'view-not-current' : null,
          );
          if (source == 'Ready') wire.remove('presentationContext');
          final harness = Harness(
            detailReply: (request) async {
              final detail = fixture(
                request.url.path.endsWith('query.json')
                    ? 'list-initial'
                    : 'detail-initial',
              );
              if (standalone) detail['presentationContext'] = context;
              return rawReply(rawNumbers(jsonEncode({'data': detail})));
            },
            updateReply: (_) async => rawReply(rawNumbers(wireResult(wire))),
          );
          addTearDown(harness.close);
          await harness.prepare();
          // When ordinary data decoding completes, Then valid observations or receipts remain usable.
          if (standalone) {
            final observed = source == 'query'
                ? await harness.service.query()
                : harness.observation;
            expect(observed.presentationContext, supported);
            expect(observed.resources, isNotEmpty);
          } else {
            final receipt = await harness.update();
            expect(receipt.revision, '2');
            expect(
              receipt.presentationContext,
              source == 'Pending' ? supported : null,
            );
            expect(
              receipt.display?.presentationContext,
              source == 'Ready' ? supported : null,
            );
            expect(harness.requests, hasLength(3));
          }
          // When another safe read is explicit, Then only supported families enter its canonical carrier.
          await harness.service.read(resourceId);
          expect(
            jsonDecode(
              harness.requests.last.headers['X-CNCF-Presentation-Context']!,
            ),
            supported,
          );
        },
      );
    }

    for (final mutation in <String, void Function(Map<String, Object?>)>{
      'created outcome': (wire) => wire['outcome'] = 'created',
      'deleted outcome': (wire) => wire['outcome'] = 'deleted',
      'retry true': (wire) => wire['retryCommand'] = true,
      'retry string': (wire) => wire['retryCommand'] = 'false',
      'outer source': (wire) => wire['componentId'] = 'foreign',
      'outer definition': (wire) =>
          (wire['definition']! as Map)['mutationRevision'] = 'foreign',
      'resource ID': (wire) =>
          (wire['resource']! as Map)['entityId'] = 'foreign',
      'nested source': (wire) =>
          (wire['projection']! as Map)['display']['componentId'] = 'foreign',
      'nested ID': (wire) =>
          (wire['projection']!
                  as Map)['display']['model']['resource']['entityId'] =
              'foreign',
      'nested revision': (wire) =>
          (wire['projection']!
                  as Map)['display']['model']['resource']['revision'] =
              '1',
      'projection tag': (wire) =>
          (wire['projection']! as Map)['type'] = 'reload-list',
      'projection extra': (wire) =>
          (wire['projection']! as Map)['reason'] = 'view-not-current',
      'null context': (wire) => wire['presentationContext'] = null,
      'context disagreement': (wire) =>
          wire['presentationContext'] = fixture('context-locale-ja'),
    }.entries) {
      test(
        'should reject ${mutation.key} as an unknown dispatched acknowledgement',
        () async {
          // Given a success acknowledgement that violates the original request or projection.
          final wire = result();
          mutation.value(wire);
          final harness = Harness(
            updateReply: (_) async => rawReply(wireResult(wire)),
          );
          addTearDown(harness.close);
          await harness.prepare();
          // When acknowledgement admission runs, Then no receipt or automatic reload is fabricated.
          await expectLater(
            harness.update(),
            throwsA(
              isA<CncfDisplayReadException>().having(
                (error) => error.outcomeUnknown,
                'outcome unknown',
                isTrue,
              ),
            ),
          );
          expect(harness.requests, hasLength(3));
        },
      );
    }

    for (final revision in ['9007199254740993', '9223372036854775807']) {
      test(
        'should retain exact raw Long $revision without machine-number recovery',
        () async {
          // Given an original canonical String observation immediately before a raw Long receipt.
          final observed = (BigInt.parse(revision) - BigInt.one).toString();
          final detail = fixture('detail-initial');
          ((detail['model']! as Map)['resource'] as Map)['revision'] = observed;
          final harness = Harness(
            detailData: detail,
            updateReply: (_) async => rawReply(
              wireResult(result(revision: revision), revision: revision),
            ),
          );
          addTearDown(harness.close);
          await harness.prepare();
          // When exact raw JSON is consumed, Then receipt/Ready/header retain all decimal digits.
          final receipt = await harness.update();
          expect(receipt.revision, revision);
          expect(receipt.display!.resources.single.revision, revision);
          expect(
            harness.requests.last.headers['If-Match'],
            '"revision-$observed"',
          );
        },
      );
    }

    for (final spelling in [
      '2.0',
      '2e0',
      '"2"',
      '02',
      '0',
      '-1',
      '9223372036854775808',
    ]) {
      test(
        'should reject raw noncanonical receipt revision $spelling',
        () async {
          // Given actual raw revision syntax, never jsonEncode of a rounded double.
          final harness = Harness(
            updateReply: (_) async =>
                rawReply(wireResult(result(), revision: spelling)),
          );
          addTearDown(harness.close);
          await harness.prepare();
          // When the result parser reads the token, Then no numeric-equivalence fallback admits it.
          await expectLater(
            harness.update(),
            throwsA(isA<CncfDisplayReadException>()),
          );
          expect(harness.requests, hasLength(3));
        },
      );
    }

    test('should reject wrong receipt arithmetic, lexical versions, duplicates and malformed JSON', () async {
      // Given raw success inputs that violate unchanged/next revision or lexical integrity.
      final raws = [
        wireResult(result(), revision: '1'),
        wireResult(result(outcome: 'unchanged'), revision: '2'),
        wireResult(result()).replaceFirst('"version":1', '"version":1.0'),
        wireResult(result()).replaceFirst('"version":1', '"version":1e0'),
        wireResult(result()).replaceFirst(
          '"retryCommand":false',
          '"retryCommand":true,"retryCommand":false',
        ),
        wireResult(
          result(),
        ).replaceFirst('"entityId":', r'"\u0065ntityId":"foreign","entityId":'),
        '{"data":',
        '[${'[' * 65}0${']' * 65}]',
      ];
      for (final raw in raws) {
        final harness = Harness(updateReply: (_) async => rawReply(raw));
        addTearDown(harness.close);
        await harness.prepare();
        // When update acknowledgement admission runs, Then the dispatched outcome remains unknown.
        await expectLater(
          harness.update(),
          throwsA(
            isA<CncfDisplayReadException>().having(
              (error) => error.outcomeUnknown,
              'outcome unknown',
              isTrue,
            ),
          ),
        );
        expect(harness.requests, hasLength(3));
      }
    });

    test(
      'should reject updated overflow but admit unchanged at Long maximum',
      () async {
        // Given an original observation already at the positive Long maximum.
        final detail = fixture('detail-initial');
        ((detail['model']! as Map)['resource'] as Map)['revision'] =
            '9223372036854775807';
        final harness = Harness(
          detailData: detail,
          updateReply: (_) async => rawReply(
            wireResult(
              result(revision: '9223372036854775807'),
              revision: '9223372036854775807',
            ),
          ),
        );
        final unchanged = Harness(
          detailData: detail,
          updateReply: (_) async => rawReply(
            wireResult(
              result(outcome: 'unchanged', revision: '9223372036854775807'),
              revision: '9223372036854775807',
            ),
          ),
        );
        addTearDown(harness.close);
        addTearDown(unchanged.close);
        await harness.prepare();
        await unchanged.prepare();
        // When the server claims an increment or exact no-op, Then only no-op has valid arithmetic.
        await expectLater(
          harness.update(),
          throwsA(code('receiptRevisionInvalid', unknown: true)),
        );
        expect((await unchanged.update()).revision, '9223372036854775807');
      },
    );

    for (final pending in ['view-not-current', 'projection-unavailable']) {
      test(
        'should retain $pending receipt and current flow without implicit I/O',
        () async {
          // Given an admitted flow and a committed Pending acknowledgement omitting context.
          final context = fixture('context-variant-ja');
          final detail = fixture('detail-initial')
            ..['presentationContext'] = context;
          final harness = Harness(
            detailData: detail,
            updateReply: (_) async =>
                rawReply(wireResult(result(pending: pending))),
          );
          addTearDown(harness.close);
          await harness.prepare();
          // When Pending is received, Then the receipt survives and omitted context is not a reset.
          final receipt = await harness.update();
          expect(receipt.revision, '2');
          expect(receipt.pendingReason, pending);
          expect(receipt.display, isNull);
          expect(receipt.presentationContext, isNull);
          expect(receipt.reloadRequired, isTrue);
          expect(receipt.retryCommand, isFalse);
          expect(harness.requests, hasLength(3));
          await harness.service.read(resourceId);
          expect(
            jsonDecode(
              harness.requests.last.headers['X-CNCF-Presentation-Context']!,
            ),
            context,
          );
        },
      );
    }

    test('should adopt explicit outer or Ready nested context through the same generic flow', () async {
      // Given genuine read/context goldens and exact matching acknowledgement contexts.
      for (final outer in [false, true]) {
        final context = fixture('context-locale-ja');
        final wire = result(context: context);
        if (!outer) wire.remove('presentationContext');
        final harness = Harness(
          updateReply: (_) async => rawReply(wireResult(wire)),
        );
        addTearDown(harness.close);
        await harness.prepare();
        // When Ready is admitted, Then future safe reads carry the selected generic context.
        final receipt = await harness.update();
        expect(receipt.presentationContext, outer ? context : null);
        expect(receipt.display!.presentationContext, context);
        await harness.service.read(resourceId);
        expect(
          jsonDecode(
            harness.requests.last.headers['X-CNCF-Presentation-Context']!,
          ),
          context,
        );
      }
    });

    test('should adopt an outer Pending context and clear continuation on context-free Ready', () async {
      // Given a current flow and either an explicit Pending context or a context-free Ready.
      for (final pending in [true, false]) {
        final context = fixture('context-locale-ja');
        final original = fixture('detail-initial')
          ..['presentationContext'] = fixture('context-variant-ja');
        final wire = pending
            ? result(pending: 'view-not-current', context: context)
            : result();
        final harness = Harness(
          detailData: original,
          updateReply: (_) async => rawReply(wireResult(wire)),
        );
        addTearDown(harness.close);
        await harness.prepare();
        // When acknowledgement context is consumed, Then the next explicit read carries its exact meaning.
        final receipt = await harness.update();
        expect(receipt.presentationContext, pending ? context : null);
        await harness.service.read(resourceId);
        expect(
          jsonDecode(
            harness.requests.last.headers['X-CNCF-Presentation-Context']!,
          ),
          pending ? context : {'version': 1, 'families': []},
        );
      }
    });
  });

  group('structured rejection', () {
    test('should retain exact taxonomy, diagnostic and ordered facets without message semantics', () async {
      // Given a controlled Conclusion wire following the selected server observation contract.
      final facets = [
        {'type': 'reason', 'reason': 'first'},
        {'type': 'reason', 'reason': 'second'},
      ];
      final conclusion = {
        'status': {'code': 400},
        'observation': {
          'taxonomy': {'category': 'argument', 'symptom': 'invalid'},
          'cause': {
            'diagnostic': {
              'code': 'DSP96_MUTATION_VALUE_INVALID',
              'path': 'capture-detail/main/title',
            },
            'facets': facets,
          },
        },
        'interpretation': <String, Object?>{},
        'disposition': <String, Object?>{},
      };
      final harness = Harness(
        updateReply: (_) async => rawReply(
          jsonEncode({
            'error': {
              'message': 'private-test-token: internal detail',
              'conclusion': conclusion,
            },
          }),
          status: 422,
        ),
      );
      addTearDown(harness.close);
      await harness.prepare();
      // When the command receives an exact requested-field diagnostic.
      // Then only structured taxonomy/code/path yields an editable rejection; status stays separate.
      try {
        await harness.update();
        fail('Expected structured rejection');
      } on CncfDisplayReadException catch (error) {
        expect(error.statusCode, 422);
        expect(error.outcomeUnknown, isFalse);
        final failure = error.failure!;
        expect(failure.conclusion.keys, conclusion.keys);
        expect(failure.conclusion['observation'], conclusion['observation']);
        expect(
          failure.conclusion['interpretation'],
          conclusion['interpretation'],
        );
        expect(failure.conclusion['disposition'], conclusion['disposition']);
        expect(
          CncfDisplayFailure.numberLexeme(
            (failure.conclusion['status']! as Map)['code'],
          ),
          '400',
        );
        expect(failure.category, 'argument');
        expect(failure.symptom, 'invalid');
        expect(failure.diagnosticCode, 'DSP96_MUTATION_VALUE_INVALID');
        expect(failure.diagnosticPath, 'capture-detail/main/title');
        expect(failure.facets, facets);
        expect(failure.fieldLocator, title);
        expect(failure.isEditableRejection, isTrue);
        expect(failure.reconciliationRequired, isFalse);
        expect(
          () => (failure.facets.first! as Map)['reason'] = 'altered',
          throwsUnsupportedError,
        );
        expect(error.toString(), isNot(contains('private-test-token')));
        expect(failure.toString(), isNot(contains('internal')));
      }
      expect(harness.requests, hasLength(3));
    });

    for (final taxonomy in [
      ('operation', 'conflict'),
      ('argument', 'invalid'),
      ('state', 'invalid'),
    ]) {
      test(
        'should use taxonomy ${taxonomy.$1}/${taxonomy.$2} instead of HTTP 409 or message text',
        () async {
          // Given status 409 and a misleading message, with a nonrequested diagnostic path.
          final harness = Harness(
            updateReply: (_) async => rawReply(
              jsonEncode({
                'error': {
                  'message': 'operation conflict DSP96_MUTATION_VALUE_INVALID',
                  'conclusion': {
                    'observation': {
                      'taxonomy': {
                        'category': taxonomy.$1,
                        'symptom': taxonomy.$2,
                      },
                      'cause': {
                        'facets': [],
                        'diagnostic': {
                          'code': 'DSP96_MUTATION_VALUE_INVALID',
                          'path': 'capture-detail/main/description',
                        },
                      },
                    },
                  },
                },
              }),
              status: 409,
            ),
          );
          addTearDown(harness.close);
          await harness.prepare();
          // When rejection is received, Then conflict comes only from taxonomy and reconciliation remains required.
          try {
            await harness.update();
            fail('Expected failure');
          } on CncfDisplayReadException catch (error) {
            expect(
              error.failure!.isConflict,
              taxonomy.$1 == 'operation' && taxonomy.$2 == 'conflict',
            );
            expect(error.failure!.isEditableRejection, isFalse);
            expect(error.failure!.reconciliationRequired, isTrue);
            expect(error.statusCode, 409);
          }
        },
      );
    }

    test('should treat status-only and malformed failure envelopes as indeterminate', () async {
      // Given unstructured HTTP conflict and duplicate diagnostic members.
      for (final raw in [
        'private-test-token',
        '{"error":{"conclusion":{"observation":{"taxonomy":{"category":"argument","category":"operation"}}}}}',
      ]) {
        final harness = Harness(
          updateReply: (_) async => rawReply(raw, status: 409),
        );
        addTearDown(harness.close);
        await harness.prepare();
        // When no structured Conclusion can be admitted, Then no conflict/value outcome is inferred.
        try {
          await harness.update();
          fail('Expected failure');
        } on CncfDisplayReadException catch (error) {
          expect(error.failure, isNull);
          expect(error.outcomeUnknown, isTrue);
          expect(error.toString(), 'CncfDisplayReadException(httpRejected)');
        }
      }
    });

    test('should require the approved diagnostic code even at a requested field path', () async {
      // Given argument/invalid and the requested title path with an unapproved diagnostic code.
      final harness = Harness(
        updateReply: (_) async => rawReply(
          jsonEncode({
            'error': {
              'conclusion': {
                'observation': {
                  'taxonomy': {'category': 'argument', 'symptom': 'invalid'},
                  'cause': {
                    'facets': [],
                    'diagnostic': {
                      'code': 'PRIVATE_OTHER_CODE',
                      'path': 'capture-detail/main/title',
                    },
                  },
                },
              },
            },
          }),
          status: 400,
        ),
      );
      addTearDown(harness.close);
      await harness.prepare();
      // When the failure is admitted, Then its data survives but editable rejection is vetoed.
      try {
        await harness.update();
        fail('Expected failure');
      } on CncfDisplayReadException catch (error) {
        expect(error.failure!.diagnosticCode, 'PRIVATE_OTHER_CODE');
        expect(error.failure!.fieldLocator, isNull);
        expect(error.failure!.reconciliationRequired, isTrue);
      }
    });

    test('should retain every raw Conclusion number token and ordered nested facet without coercion', () async {
      // Given raw Conclusion Longs beyond JS precision, decimals, exponents and a distinct numeric String.
      const raw = r'''
{
  "error": {
    "message": "private-test-token: internal message",
    "conclusion": {
      "status": {"code":409},
      "observation": {
        "taxonomy": {"category":"operation","symptom":"conflict"},
        "cause": {
          "facets": [
            {"reason":"expected","expected":9007199254740993},
            {"reason":"actual","actual":9223372036854775807},
            {
              "reason":"metadata",
              "decimal":-0.0100,
              "exponent":1.2300e+400,
              "numericString":"9007199254740993",
              "nested":[9007199254740993,{"exponent":2E-9}]
            }
          ]
        }
      }
    }
  }
}
''';
      final harness = Harness(
        updateReply: (_) async => rawReply(raw, status: 409),
      );
      addTearDown(harness.close);
      await harness.prepare();
      // When the command receives the structured failure, Then exact token spelling and facet order survive.
      try {
        await harness.update();
        fail('Expected failure');
      } on CncfDisplayReadException catch (error) {
        final failure = error.failure!;
        final facets = failure.facets;
        expect(facets.map((facet) => (facet! as Map)['reason']), [
          'expected',
          'actual',
          'metadata',
        ]);
        expect(
          CncfDisplayFailure.numberLexeme((facets[0]! as Map)['expected']),
          '9007199254740993',
        );
        expect(
          CncfDisplayFailure.numberLexeme((facets[1]! as Map)['actual']),
          '9223372036854775807',
        );
        final metadata = facets[2]! as Map;
        expect(CncfDisplayFailure.numberLexeme(metadata['decimal']), '-0.0100');
        expect(
          CncfDisplayFailure.numberLexeme(metadata['exponent']),
          '1.2300e+400',
        );
        expect(metadata['numericString'], isA<String>());
        expect(metadata['numericString'], '9007199254740993');
        expect(
          CncfDisplayFailure.numberLexeme(metadata['numericString']),
          isNull,
        );
        expect(CncfDisplayFailure.numberLexeme(null), isNull);
        expect(CncfDisplayFailure.numberLexeme(true), isNull);
        expect(CncfDisplayFailure.numberLexeme(1), isNull);
        final nested = metadata['nested'] as List;
        expect(CncfDisplayFailure.numberLexeme(nested[0]), '9007199254740993');
        expect(
          CncfDisplayFailure.numberLexeme((nested[1] as Map)['exponent']),
          '2E-9',
        );
        expect(() => nested.add('altered'), throwsUnsupportedError);
        expect(
          () => (nested[1] as Map)['exponent'] = 'altered',
          throwsUnsupportedError,
        );
        expect(
          () => failure.conclusion['status'] = 'altered',
          throwsUnsupportedError,
        );
        expect(
          CncfDisplayFailure.numberLexeme(
            (failure.conclusion['status']! as Map)['code'],
          ),
          '409',
        );
        expect(error.statusCode, 409);
        expect(error.outcomeUnknown, isFalse);
        expect(failure.isConflict, isTrue);
        expect(failure.reconciliationRequired, isTrue);
        expect(error.toString(), isNot(contains('private-test-token')));
        expect(failure.toString(), isNot(contains('internal message')));
      }
      expect(harness.requests, hasLength(3));
    });
  });

  group('command ownership and retirement', () {
    test('should reserve a command during token wait and allow safe reads after terminal receipt', () async {
      // Given an update whose per-request credentials have not completed.
      final heldToken = Completer<String?>();
      var tokens = 0;
      final harness = Harness(
        token: () => ++tokens == 3 ? heldToken.future : Future.value('token'),
      );
      addTearDown(harness.close);
      await harness.prepare();
      // When update is called without awaiting it, Then every competing operation rejects busy.
      final command = harness.update();
      await expectLater(
        harness.service.read(resourceId),
        throwsA(code('busy')),
      );
      await expectLater(harness.service.query(), throwsA(code('busy')));
      await expectLater(
        harness.service.describeMutation(),
        throwsA(code('busy')),
      );
      await expectLater(harness.update(), throwsA(code('busy')));
      expect(harness.requests, hasLength(2));
      heldToken.complete('token');
      await command;
      // Then explicit safe reload becomes available after command terminal, without automatic replay.
      await harness.service.read(resourceId);
      expect(harness.requests.map((request) => request.method), [
        'GET',
        'GET',
        'PUT',
        'GET',
      ]);
    });

    test('should retire an earlier safe GET while preserving ordinary GET supersession', () async {
      // Given a held safe read followed by a command, then two independently held safe reads.
      final firstRead = Completer<http.Response>();
      final firstStarted = Completer<void>();
      final secondRead = Completer<http.Response>();
      final secondStarted = Completer<void>();
      var readCalls = 0;
      final transport = MockClient((request) async {
        if (request.url.path.endsWith('describeMutation.json')) {
          return reply(fixture('mutation-descriptor'));
        }
        if (request.method == 'PUT') return rawReply(wireResult(result()));
        readCalls++;
        if (readCalls == 2) {
          firstStarted.complete();
          return firstRead.future;
        }
        if (readCalls == 3) {
          secondStarted.complete();
          return secondRead.future;
        }
        return reply(fixture('detail-initial'));
      });
      final service = CncfDisplayReadClient(
        profile: profile(),
        endpoint: Uri.parse('https://studio.test/'),
        client: transport,
        bearerToken: () async => 'token',
      );
      addTearDown(() {
        service.dispose();
        transport.close();
      });
      final descriptor = await service.describeMutation();
      final observation = await service.read(resourceId);
      final old = service.read(resourceId);
      final oldExpectation = expectLater(old, throwsA(code('superseded')));
      await firstStarted.future;
      // When update replaces the safe GET, Then its late response cannot publish.
      await service.update(
        descriptor: descriptor,
        observation: observation,
        changes: const [CncfDisplayTextChange(title, 'x')],
      );
      firstRead.complete(reply(fixture('detail-initial')));
      await oldExpectation;
      final replaced = service.read(resourceId);
      final replacedExpectation = expectLater(
        replaced,
        throwsA(code('superseded')),
      );
      await secondStarted.future;
      final current = await service.read(resourceId);
      secondRead.complete(reply(fixture('detail-initial')));
      // Then safe GET supersession still works and current publication remains valid.
      await replacedExpectation;
      expect(current.resources.single.entityId, resourceId);
    });

    for (final retire in ['timeout', 'dispose']) {
      test(
        'should mark dispatched $retire unknown, cancel its body and never publish late context',
        () async {
          // Given a command with headers received but a held body subscription.
          final heldBody = StreamController<List<int>>();
          final sent = Completer<void>();
          var calls = 0;
          var cancelled = false;
          heldBody.onCancel = () {
            cancelled = true;
          };
          final transport = MockClient.streaming((request, stream) async {
            calls++;
            if (request.method == 'PUT') {
              sent.complete();
              return http.StreamedResponse(
                heldBody.stream,
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            final data = request.url.path.endsWith('describeMutation.json')
                ? fixture('mutation-descriptor')
                : fixture('detail-initial');
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({'data': data}))),
              200,
              headers: {'content-type': 'application/json'},
            );
          });
          final service = CncfDisplayReadClient(
            profile: profile(),
            endpoint: Uri.parse('https://studio.test/'),
            client: transport,
            bearerToken: () async => 'token',
            timeout: const Duration(milliseconds: 40),
          );
          addTearDown(() {
            service.dispose();
            transport.close();
          });
          final descriptor = await service.describeMutation();
          final observation = await service.read(resourceId);
          // When an admitted command times out or its flow is disposed during response delivery.
          final command = service.update(
            descriptor: descriptor,
            observation: observation,
            changes: const [CncfDisplayTextChange(title, 'x')],
          );
          final expectation = expectLater(
            command,
            throwsA(
              isA<CncfDisplayReadException>().having(
                (error) => error.outcomeUnknown,
                'outcome unknown',
                isTrue,
              ),
            ),
          );
          await sent.future;
          await Future<void>.delayed(Duration.zero);
          await expectLater(service.query(), throwsA(code('busy')));
          if (retire == 'dispose') service.dispose();
          await expectation;
          await Future<void>.delayed(Duration.zero);
          // Then actual subscription cancellation prevents late receipt/context and any implicit replay.
          expect(cancelled, isTrue);
          heldBody.add(
            utf8.encode(
              wireResult(result(context: fixture('context-locale-ja'))),
            ),
          );
          await heldBody.close();
          expect(calls, 3);
          if (retire == 'timeout') {
            await service.read(resourceId);
            expect(calls, 4);
          }
        },
      );
    }

    test('should prevent dispatch after token timeout or disposal and redact provider failures', () async {
      // Given a command token that arrives only after timeout/disposal, or a throwing provider.
      for (final retire in ['timeout', 'dispose', 'throw']) {
        final held = Completer<String?>();
        var tokens = 0;
        final harness = Harness(
          token: () {
            if (++tokens < 3) return Future.value('token');
            if (retire == 'throw') throw StateError('private-test-token');
            return held.future;
          },
          timeout: const Duration(milliseconds: 30),
        );
        addTearDown(harness.close);
        await harness.prepare();
        // When pre-dispatch ownership retires, Then no unknown write or late command is claimed.
        final command = harness.update();
        final expectation = expectLater(
          command,
          throwsA(
            isA<CncfDisplayReadException>()
                .having(
                  (error) => error.outcomeUnknown,
                  'outcome unknown',
                  isFalse,
                )
                .having(
                  (error) => error.toString().contains('private-test-token'),
                  'redaction',
                  isFalse,
                ),
          ),
        );
        if (retire == 'dispose') {
          harness.service.dispose();
          held.complete('late-token');
        }
        await expectation;
        if (retire == 'timeout') held.complete('late-token');
        await Future<void>.delayed(Duration.zero);
        expect(harness.requests, hasLength(2));
      }
    });

    test('should retire a timed out sent command and discard its late header response', () async {
      // Given a PUT whose response headers remain held beyond the bounded exchange.
      final held = Completer<http.Response>();
      final sent = Completer<void>();
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          sent.complete();
          return held.future;
        }
        return reply(
          request.url.path.endsWith('describeMutation.json')
              ? fixture('mutation-descriptor')
              : fixture('detail-initial'),
        );
      });
      final service = CncfDisplayReadClient(
        profile: profile(),
        endpoint: Uri.parse('https://studio.test/'),
        client: transport,
        bearerToken: () async => 'token',
        timeout: const Duration(milliseconds: 40),
      );
      addTearDown(() {
        service.dispose();
        transport.close();
      });
      final descriptor = await service.describeMutation();
      final observation = await service.read(resourceId);
      // When timeout retires a dispatched command and an explicit safe read starts afterward.
      final command = service.update(
        descriptor: descriptor,
        observation: observation,
        changes: const [CncfDisplayTextChange(title, 'x')],
      );
      final expectation = expectLater(
        command,
        throwsA(code('timeout', unknown: true)),
      );
      await sent.future;
      await expectLater(service.describeMutation(), throwsA(code('busy')));
      await expectation;
      await service.read(resourceId);
      held.complete(
        rawReply(wireResult(result(context: fixture('context-locale-ja')))),
      );
      await Future<void>.delayed(Duration.zero);
      // Then late context never publishes, no automatic retry occurs, and new reads remain explicit.
      await service.read(resourceId);
      expect(
        requests.where((request) => request.method == 'PUT'),
        hasLength(1),
      );
      expect(
        jsonDecode(requests.last.headers['X-CNCF-Presentation-Context']!),
        {'version': 1, 'families': []},
      );
    });

    test('should keep connection failure unknown and leave explicit safe reads available', () async {
      // Given a dispatched command whose peer fails without an acknowledgement.
      final harness = Harness(
        updateReply: (_) async => throw StateError('private-test-token'),
      );
      addTearDown(harness.close);
      await harness.prepare();
      // When the connection fails, Then Core neither retries nor synthesizes a receipt.
      await expectLater(
        harness.update(),
        throwsA(code('invalidResponseOrConnection', unknown: true)),
      );
      expect(harness.requests, hasLength(3));
      await harness.service.read(resourceId);
      expect(harness.requests, hasLength(4));
    });

    test('should bound dispatched bodies and reject invalid content type without retry', () async {
      // Given a sent command with either an oversized body or a non-JSON success response.
      for (final oversized in [true, false]) {
        final harness = Harness(
          updateReply: (_) async => oversized
              ? rawReply('x' * 262145)
              : http.Response.bytes(
                  utf8.encode(wireResult(result())),
                  200,
                  headers: {'content-type': 'text/plain'},
                ),
        );
        addTearDown(harness.close);
        await harness.prepare();
        // When bounded exchange admission fails, Then outcome is unknown and no follow-up is sent.
        await expectLater(
          harness.update(),
          throwsA(
            code(
              oversized ? 'responseTooLarge' : 'contentTypeInvalid',
              unknown: true,
            ),
          ),
        );
        expect(harness.requests, hasLength(3));
      }
    });
  });
}
