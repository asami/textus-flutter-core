import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

// The read inputs are the genuine accepted producer fixtures. Ordinary ACKs
// below are controlled responses from the selected service's three-member contract.
Map<String, Object?> fixture(String name) => Map<String, Object?>.from(
  jsonDecode(
    File('test/fixtures/cncf_display_reference_v1/$name.json')
        .readAsStringSync(),
  ) as Map,
);

final initial = fixture('detail-initial');
final resourceId =
    ((initial['model']! as Map)['resource'] as Map)['entityId']! as String;

CncfDisplayReadProfile profile({String? mutationRevision}) =>
    CncfDisplayReadProfile(
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

CncfDisplayBusinessBinding binding({
  String componentId = 'org.simplemodeling.textus.EditingStudio',
  String actionId = 'request-review',
  String bindingId = 'ess.reference.request-review',
  String service = 'reference-business',
  String operation = 'requestReview',
  String expectedOutcome = 'review-requested',
  int revisionIncrement = 1,
}) => CncfDisplayBusinessBinding(
  componentId: componentId,
  actionId: actionId,
  bindingId: bindingId,
  service: service,
  operation: operation,
  expectedOutcome: expectedOutcome,
  revisionIncrement: revisionIncrement,
);

Map<String, Object?> detail({
  String? id,
  String revision = '1',
  void Function(Map<String, Object?>)? change,
}) {
  final wire = fixture('detail-initial');
  final resource = (wire['model']! as Map)['resource'] as Map;
  resource['entityId'] = id ?? resourceId;
  resource['revision'] = revision;
  change?.call(wire);
  return wire;
}

CncfDisplayRead observation({
  String? id,
  String revision = '1',
  void Function(Map<String, Object?>)? change,
}) => CncfDisplayRead.decode(
  detail(id: id, revision: revision, change: change),
  profile(),
  detail: true,
  expectedResourceId: id ?? resourceId,
);

String acknowledgement({
  String? id,
  String revision = '2',
  String outcome = 'review-requested',
}) =>
    '{"data":{"resourceId":${jsonEncode(id ?? resourceId)},'
    '"revision":$revision,"outcome":${jsonEncode(outcome)}}}';

http.Response rawReply(String raw, {int status = 200}) => http.Response.bytes(
  utf8.encode(raw),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Matcher errorCode(String code, {bool unknown = false}) =>
    isA<CncfDisplayReadException>()
        .having((error) => error.code, 'redacted code', code)
        .having((error) => error.outcomeUnknown, 'outcome unknown', unknown);

final class Harness {
  Harness({
    Future<http.Response> Function(http.Request)? respond,
    Future<String?> Function()? token,
    Duration timeout = const Duration(seconds: 2),
    CncfDisplayReadProfile? selectedProfile,
  }) {
    transport = MockClient((request) async {
      requests.add(request);
      if (respond != null) return respond(request);
      if (request.method == 'POST') return rawReply(acknowledgement());
      return rawReply(
        jsonEncode({
          'data': fixture(
            request.url.path.endsWith('describeMutation.json')
                ? 'mutation-descriptor'
                : 'detail-initial',
          ),
        }),
      );
    });
    service = CncfDisplayReadClient(
      profile: selectedProfile ?? profile(),
      endpoint: Uri.parse('https://studio.test/rest/v1/editing-studio/'),
      client: transport,
      bearerToken: () {
        tokens++;
        return token?.call() ?? Future.value('private-business-token');
      },
      timeout: timeout,
    );
  }
  final requests = <http.Request>[];
  int tokens = 0;
  late final http.Client transport;
  late final CncfDisplayReadClient service;
  Future<CncfDisplayBusinessResult> invoke({
    CncfDisplayRead? selected,
    CncfDisplayBusinessBinding? configured,
  }) => service.invokeBusiness(
    binding: configured ?? binding(),
    observation: selected ?? observation(),
  );
  void close() {
    service.dispose();
    transport.close();
  }
}

void main() {
  group('trusted ordinary Business binding', () {
    for (final invalid in <String, CncfDisplayBusinessBinding Function()>{
      'empty component': () => binding(componentId: ''),
      'untrimmed component': () => binding(componentId: ' component'),
      'control component': () => binding(componentId: 'component\n'),
      'empty action': () => binding(actionId: ''),
      'untrimmed action': () => binding(actionId: 'request-review '),
      'control action': () => binding(actionId: 'request\u007freview'),
      'empty binding': () => binding(bindingId: ''),
      'untrimmed binding': () => binding(bindingId: ' binding'),
      'control binding': () => binding(bindingId: 'binding\t'),
      'empty outcome': () => binding(expectedOutcome: ''),
      'untrimmed outcome': () => binding(expectedOutcome: ' review-requested'),
      'control outcome': () =>
          binding(expectedOutcome: 'review\u0000requested'),
      'empty service': () => binding(service: ''),
      'service traversal': () => binding(service: '../reference-business'),
      'service URL': () => binding(service: 'https://elsewhere.test'),
      'service query': () => binding(service: 'reference?target=x'),
      'numeric service start': () => binding(service: '1reference'),
      'underscore service': () => binding(service: 'reference_business'),
      'empty operation': () => binding(operation: ''),
      'operation traversal': () => binding(operation: '../requestReview'),
      'hyphen operation': () => binding(operation: 'request-review'),
      'operation query': () => binding(operation: 'requestReview?x=y'),
      'zero increment': () => binding(revisionIncrement: 0),
      'negative increment': () => binding(revisionIncrement: -1),
      'overflow increment': () => binding(revisionIncrement: 2147483648),
    }.entries) {
      test('should reject ${invalid.key} as invalid trusted configuration', () {
        // Given an independently supplied invalid configuration value.
        final construct = invalid.value;
        // When the immutable binding is constructed, Then configuration fails consistently.
        expect(construct, throwsArgumentError);
      });
    }

    test('should send exactly one ordinary form POST and retain a separate receipt', () async {
      // Given a genuine formal Detail and independent binding, without mutation authority.
      final harness = Harness();
      addTearDown(harness.close);
      final selectedBinding = binding();
      // When the enabled ordinary operation is invoked.
      final receipt = await harness.invoke(configured: selectedBinding);
      // Then no descriptor, query, read or retry was implicitly sent.
      expect(harness.tokens, 1);
      expect(harness.requests, hasLength(1));
      final request = harness.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/rest/v1/editing-studio/reference-business/requestReview.json',
      );
      expect(request.url.queryParameters, {'textus.output.shape': 'envelope'});
      expect(request.url.query, 'textus.output.shape=envelope');
      expect(
        request.body,
        'resourceId=fixture-display-entity-ec1_7_fixture_7_display_7_Capture-1800000000000-projection_resource_1',
      );
      expect(
        request.headers['Content-Type'],
        'application/x-www-form-urlencoded;charset=utf-8',
      );
      expect(request.headers['If-Match'], '"revision-1"');
      expect(request.headers['Authorization'], 'Bearer private-business-token');
      expect(request.headers['Accept'], 'application/json');
      expect(request.followRedirects, isFalse);
      expect(jsonDecode(request.headers['X-CNCF-Presentation-Context']!), {
        'version': 1,
        'families': [],
      });
      expect(receipt.binding, same(selectedBinding));
      expect(receipt.resourceId, resourceId);
      expect(receipt.revision, '2');
      expect(receipt.outcome, 'review-requested');
      expect(harness.service.profile.mutationRevision, isNull);
    });

    for (final increment in [2, 2147483647]) {
      test(
        'should apply the trusted one-resource increment $increment',
        () async {
          // Given a command with its own independently declared increment contract.
          final expected = increment == 2 ? '3' : '2147483648';
          final harness = Harness(
            respond: (_) async => rawReply(acknowledgement(revision: expected)),
          );
          addTearDown(harness.close);
          // When its strict ordinary receipt matches that contract.
          final receipt = await harness.invoke(
            configured: binding(revisionIncrement: increment),
          );
          // Then the exact expected revision is retained and the observed precondition stays original.
          expect(receipt.revision, expected);
          expect(harness.requests.single.headers['If-Match'], '"revision-1"');
        },
      );
    }
  });

  group('pre-dispatch authority and observation', () {
    for (final invalid
        in <String, (CncfDisplayBusinessBinding, CncfDisplayRead, String)>{
          'component': (
            binding(componentId: 'foreign'),
            observation(),
            'sourceMismatch',
          ),
          'action': (
            binding(actionId: 'other'),
            observation(),
            'businessBindingMismatch',
          ),
          'binding': (
            binding(bindingId: 'other'),
            observation(),
            'businessBindingMismatch',
          ),
          'missing action': (
            binding(),
            observation(
              change: (wire) => (wire['model']! as Map)['actions'] = [],
            ),
            'businessBindingMismatch',
          ),
          'disabled action': (
            binding(),
            observation(
              change: (wire) =>
                  ((wire['model']! as Map)['actions'] as List)
                          .single['availability'] =
                      'disabled',
            ),
            'businessUnavailable',
          ),
          'hidden action': (
            binding(),
            observation(
              change: (wire) =>
                  ((wire['model']! as Map)['actions'] as List)
                          .single['availability'] =
                      'hidden',
            ),
            'businessUnavailable',
          ),
          'Long maximum': (
            binding(),
            observation(revision: '9223372036854775807'),
            'revisionInvalid',
          ),
          'increment overflow': (
            binding(revisionIncrement: 2),
            observation(revision: '9223372036854775806'),
            'revisionInvalid',
          ),
        }.entries) {
      test(
        'should reject ${invalid.key} before credentials or transport',
        () async {
          // Given an admitted formal observation and an independently failing command predicate.
          final harness = Harness();
          addTearDown(harness.close);
          // When that command is requested, Then it fails locally with a known unexecuted outcome.
          await expectLater(
            harness.invoke(
              configured: invalid.value.$1,
              selected: invalid.value.$2,
            ),
            throwsA(errorCode(invalid.value.$3)),
          );
          // Then neither token lookup nor dispatch occurred.
          expect(harness.tokens, 0);
          expect(harness.requests, isEmpty);
        },
      );
    }

    test(
      'should re-admit the observation against the selected profile',
      () async {
        // Given a Detail admitted by another independently selected definition revision.
        final foreign = fixture('detail-initial');
        (foreign['definition']! as Map)['revision'] = 'another-definition';
        final otherProfile = CncfDisplayReadProfile(
          componentId: profile().componentId,
          resourceType: profile().resourceType,
          listScreenId: profile().listScreenId,
          detailScreenId: profile().detailScreenId,
          definitionRevision: 'another-definition',
          semanticContract: profile().semanticContract,
          provenance: profile().provenance,
        );
        final selected = CncfDisplayRead.decode(
          foreign,
          otherProfile,
          detail: true,
          expectedResourceId: resourceId,
        );
        final harness = Harness();
        addTearDown(harness.close);
        // When the foreign observation reaches this client's command boundary.
        await expectLater(
          harness.invoke(selected: selected),
          throwsA(errorCode('definitionMismatch')),
        );
        // Then matching resource/action strings cannot bypass the full selected profile.
        expect(harness.tokens, 0);
        expect(harness.requests, isEmpty);
      },
    );

    for (final empty in [false, true]) {
      test(
        'should reject ${empty ? 'empty' : 'populated'} List observations',
        () async {
          // Given a real formal List rather than one selected Detail resource.
          final wire = fixture('list-initial');
          if (empty) (wire['model']! as Map)['items'] = [];
          final selected = CncfDisplayRead.decode(
            wire,
            profile(),
            detail: false,
          );
          final harness = Harness();
          addTearDown(harness.close);
          // When the ordinary command is requested from that List.
          await expectLater(
            harness.invoke(selected: selected),
            throwsA(isA<CncfDisplayReadException>()),
          );
          // Then no implicit selection, token or request is manufactured.
          expect(harness.tokens, 0);
          expect(harness.requests, isEmpty);
        },
      );
    }

    for (final revision in <Object?>[
      '0',
      '01',
      '-1',
      '1.0',
      '1e0',
      '9223372036854775808',
      1,
      true,
      null,
    ]) {
      test(
        'should reject nonformal observation revision $revision before dispatch',
        () async {
          // Given controlled invalid revision input on the genuine Detail baseline.
          final wire = detail();
          ((wire['model']! as Map)['resource'] as Map)['revision'] = revision;
          final harness = Harness();
          addTearDown(harness.close);
          // When admission is attempted before invoking the command.
          await expectLater(
            Future.sync(
              () => harness.invoke(
                selected: CncfDisplayRead.decode(
                  wire,
                  profile(),
                  detail: true,
                  expectedResourceId: resourceId,
                ),
              ),
            ),
            throwsA(isA<CncfDisplayReadException>()),
          );
          // Then a noncanonical or non-String observation never reaches authentication.
          expect(harness.tokens, 0);
          expect(harness.requests, isEmpty);
        },
      );
    }
  });

  group('exact identity and raw ordinary acknowledgement', () {
    test(
      'should preserve Unicode pairs, plus, space, percent and form delimiters',
      () async {
        // Given an exact admitted identity with multibyte characters and form metacharacters.
        const id = '日本📚+ %&=';
        final harness = Harness(
          respond: (_) async => rawReply(acknowledgement(id: id)),
        );
        addTearDown(harness.close);
        // When that identity is encoded as the sole ordinary form member.
        final receipt = await harness.invoke(selected: observation(id: id));
        // Then expected literal bytes and decoding preserve every original character.
        expect(
          harness.requests.single.body,
          'resourceId=%E6%97%A5%E6%9C%AC%F0%9F%93%9A%2B+%25%26%3D',
        );
        expect(Uri.splitQueryString(harness.requests.single.body), {
          'resourceId': id,
        });
        expect(receipt.resourceId, id);
      },
    );

    for (final id in [
      'prefix\ud800suffix',
      'prefix\udc00suffix',
      'prefix\ud800',
      'prefix\ud800\ud800',
      'prefix\udc00\ud800',
    ]) {
      test(
        'should reject isolated UTF16 units ${id.codeUnits} before token lookup',
        () async {
          // Given a formal String identity that UTF8 form encoding cannot carry losslessly.
          final harness = Harness();
          addTearDown(harness.close);
          final selected = observation(id: id);
          // When the command prepares its ordinary form.
          await expectLater(
            harness.invoke(selected: selected),
            throwsA(errorCode('identityInvalid')),
          );
          // Then no lossy replacement identity is ever dispatched.
          expect(harness.tokens, 0);
          expect(harness.requests, isEmpty);
        },
      );
    }

    for (final pair in [
      ('9007199254740991', '9007199254740992'),
      ('9007199254740992', '9007199254740993'),
      ('9223372036854775806', '9223372036854775807'),
    ]) {
      test('should retain raw Long receipt ${pair.$2} without numeric rounding', () async {
        // Given raw numeric JSON independent of ordinary JSON number decoding.
        final harness = Harness(
          respond: (_) async => rawReply(acknowledgement(revision: pair.$2)),
        );
        addTearDown(harness.close);
        // When a receipt at the trusted observed-plus-one boundary is admitted.
        final receipt = await harness.invoke(
          selected: observation(revision: pair.$1),
        );
        // Then both precondition and returned revision preserve exact decimal spelling.
        expect(receipt.revision, pair.$2);
        expect(
          harness.requests.single.headers['If-Match'],
          '"revision-${pair.$1}"',
        );
      });
    }

    final validData =
        '{"resourceId":${jsonEncode(resourceId)},'
        '"revision":2,"outcome":"review-requested"}';
    final invalidAcks = <String, String>{
      'wrong resource': acknowledgement(id: 'other'),
      'wrong outcome': acknowledgement(outcome: 'updated'),
      'unchanged revision': acknowledgement(revision: '1'),
      'skipped revision': acknowledgement(revision: '3'),
      'quoted revision': acknowledgement(revision: '"2"'),
      'bool revision': acknowledgement(revision: 'true'),
      'null revision': acknowledgement(revision: 'null'),
      'decimal revision': acknowledgement(revision: '2.0'),
      'exponent revision': acknowledgement(revision: '2e0'),
      'negative revision': acknowledgement(revision: '-2'),
      'zero revision': acknowledgement(revision: '0'),
      'leading-zero revision': acknowledgement(revision: '02'),
      'overflow revision': acknowledgement(revision: '9223372036854775808'),
      'rounded-looking revision': acknowledgement(revision: '9007199254740993'),
      'missing data': '{}',
      'null data': '{"data":null}',
      'array data': '{"data":[]}',
      'missing key':
          '{"data":{"resourceId":${jsonEncode(resourceId)},"revision":2}}',
      'null resource': '{"data":{"resourceId":null,"revision":2,"outcome":"review-requested"}}',
      'null outcome':
          '{"data":{"resourceId":${jsonEncode(resourceId)},"revision":2,"outcome":null}}',
      'nonstring resource':
          '{"data":{"resourceId":1,"revision":2,"outcome":"review-requested"}}',
      'nonstring outcome':
          '{"data":{"resourceId":${jsonEncode(resourceId)},"revision":2,"outcome":true}}',
      'extra Display':
          '{"data":${validData.replaceFirst('}', ',"display":{}}')}}',
      'extra projection':
          '{"data":${validData.replaceFirst('}', ',"projection":{}}')}}',
      'extra context':
          '{"data":${validData.replaceFirst('}', ',"presentationContext":{"version":1,"families":[]}}')}}',
      'unknown key':
          '{"data":${validData.replaceFirst('}', ',"extra":true}')}}',
      'duplicate escaped key':
          '{"data":${validData.replaceFirst('}', r',"\u0072evision":2}')}}',
      'duplicate envelope': '{"data":$validData,"data":$validData}',
      'malformed JSON': '{"data":',
      'trailing bytes': '{"data":$validData}private-provider-details',
    };
    for (final invalid in invalidAcks.entries) {
      test(
        'should reject ${invalid.key} without fabricating a receipt or replay',
        () async {
          // Given a controlled inadmissible raw ordinary acknowledgement.
          final harness = Harness(
            respond: (_) async => rawReply(invalid.value),
          );
          addTearDown(harness.close);
          // When one POST has already been dispatched, Then acknowledgement failure stays indeterminate.
          await expectLater(
            harness.invoke(),
            throwsA(
              isA<CncfDisplayReadException>()
                  .having(
                    (error) => error.outcomeUnknown,
                    'outcome unknown',
                    isTrue,
                  )
                  .having(
                    (error) => error.failure,
                    'no fabricated failure',
                    isNull,
                  )
                  .having(
                    (error) => error.toString(),
                    'redaction',
                    allOf(
                      isNot(contains('private-provider-details')),
                      isNot(contains('private-business-token')),
                    ),
                  ),
            ),
          );
          // Then no automatic POST retry or safe reload follows the rejected receipt.
          expect(harness.tokens, 1);
          expect(harness.requests.map((request) => request.method), ['POST']);
        },
      );
    }
  });

  group('shared context, authentication and failure policy', () {
    test('should retain current generic context across an ACK without context', () async {
      // Given an explicit read that establishes the generic continuation context.
      final context = fixture('context-locale-ja');
      final harness = Harness(
        respond: (request) async => request.method == 'POST'
            ? rawReply(acknowledgement())
            : rawReply(
                jsonEncode({
                  'data': detail(
                    change: (wire) => wire['presentationContext'] = context,
                  ),
                }),
              ),
      );
      addTearDown(harness.close);
      // When the read is explicitly requested by the caller.
      final selected = await harness.service.read(resourceId);
      // Then it supplies the original formal observation and supported context.
      expect(selected.presentationContext, context);
      // When Business returns only its ordinary acknowledgement.
      await harness.invoke(selected: selected);
      // Then the command carries the previously admitted generic header.
      expect(
        jsonDecode(harness.requests[1].headers['X-CNCF-Presentation-Context']!),
        context,
      );
      expect(harness.requests, hasLength(2));
      // When the caller explicitly reads again after that receipt.
      await harness.service.read(resourceId);
      // Then absent ACK context has retained that continuation without an implicit read.
      expect(
        jsonDecode(
          harness.requests.last.headers['X-CNCF-Presentation-Context']!,
        ),
        context,
      );
      expect(harness.requests.map((request) => request.method), [
        'GET',
        'POST',
        'GET',
      ]);
    });

    test('should look up a fresh bearer for each explicit Business request', () async {
      // Given a token provider that changes credentials between requests.
      var sequence = 0;
      final harness = Harness(token: () async => 'token-${++sequence}');
      addTearDown(harness.close);
      // When the caller explicitly invokes twice with independent observations.
      await harness.invoke();
      await harness.invoke();
      // Then each dispatch uses its own credential lookup and no implicit request exists.
      expect(
        harness.requests.map((request) => request.headers['Authorization']),
        ['Bearer token-1', 'Bearer token-2'],
      );
      expect(harness.tokens, 2);
    });

    test('should retain structural conflict on HTTP 400 without editable-field admission', () async {
      // Given a disclosed Conclusion whose taxonomy identifies conflict independently of HTTP status.
      final harness = Harness(
        respond: (_) async => rawReply(
          jsonEncode({
            'error': {
              'message': 'private-provider-details',
              'conclusion': {
                'observation': {
                  'taxonomy': {'category': 'operation', 'symptom': 'conflict'},
                  'cause': {
                    'facets': [
                      {'expected': 1, 'actual': 2},
                    ],
                    'diagnostic': {
                      'code': 'DSP96_MUTATION_VALUE_INVALID',
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
      // When the ordinary POST is rejected by that structured failure.
      await expectLater(
        harness.invoke(),
        throwsA(
          isA<CncfDisplayReadException>()
              .having((error) => error.statusCode, 'HTTP status', 400)
              .having(
                (error) => error.outcomeUnknown,
                'known rejected outcome',
                isFalse,
              )
              .having(
                (error) => error.failure!.isConflict,
                'taxonomy conflict',
                isTrue,
              )
              .having(
                (error) => error.failure!.isEditableRejection,
                'no requested fields',
                isFalse,
              )
              .having(
                (error) => error.failure!.fieldLocator,
                'no fabricated locator',
                isNull,
              )
              .having(
                (error) => error.failure!.reconciliationRequired,
                'reconcile',
                isTrue,
              )
              .having(
                (error) => error.failure!.facets,
                'retained facets',
                hasLength(1),
              )
              .having(
                (error) => error.toString(),
                'redacted exception',
                isNot(contains('private-provider-details')),
              )
              .having(
                (error) => error.failure.toString(),
                'redacted failure',
                isNot(contains('private-provider-details')),
              ),
        ),
      );
      // Then the rejected command has not replayed or implicitly read.
      expect(harness.requests.map((request) => request.method), ['POST']);
    });

    for (final stage in ['provider', 'connection']) {
      test('should redact $stage failures and preserve dispatch classification', () async {
        // Given a private provider/transport throwable before or after dispatch.
        final harness = Harness(
          token: stage == 'provider'
              ? () => throw StateError('private-provider-details')
              : null,
          respond: (_) async => throw StateError('private-provider-details'),
        );
        addTearDown(harness.close);
        // When the configured failure interrupts one command.
        await expectLater(
          harness.invoke(),
          throwsA(
            isA<CncfDisplayReadException>()
                .having(
                  (error) => error.outcomeUnknown,
                  'dispatch classification',
                  stage == 'connection',
                )
                .having(
                  (error) => error.toString(),
                  'provider redaction',
                  isNot(contains('private-provider-details')),
                ),
          ),
        );
        // Then only an actually sent command is counted and nothing is retried.
        expect(harness.requests, hasLength(stage == 'connection' ? 1 : 0));
      });
    }
  });

  group('ordinary Business shares exclusive command ownership', () {
    for (final stage in ['token', 'send', 'body']) {
      test(
        'should reject GET, update and Business before token lookup while $stage is held',
        () async {
          // Given the same command owner with a real descriptor and a finite held exchange stage.
          final tokenGate = Completer<String?>();
          final sendGate = Completer<http.StreamedResponse>();
          final bodyGate = StreamController<List<int>>();
          final entered = Completer<void>();
          var tokens = 0;
          var sends = 0;
          final transport = MockClient.streaming((request, stream) async {
            sends++;
            if (request.method != 'POST') {
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    jsonEncode({'data': fixture('mutation-descriptor')}),
                  ),
                ),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (stage != 'token') entered.complete();
            if (stage == 'send') return sendGate.future;
            return http.StreamedResponse(
              stage == 'body'
                  ? bodyGate.stream
                  : Stream.value(utf8.encode(acknowledgement())),
              200,
              headers: {'content-type': 'application/json'},
            );
          });
          final service = CncfDisplayReadClient(
            profile: profile(mutationRevision: 'ess-reference-mutation-1'),
            endpoint: Uri.parse('https://studio.test/'),
            client: transport,
            bearerToken: () {
              tokens++;
              if (stage == 'token' && tokens == 2) {
                entered.complete();
                return tokenGate.future;
              }
              return Future.value('token');
            },
          );
          addTearDown(() {
            service.dispose();
            transport.close();
          });
          // When the caller explicitly obtains the separate update descriptor.
          final descriptor = await service.describeMutation();
          // Then it has consumed exactly one token and safe exchange.
          expect(tokens, 1);
          expect(sends, 1);
          // When Business reserves ownership synchronously and waits at the selected stage.
          final command = service.invokeBusiness(
            binding: binding(),
            observation: observation(),
          );
          await entered.future;
          // Then every competing entry point rejects before it can obtain another token.
          await expectLater(service.query(), throwsA(errorCode('busy')));
          await expectLater(
            service.read(resourceId),
            throwsA(errorCode('busy')),
          );
          await expectLater(
            service.describeMutation(),
            throwsA(errorCode('busy')),
          );
          await expectLater(
            service.update(
              descriptor: descriptor,
              observation: observation(),
              changes: const [
                CncfDisplayTextChange(
                  CncfDisplayFieldLocator('main', 'title'),
                  'changed',
                ),
              ],
            ),
            throwsA(errorCode('busy')),
          );
          await expectLater(
            service.invokeBusiness(
              binding: binding(),
              observation: observation(),
            ),
            throwsA(errorCode('busy')),
          );
          expect(tokens, 2);
          expect(sends, stage == 'token' ? 1 : 2);
          // When the finite held stage releases its ordinary acknowledgement.
          if (stage == 'token') tokenGate.complete('token');
          if (stage == 'send') {
            sendGate.complete(
              http.StreamedResponse(
                Stream.value(utf8.encode(acknowledgement())),
                200,
                headers: {'content-type': 'application/json'},
              ),
            );
          }
          if (stage == 'body') {
            bodyGate.add(utf8.encode(acknowledgement()));
            await bodyGate.close();
          }
          final receipt = await command;
          // Then only the original Business command completed, with no competitor or replay.
          expect(receipt.revision, '2');
          expect(tokens, 2);
          expect(sends, 2);
          // When a caller explicitly starts another safe exchange after terminal receipt.
          await service.describeMutation();
          // Then the shared reservation has released normally.
          expect(tokens, 3);
          expect(sends, 3);
        },
      );
    }

    test('should reserve ownership before reentrant credential-provider calls', () async {
      // Given a provider that synchronously reenters Core during token lookup.
      late Harness harness;
      final reentrant = <Future<void>>[];
      harness = Harness(
        token: () {
          reentrant.add(
            expectLater(harness.service.query(), throwsA(errorCode('busy'))),
          );
          reentrant.add(
            expectLater(harness.invoke(), throwsA(errorCode('busy'))),
          );
          return Future.value('token');
        },
      );
      addTearDown(harness.close);
      // When the outer ordinary command starts.
      final receipt = await harness.invoke();
      await Future.wait(reentrant);
      // Then reentrancy cannot replace or duplicate the command or recursively look up credentials.
      expect(receipt.revision, '2');
      expect(harness.tokens, 1);
      expect(harness.requests.map((request) => request.method), ['POST']);
    });

    for (final retire in ['timeout', 'dispose']) {
      test('should prevent late dispatch after token $retire', () async {
        // Given an ordinary command whose credentials remain held before dispatch.
        final tokenGate = Completer<String?>();
        final harness = Harness(
          token: () => tokenGate.future,
          timeout: const Duration(milliseconds: 50),
        );
        addTearDown(harness.close);
        // When timeout or disposal retires the command before credentials arrive.
        final command = harness.invoke();
        final rejected = expectLater(
          command,
          throwsA(
            isA<CncfDisplayReadException>().having(
              (error) => error.outcomeUnknown,
              'not dispatched',
              isFalse,
            ),
          ),
        );
        if (retire == 'dispose') harness.service.dispose();
        await rejected;
        // Then retirement has produced neither a receipt nor a transport request.
        expect(harness.requests, isEmpty);
        // When late credentials arrive after that terminal failure.
        tokenGate.complete('late-token');
        await Future<void>.delayed(Duration.zero);
        // Then the retired command cannot dispatch with those credentials.
        expect(harness.requests, isEmpty);
        expect(harness.tokens, 1);
      });
    }

    for (final stage in ['send', 'body']) {
      for (final retire in ['timeout', 'dispose']) {
        test(
          'should keep sent $stage $retire unknown and leave the borrowed client alive',
          () async {
            // Given a dispatched ordinary command with finite held headers or body.
            final entered = Completer<void>();
            final sendGate = Completer<http.StreamedResponse>();
            final bodyGate = StreamController<List<int>>();
            var cancelled = false;
            bodyGate.onCancel = () {
              cancelled = true;
            };
            final methods = <String>[];
            final transport = MockClient.streaming((request, stream) async {
              methods.add(request.method);
              if (request.method == 'POST') {
                entered.complete();
                if (stage == 'send') return sendGate.future;
                return http.StreamedResponse(
                  bodyGate.stream,
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.StreamedResponse(
                Stream.value(utf8.encode('{"alive":true}')),
                200,
              );
            });
            final service = CncfDisplayReadClient(
              profile: profile(),
              endpoint: Uri.parse('https://studio.test/'),
              client: transport,
              bearerToken: () async => 'token',
              timeout: const Duration(milliseconds: 50),
            );
            addTearDown(() {
              service.dispose();
              transport.close();
            });
            // When the single command reaches the selected held transport stage.
            final command = service.invokeBusiness(
              binding: binding(),
              observation: observation(),
            );
            final rejected = expectLater(
              command,
              throwsA(
                isA<CncfDisplayReadException>().having(
                  (error) => error.outcomeUnknown,
                  'sent outcome unknown',
                  isTrue,
                ),
              ),
            );
            await entered.future;
            await Future<void>.delayed(Duration.zero);
            // Then even a body wait still excludes competing safe reads.
            await expectLater(service.query(), throwsA(errorCode('busy')));
            // When timeout or disposal retires the sent command.
            if (retire == 'dispose') service.dispose();
            await rejected;
            await Future<void>.delayed(Duration.zero);
            // Then a held subscribed body is cancelled without an authoritative receipt.
            if (stage == 'body') expect(cancelled, isTrue);
            expect(methods, ['POST']);
            // When late headers/body arrive with an otherwise valid ordinary receipt.
            if (stage == 'send') {
              sendGate.complete(
                http.StreamedResponse(
                  Stream.value(utf8.encode(acknowledgement())),
                  200,
                  headers: {'content-type': 'application/json'},
                ),
              );
            } else {
              bodyGate.add(utf8.encode(acknowledgement()));
              await bodyGate.close();
            }
            await Future<void>.delayed(Duration.zero);
            // Then there is no automatic POST retry or implicit safe read.
            expect(methods, ['POST']);
            // When the caller disposes the Core flow and independently uses its borrowed client.
            service.dispose();
            final alive = await transport.get(
              Uri.parse('https://studio.test/borrowed-owner'),
            );
            // Then Core disposal has preserved the caller-owned HTTP client.
            expect(alive.body, '{"alive":true}');
            expect(methods, ['POST', 'GET']);
            // When the disposed Core flow is asked to invoke again, Then it rejects locally.
            await expectLater(
              service.invokeBusiness(
                binding: binding(),
                observation: observation(),
              ),
              throwsA(errorCode('disposed')),
            );
          },
        );
      }
    }
  });
}
