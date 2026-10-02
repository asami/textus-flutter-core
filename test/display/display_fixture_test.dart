import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('fixture decoding and immutable mappings', () {
    test('generic fixture decodes named contexts responses and uninterpreted mappings', () {
      // Given neutral inline data owned by this specification, with no app paths.
      final wire = fixtureWire();
      // When the public generic fixture codec roundtrips.
      final fixture = DisplayPrototypeFixture.fromJson(wire);
      final roundtrip = DisplayPrototypeFixture.fromJson(fixture.toJson());
      // Then named typed consumers decode and semantic mappings remain data.
      expect(roundtrip.contextFor('neutral'), neutralContext());
      expect(
        DisplayListResponse.fromJson(fixture.displayResponse('list'))
            .data
            .model
            .items
            .single
            .resourceId,
        'r',
      );
      expect(
        DisplayDetailResponse.fromJson(fixture.displayResponse('detail'))
            .data
            .sourceRevision,
        1,
      );
      expect(
        DisplayMutationResponse.fromJson(fixture.displayResponse('mutation'))
            .result
            .outcome,
        DisplayCommandOutcome.unsupported,
      );
      expect(
        OrdinaryOperationResponse.fromJson(
          fixture.operationResponse('operation'),
        ).result.committedRevision,
        2,
      );
      expect(fixture.semanticSeed, [
        {'resourceId': 'r', 'sourceRevision': 1},
      ]);
      expect(fixture.operationBindings, {
        'neutral-operation': {
          'inputFields': ['resourceId'],
        },
      });
    });

    test(
      'fixture getters reject missing IDs and all stored data is immutable',
      () {
        // Given mutable source mappings and response data.
        final wire = fixtureWire();
        final fixture = DisplayPrototypeFixture.fromJson(wire);
        // When caller mutates its input after decoding.
        (wire['semanticSeed'] as List).clear();
        (wire['contexts'] as Map).clear();
        // Then named lookup errors are explicit and stored views cannot be mutated.
        expect((fixture.semanticSeed as List).length, 1);
        expect(fixture.contextFor('neutral'), neutralContext());
        expect(() => fixture.contextFor('missing'), throwsStateError);
        expect(() => fixture.displayResponse('missing'), throwsStateError);
        expect(() => fixture.operationResponse('missing'), throwsStateError);
        expect(() => fixture.contexts.clear(), throwsUnsupportedError);
        expect(
          () => (fixture.semanticSeed as List).clear(),
          throwsUnsupportedError,
        );
        expect(
          () => (fixture.displayResponse('detail')['data'] as Map).clear(),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'fixture rejects closed schema reference and malformed response bodies',
      () {
        // Given malformed top-level, reference and response variants.
        final wrongReference = fixtureWire();
        wrongReference['reference'] = {
          'sampleId': 'neutral',
          'sampleRevision': 1,
          'provisionalVersion': 1,
          'developmentOnly': false,
        };
        final wrongRevision = fixtureWire();
        (wrongRevision['reference'] as Map)['sampleRevision'] = 1.0;
        final badResponse = fixtureWire();
        (badResponse['displayResponses'] as Map)['detail'] = {
          'schema': 'textus.display.prototype.v1',
          'kind': 'detail',
          'context': neutralContext().toJson(),
          'data': {},
        };
        final badOperation = fixtureWire();
        (badOperation['operationResponses'] as Map)['operation'] = {
          'schema': 'textus.operation.prototype.v1',
          'context': neutralContext().toJson(),
          'result': {},
          'data': {},
        };
        // When these fixture variants pass structural decoding.
        final actions = [
          () => DisplayPrototypeFixture.fromJson({
            ...fixtureWire(),
            'schema': 'wrong',
          }),
          () => DisplayPrototypeFixture.fromJson({
            ...fixtureWire(),
            'extra': true,
          }),
          () => DisplayPrototypeFixture.fromJson(
            {...fixtureWire()}..remove('semanticSeed'),
          ),
          () => DisplayPrototypeFixture.fromJson(wrongReference),
          () => DisplayPrototypeFixture.fromJson(wrongRevision),
          () => DisplayPrototypeFixture.fromJson(badResponse),
          () => DisplayPrototypeFixture.fromJson(badOperation),
        ];
        // Then no invalid envelope or production reference is usable.
        for (final action in actions) {
          expect(action, throwsFormatException);
        }
      },
    );

    test('fixture collections enforce independent byte depth and finite JSON bounds', () {
      // Given the exact 65536-byte mapping and excess/non-JSON/deep alternatives.
      final boundary = fixtureWire()..['semanticSeed'] = {'x': 'a' * 65528};
      final deep = <String, Object?>{'leaf': true};
      Map<String, Object?> nested = deep;
      for (var index = 0; index < 16; index++) {
        nested = {'next': nested};
      }
      final invalid = [
        fixtureWire()..['semanticSeed'] = {'x': 'a' * 65529},
        fixtureWire()..['projectionBindings'] = nested,
        fixtureWire()..['operationBindings'] = {'x': double.infinity},
        fixtureWire()..['semanticSeed'] = {'x': DateTime.utc(2026)},
        fixtureWire()..['semanticSeed'] = 'scalar',
      ];
      // When each collection independently decodes.
      final decoded = DisplayPrototypeFixture.fromJson(boundary);
      // Then the exact byte bound is accepted and all excess/invalid inputs reject.
      expect((decoded.semanticSeed as Map)['x'], 'a' * 65528);
      for (final wire in invalid) {
        expect(
          () => DisplayPrototypeFixture.fromJson(wire),
          throwsFormatException,
        );
      }
    });
  });

  group('Display request contracts', () {
    test('all Display methods record exact typed wire context and transport revision', () async {
      // Given immutable typed requests with repeated scoped inputs.
      final input = DisplayFieldInput(
        locator: DisplayFieldLocator(
          screenId: 'detail',
          sectionId: 'main',
          fieldId: 'title',
        ),
        value: const TextDisplayValue('semantic'),
      );
      final requests = <DisplayRequest>[
        DisplayQueryRequest(resourceType: 'neutral', metadata: metadata()),
        DisplayReadRequest(
          resourceType: 'neutral',
          resourceId: 'r',
          metadata: metadata(),
        ),
        DisplayUpdateRequest(
          resourceType: 'neutral',
          resourceId: 'r',
          fields: [input, input],
          metadata: metadata(revision: 1),
        ),
        DisplayCreateRequest(
          resourceType: 'neutral',
          fields: [input],
          metadata: metadata(),
        ),
        DisplayDeleteRequest(
          resourceType: 'neutral',
          resourceId: 'r',
          metadata: metadata(revision: 1),
        ),
      ];
      final fake = ScriptedDisplayTransport([
        for (final request in requests)
          ScriptedDisplayExchange(
            kind: request.kind,
            reply: ScriptedTransportReply.response({
              'method': request.kind.name,
            }),
          ),
      ]);
      final DisplayTransport port = fake;
      for (final request in requests) {
        // When the corresponding public raw port consumes a single exchange.
        final response = await invoke(port, request);
        final wire = request.toJson();
        final decoded = DisplayRequest.fromJson(wire);
        // Then observed requests and exact method-specific wire shapes are retained.
        expect(response['method'], request.kind.name);
        expect(decoded.toJson(), wire);
        expect(wire['schema'], 'textus.display.prototype.v1');
        expect(wire['resourceType'], 'neutral');
        expect(wire['metadata'], {
          'context': neutralContext().toJson(),
          'observedRevision': request.metadata.observedRevision,
        });
        expect(wire.keys.toSet(), {
          'schema',
          'kind',
          'resourceType',
          'metadata',
          if (request.kind != DisplayRequestKind.query &&
              request.kind != DisplayRequestKind.create)
            'resourceId',
          if (request.kind == DisplayRequestKind.update ||
              request.kind == DisplayRequestKind.create)
            'fields',
        });
        expect(fake.calls.last.request, same(request));
      }
      // Then all methods are recorded once and duplicate inputs remain representable.
      expect(fake.callCount, 5);
      expect((fake.calls[2].request as DisplayUpdateRequest).fields.length, 2);
      expect(
        DisplayFieldInput.fromJson(input.toJson()).toJson(),
        input.toJson(),
      );
      expect(() => fake.calls.clear(), throwsUnsupportedError);
    });

    test(
      'request revision placement and closed input shapes reject mismatches',
      () {
        // Given typed requests with forbidden/missing revision and malformed input shapes.
        final actions = [
          () => DisplayQueryRequest(
            resourceType: 'neutral',
            metadata: metadata(revision: 1),
          ),
          () => DisplayReadRequest(
            resourceType: 'neutral',
            resourceId: 'r',
            metadata: metadata(revision: 1),
          ),
          () => DisplayCreateRequest(
            resourceType: 'neutral',
            fields: [],
            metadata: metadata(revision: 1),
          ),
          () => DisplayUpdateRequest(
            resourceType: 'neutral',
            resourceId: 'r',
            fields: [],
            metadata: metadata(),
          ),
          () => DisplayDeleteRequest(
            resourceType: 'neutral',
            resourceId: 'r',
            metadata: metadata(),
          ),
          () => DisplayRequestMetadata(
            context: neutralContext(),
            observedRevision: 0,
          ),
          () => OrdinaryOperationRequest(
            operationId: 'op',
            resourceId: 'r',
            metadata: metadata(),
          ),
          () => DisplayRequest.fromJson({
            ...DisplayQueryRequest(
              resourceType: 'neutral',
              metadata: metadata(),
            ).toJson(),
            'extra': true,
          }),
          () => DisplayFieldInput.fromJson({
            'locator': {
              'screenId': 'detail',
              'sectionId': 'main',
              'fieldId': 'title',
            },
            'value': null,
          }),
          () => OrdinaryOperationRequest.fromJson({
            'schema': 'textus.operation.prototype.v1',
            'operationId': 'op',
            'input': {'resourceId': 'r', 'revision': 1},
            'metadata': metadata(revision: 1).toJson(),
          }),
        ];
        for (final action in actions) {
          Object? observedfailure;
          // When constructors or codecs process the mismatched requests.
          try {
            action();
          } catch (error) {
            observedfailure = error;
          }
          // Then revision remains transport metadata and all malformed shapes reject.
          expect(observedfailure, isA<FormatException>());
        }
      },
    );
  });

  group('scripted Display transport', () {
    test('independent fake instances have independent FIFO cursors', () async {
      // Given two instances constructed from the same external exchange list.
      final exchanges = [
        ScriptedDisplayExchange(
          kind: DisplayRequestKind.query,
          reply: ScriptedTransportReply.response({'step': 1}),
        ),
        ScriptedDisplayExchange(
          kind: DisplayRequestKind.read,
          reply: ScriptedTransportReply.response({'step': 2}),
        ),
      ];
      final first = ScriptedDisplayTransport(exchanges);
      final second = ScriptedDisplayTransport(exchanges);
      exchanges.clear();
      // When both query and only the first reads.
      final a = await first.query(
        DisplayQueryRequest(resourceType: 'neutral', metadata: metadata()),
      );
      final b = await second.query(
        DisplayQueryRequest(resourceType: 'neutral', metadata: metadata()),
      );
      final c = await first.read(
        DisplayReadRequest(
          resourceType: 'neutral',
          resourceId: 'r',
          metadata: metadata(),
        ),
      );
      // Then cursor advancement is local to each instance.
      expect(a, {'step': 1});
      expect(b, {'step': 1});
      expect(c, {'step': 2});
      expect(first.callCount, 2);
      expect(second.callCount, 1);
    });

    test(
      'unavailable and ambiguous failures record once without implicit retry',
      () async {
        // Given an unavailable read followed by an ambiguous update.
        const unavailable = DisplayTransportException(
          DisplayTransportFailure.unavailable,
          'offline',
        );
        const ambiguous = DisplayTransportException(
          DisplayTransportFailure.ambiguous,
          'receipt lost',
        );
        final fake = ScriptedDisplayTransport([
          const ScriptedDisplayExchange(
            kind: DisplayRequestKind.read,
            reply: ScriptedTransportReply.failure(unavailable),
          ),
          const ScriptedDisplayExchange(
            kind: DisplayRequestKind.update,
            reply: ScriptedTransportReply.failure(ambiguous),
          ),
        ]);
        // When raw calls consume their failure replies.
        final read = fake.read(
          DisplayReadRequest(
            resourceType: 'neutral',
            resourceId: 'r',
            metadata: metadata(),
          ),
        );
        // Then the exact failure is exposed after one recorded attempt.
        await expectLater(read, throwsA(same(unavailable)));
        expect(fake.callCount, 1);
        // When the ambiguous command is attempted.
        final update = fake.update(
          DisplayUpdateRequest(
            resourceType: 'neutral',
            resourceId: 'r',
            fields: [],
            metadata: metadata(revision: 1),
          ),
        );
        // Then no retry or reload is added by the fake.
        await expectLater(update, throwsA(same(ambiguous)));
        expect(fake.callCount, 2);
        expect(fake.calls.map((call) => call.kind), [
          DisplayRequestKind.read,
          DisplayRequestKind.update,
        ]);
      },
    );

    test('wrong method and exhausted fixtures are explicit recorded mismatches', () async {
      // Given a read exchange consumed by a query and an empty Operation port.
      final fake = ScriptedDisplayTransport([
        ScriptedDisplayExchange(
          kind: DisplayRequestKind.read,
          reply: ScriptedTransportReply.response({}),
        ),
      ]);
      final operation = ScriptedOrdinaryOperationTransport([]);
      // When an unexpected method or exhausted FIFO is called.
      final wrong = fake.query(
        DisplayQueryRequest(resourceType: 'neutral', metadata: metadata()),
      );
      // Then fixture mismatch is explicit and the attempt is recorded.
      await expectLater(
        wrong,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Fixture mismatch'),
          ),
        ),
      );
      await expectLater(
        fake.read(
          DisplayReadRequest(
            resourceType: 'neutral',
            resourceId: 'r',
            metadata: metadata(),
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        operation.execute(operationRequest()),
        throwsStateError,
      );
      expect(fake.callCount, 2);
      expect(operation.callCount, 1);
    });

    test(
      'scripted replies and recorded input retain defensive nested copies',
      () async {
        // Given external nested wire data and an external mutable input list.
        final list = <Object?>['original'];
        final wire = <String, Object?>{
          'nested': {'items': list},
        };
        final reply = ScriptedTransportReply.response(wire);
        final inputs = <DisplayFieldInput>[
          DisplayFieldInput(
            locator: DisplayFieldLocator(
              screenId: 'detail',
              sectionId: 'main',
              fieldId: 'title',
            ),
            value: const TextDisplayValue('original'),
          ),
        ];
        final request = DisplayUpdateRequest(
          resourceType: 'neutral',
          resourceId: 'r',
          fields: inputs,
          metadata: metadata(revision: 1),
        );
        final fake = ScriptedDisplayTransport([
          ScriptedDisplayExchange(
            kind: DisplayRequestKind.update,
            reply: reply,
          ),
        ]);
        // When external values mutate before and after raw playback.
        list.add('changed');
        wire.clear();
        inputs.clear();
        final returned = await fake.update(request);
        // Then response and recorded request remain deeply immutable and unchanged.
        expect(((returned['nested'] as Map)['items'] as List), ['original']);
        expect(
          (fake.calls.single.request as DisplayUpdateRequest)
              .fields
              .single
              .value,
          const TextDisplayValue('original'),
        );
        expect(
          () => ((returned['nested'] as Map)['items'] as List).clear(),
          throwsUnsupportedError,
        );
        expect(() => request.fields.clear(), throwsUnsupportedError);
        expect(
          () => ScriptedTransportReply.response({'x': Object()}),
          throwsFormatException,
        );
      },
    );
  });

  group('ordinary Operation and explicit Display reads', () {
    test(
      'ordinary Operation observation and explicit Display read are separate',
      () async {
        // Given one Operation receipt and a separate Detail FIFO.
        final fixture = DisplayPrototypeFixture.fromJson(fixtureWire());
        final operations = ScriptedOrdinaryOperationTransport([
          ScriptedTransportReply.response(
            fixture.operationResponse('operation'),
          ),
        ]);
        final display = ScriptedDisplayTransport([
          ScriptedDisplayExchange(
            kind: DisplayRequestKind.read,
            reply: ScriptedTransportReply.response(
              fixture.displayResponse('detail'),
            ),
          ),
        ]);
        final OrdinaryOperationTransport operationPort = operations;
        final request = operationRequest();
        // When only the ordinary Operation executes.
        final operation = OrdinaryOperationResponse.fromJson(
          await operationPort.execute(request),
        );
        // Then its input contains resource only and no Display call/reload occurs.
        expect(operation.result.committedRevision, 2);
        expect(request.toJson()['input'], {'resourceId': 'r'});
        expect(
          OrdinaryOperationRequest.fromJson(request.toJson()).toJson(),
          request.toJson(),
        );
        expect(operations.calls.single, same(request));
        expect(display.callCount, 0);
        expect(operation.toJson().containsKey('data'), isFalse);
        // When an explicit separate read consumes Detail.
        final detail = DisplayDetailResponse.fromJson(
          await display.read(
            DisplayReadRequest(
              resourceType: 'neutral',
              resourceId: 'r',
              metadata: metadata(),
            ),
          ),
        );
        // Then only that explicit read supplies projection evidence.
        expect(detail.data.resourceId, 'r');
        expect(display.callCount, 1);
        expect(operations.callCount, 1);
        expect(() => operations.calls.clear(), throwsUnsupportedError);
      },
    );
  });
}

PresentationContext neutralContext() => PresentationContext(
  flowId: 'flow',
  sourceId: 'source',
  componentId: 'component',
  families: [],
);
DisplayRequestMetadata metadata({int? revision}) => DisplayRequestMetadata(
  context: neutralContext(),
  observedRevision: revision,
);
OrdinaryOperationRequest operationRequest() => OrdinaryOperationRequest(
  operationId: 'neutral-operation',
  resourceId: 'r',
  metadata: metadata(revision: 1),
);
DisplayProvenance provenance(String revision) => DisplayProvenance(
  producerId: 'producer',
  sourceId: 'source',
  revision: revision,
);
DisplayDetailData detailData() => DisplayDetailData(
  resourceId: 'r',
  sourceRevision: 1,
  provenance: provenance('1'),
  bindings: [],
  model: DisplayDetailModel(
    screenId: 'detail',
    title: 'Detail',
    sections: [],
    actions: [],
  ),
);
Map<String, Object?> fixtureWire() => {
  'schema': 'textus.display.fixture.v1',
  'reference': {
    'sampleId': 'neutral',
    'sampleRevision': 1,
    'provisionalVersion': 1,
    'developmentOnly': true,
  },
  'resourceType': 'neutral',
  'contexts': {'neutral': neutralContext().toJson()},
  'displayResponses': {
    'list': DisplayListResponse(
      context: neutralContext(),
      data: DisplayListData(
        resourceType: 'neutral',
        snapshotId: 'snapshot-1',
        provenance: provenance('snapshot-1'),
        model: DisplayListModel(
          screenId: 'list',
          title: 'List',
          detailScreenId: 'detail',
          items: [
            DisplayResourceSummary(
              resourceId: 'r',
              sourceRevision: 1,
              fields: [],
            ),
          ],
        ),
      ),
    ).toJson(),
    'detail': DisplayDetailResponse(
      context: neutralContext(),
      data: detailData(),
    ).toJson(),
    'mutation': DisplayMutationResponse(
      context: neutralContext(),
      result: DisplayMutationResult(
        resourceId: 'r',
        outcome: DisplayCommandOutcome.unsupported,
        currentRevision: null,
        committedRevision: null,
        fieldErrors: [],
        message: null,
        display: null,
      ),
    ).toJson(),
  },
  'operationResponses': {
    'operation': OrdinaryOperationResponse(
      context: neutralContext(),
      result: DisplayOperationResult(
        resourceId: 'r',
        outcome: DisplayCommandOutcome.changed,
        currentRevision: 2,
        committedRevision: 2,
        fieldErrors: [],
        message: null,
      ),
    ).toJson(),
  },
  'semanticSeed': [
    {'resourceId': 'r', 'sourceRevision': 1},
  ],
  'projectionBindings': {'screenId': 'detail', 'fields': []},
  'operationBindings': {
    'neutral-operation': {
      'inputFields': ['resourceId'],
    },
  },
};
Future<Map<String, Object?>> invoke(
  DisplayTransport port,
  DisplayRequest request,
) => switch (request) {
  DisplayQueryRequest() => port.query(request),
  DisplayReadRequest() => port.read(request),
  DisplayUpdateRequest() => port.update(request),
  DisplayCreateRequest() => port.create(request),
  DisplayDeleteRequest() => port.delete(request),
};
