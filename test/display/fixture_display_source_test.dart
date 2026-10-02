import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('initial semantic projection', () {
    test(
      'ordered seed overrides template values and preserves presentation',
      () async {
        // Given neutral seeds and deliberately unrelated template identity/values.
        final source = makeSource();
        // When List and both selected Details cross public Display methods.
        final list = await querySource(source);
        final first = await readSource(source);
        final second = await readSource(source, id: 'second');
        // Then order, revisions, provenance and semantic versus lookup inputs agree.
        expect(list.data.model.items.map((item) => item.resourceId), [
          'first',
          'second',
        ]);
        expect(list.data.model.items.map((item) => item.sourceRevision), [
          1,
          4,
        ]);
        expect(list.data.snapshotId, 'snapshot-1');
        expect(list.data.provenance.revision, 'snapshot-1');
        expect(list.data.provenance.sourceId, 'neutral-source');
        expect(list.data.provenance.producerId, 'list-producer');
        expect(list.data.model.screenId, 'collection');
        expect(list.data.model.title, 'Collection');
        expect(list.data.model.detailScreenId, 'detail');
        expect(first.data.resourceId, 'first');
        expect(first.data.sourceRevision, 1);
        expect(first.data.provenance.revision, '1');
        expect(first.data.provenance.producerId, 'detail-producer');
        expect(first.data.model.title, 'Resource');
        expect(first.data.model.sections.single.id, 'body');
        expect(
          first.data.model.sections.single.fields.map((field) => field.id),
          ['name', 'status', 'note', 'count'],
        );
        expect(
          first.data.model.sections.single.fields.map((field) => field.label),
          ['Name', 'State', 'Note', 'Count'],
        );
        expect(
          first.data.model.sections.single.fields.map((field) => field.role),
          ['title', 'status', 'description', 'number'],
        );
        expect(
          fieldValue(first, 'status'),
          const TextDisplayValue('Ready label'),
        );
        expect(first.data.bindings.map((binding) => binding.inputValue), [
          const TextDisplayValue('Original'),
          const MissingDisplayValue(),
          const TextDisplayValue('Note'),
          const MissingDisplayValue(),
        ]);
        expect(fieldValue(first, 'count'), NumberDisplayValue(7));
        expect(
          fieldValue(second, 'status'),
          const TextDisplayValue('Done label'),
        );
        expect(first.data.model.actions.single.enabled, false);
        expect(second.data.model.actions, isEmpty);
        expect(source.calls.map((call) => call.kind), [
          DisplayRequestKind.query,
          DisplayRequestKind.read,
          DisplayRequestKind.read,
        ]);
      },
    );
  });

  group('atomic changed update', () {
    test(
      'multiline Unicode and empty optional text commit without normalization',
      () async {
        // Given a current resource and immutable earlier semantic snapshot.
        final source = makeSource();
        final previous = source.resources;
        const text = '  改訂\nΩ\u0085　 ';
        // When multiple valid semantic Text inputs are submitted together.
        final result = await updateSource(
          source,
          fields: [
            input('name', const TextDisplayValue(text)),
            input('note', const TextDisplayValue('')),
          ],
        );
        final list = await querySource(source);
        final detail = await readSource(source);
        // Then one atomic advancement preserves bytes and unrelated data/resources.
        expect(result.result.outcome, DisplayCommandOutcome.changed);
        expect(result.result.currentRevision, 2);
        expect(result.result.committedRevision, 2);
        expect(result.result.display!.sourceRevision, 2);
        expect(
          source.resources.first.fields['name'],
          const TextDisplayValue(text),
        );
        expect(
          source.resources.first.fields['note'],
          const TextDisplayValue(''),
        );
        expect(
          source.resources.first.fields['state'],
          const TextDisplayValue('ready'),
        );
        expect(source.resources.first.fields['count'], NumberDisplayValue(7));
        expect(source.resources[1].sourceRevision, 4);
        expect(source.resources[1].fields, previous[1].fields);
        expect(previous.first.sourceRevision, 1);
        expect(
          previous.first.fields['name'],
          const TextDisplayValue('Original'),
        );
        expect(list.data.snapshotId, 'snapshot-2');
        expect(list.data.model.items.first.sourceRevision, 2);
        expect(
          list.data.model.items.first.fields.first.value,
          const TextDisplayValue(text),
        );
        expect(fieldValue(detail, 'name'), const TextDisplayValue(text));
        expect(detail.data.provenance.revision, '2');
      },
    );

    test('two unawaited writes decide revisions synchronously', () async {
      // Given one source revision and two requests with the same observed revision.
      final source = makeSource();
      final firstRequest = updateRequest(
        fields: [input('name', const TextDisplayValue('First'))],
      );
      final secondRequest = updateRequest(
        fields: [input('name', const TextDisplayValue('Second'))],
      );
      // When both public methods are invoked before either Future is awaited.
      final firstFuture = source.update(firstRequest);
      final secondFuture = source.update(secondRequest);
      final first = DisplayMutationResponse.fromJson(await firstFuture);
      final second = DisplayMutationResponse.fromJson(await secondFuture);
      // Then the first commit precedes the second conflict without an overwrite.
      expect(first.result.outcome, DisplayCommandOutcome.changed);
      expect(second.result.outcome, DisplayCommandOutcome.conflict);
      expect(second.result.currentRevision, 2);
      expect(
        source.resources.first.fields['name'],
        const TextDisplayValue('First'),
      );
      expect(source.resources.first.sourceRevision, 2);
      // Given two writes resolved as one commit and one conflict.
      // When the consumer explicitly queries the List projection.
      final reloadedList = await querySource(source);
      // Then the explicit List retains exactly one snapshot advancement.
      expect(reloadedList.data.snapshotId, 'snapshot-2');
    });
  });

  group('noop conflict and scoped validation', () {
    test('equal and empty current inputs noop while stale equal inputs conflict', () async {
      // Given a committed revision two resource.
      final source = makeSource();
      await updateSource(
        source,
        fields: [input('name', const TextDisplayValue('New'))],
      );
      // When equal, empty and stale equal updates are submitted in that order.
      final equal = await updateSource(
        source,
        revision: 2,
        fields: [input('name', const TextDisplayValue('New'))],
      );
      final empty = await updateSource(source, revision: 2, fields: []);
      final stale = await updateSource(
        source,
        fields: [input('name', const TextDisplayValue('New'))],
      );
      // Then noops return current projection and stale comparison cannot bypass conflict.
      expect(equal.result.outcome, DisplayCommandOutcome.noOp);
      expect(empty.result.outcome, DisplayCommandOutcome.noOp);
      expect(equal.result.committedRevision, isNull);
      expect(equal.result.display!.sourceRevision, 2);
      expect(stale.result.outcome, DisplayCommandOutcome.conflict);
      expect(stale.result.currentRevision, 2);
      expect(stale.result.committedRevision, isNull);
      expect(stale.result.display, isNull);
      expect(source.resources.first.sourceRevision, 2);
      // Given equal and empty inputs returned noop and the stale input conflicted.
      // When the consumer explicitly queries the List projection.
      final reloadedList = await querySource(source);
      // Then the explicit List retains the single earlier committed snapshot.
      expect(reloadedList.data.snapshotId, 'snapshot-2');
    });

    final invalidCases = <String, (List<DisplayFieldInput>, String)>{
      'duplicate': (
        [
          input('name', const TextDisplayValue('One')),
          input('name', const TextDisplayValue('Two')),
        ],
        'duplicate-field',
      ),
      'unknown': (
        [input('absent', const TextDisplayValue('Value'))],
        'unknown-field',
      ),
      'wrong screen': (
        [input('name', const TextDisplayValue('Value'), screen: 'other')],
        'unknown-field',
      ),
      'wrong section': (
        [input('name', const TextDisplayValue('Value'), section: 'other')],
        'unknown-field',
      ),
      'read only': (
        [input('status', const TextDisplayValue('Done label'))],
        'read-only',
      ),
      'number': ([input('name', NumberDisplayValue(1))], 'invalid-type'),
      'bool': ([input('name', const BoolDisplayValue(true))], 'invalid-type'),
      'timestamp': (
        [input('name', TimestampDisplayValue(DateTime.utc(2026)))],
        'invalid-type',
      ),
      'missing': ([input('name', const MissingDisplayValue())], 'invalid-type'),
      'empty required': (
        [input('name', const TextDisplayValue(''))],
        'required-nonblank',
      ),
      'Unicode whitespace': (
        [input('name', const TextDisplayValue(' \t\n　\u0085'))],
        'required-nonblank',
      ),
    };
    for (final entry in invalidCases.entries) {
      test('${entry.key} rejects every field atomically with a scoped error', () async {
        // Given one valid change followed by the invalid scoped input variant.
        final source = makeSource();
        final invalid = entry.value.$1;
        final previous = source.resources;
        // When all inputs are sent through the actual public update method.
        final result = await updateSource(
          source,
          fields: [
            input('note', const TextDisplayValue('Must not commit')),
            ...invalid,
          ],
        );
        // Then one rejection exposes its locator and preserves every semantic value.
        expect(result.result.outcome, DisplayCommandOutcome.rejected);
        expect(result.result.fieldErrors.map((error) => error.code), [
          entry.value.$2,
        ]);
        expect(result.result.fieldErrors.single.locator, invalid.last.locator);
        expect(result.result.currentRevision, 1);
        expect(result.result.committedRevision, isNull);
        expect(result.result.display, isNull);
        expect(source.resources.first.fields, previous.first.fields);
        expect(source.resources.first.sourceRevision, 1);
        // Given the scoped invalid update rejected without changing semantic state.
        // When the consumer explicitly queries the List projection.
        final reloadedList = await querySource(source);
        // Then the explicit List retains the original snapshot after rejection.
        expect(reloadedList.data.snapshotId, 'snapshot-1');
        expect(() => result.result.fieldErrors.clear(), throwsUnsupportedError);
      });
    }

    test('null input cannot cross the typed update request boundary', () {
      // Given a wire request with explicit null instead of a typed Display value.
      final source = makeSource();
      final wire = updateRequest(
        fields: [input('name', const TextDisplayValue('New'))],
      ).toJson();
      ((wire['fields'] as List).single as Map)['value'] = null;
      // When the public request codec attempts to construct that invalid input.
      DisplayRequest decodeRequest() => DisplayRequest.fromJson(wire);
      // Then null rejects before transport use and no semantic change is possible.
      expect(decodeRequest, throwsFormatException);
      expect(source.callCount, 0);
      expect(source.resources.first.sourceRevision, 1);
    });
  });

  group('semantic alias admission and atomic inputs', () {
    for (final lookupFirst in [false, true]) {
      final caseId = lookupFirst ? 'AL02' : 'AL01';
      test('$caseId editable lookup alias rejects with either binding order', () {
        // Given otherwise valid seeded name aliases and matching Detail field order.
        final wire = fixtureWire();
        final lookup = fieldBinding(wire, index: 1);
        lookup['semanticField'] = 'name';
        lookup['lookup'] = {
          'Original': 'Original label',
          'Another': 'Another label',
        };
        if (lookupFirst) {
          projectionFields(wire).insert(0, projectionFields(wire).removeAt(1));
          detailFields(wire).insert(0, detailFields(wire).removeAt(1));
        }
        // When the public source constructor interprets the complete alias declaration.
        FixtureDisplaySource createSource() => makeSource(wire: wire);
        // Then the dedicated alias guard rejects before a usable source exists.
        expect(
          createSource,
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Editable semantic field cannot use a lookup projection',
            ),
          ),
        );
      });
    }

    test('AL03 read-only direct mirror preserves exact edited Text bytes', () async {
      // Given a read-only direct name mirror and untouched semantic seed data.
      final wire = fixtureWire();
      fieldBinding(wire, index: 1)['semanticField'] = 'name';
      fieldBinding(wire, index: 1).remove('lookup');
      final source = makeSource(wire: wire);
      final previous = source.resources;
      const text = '  改訂\nΩ\u0085　 ';
      // When a valid Unicode and multiline name crosses the public update port.
      final result = await updateSource(
        source,
        fields: [input('name', const TextDisplayValue(text))],
      );
      // Then one semantic commit preserves every other field and resource.
      expect(result.result.outcome, DisplayCommandOutcome.changed);
      expect(result.result.currentRevision, 2);
      expect(result.result.committedRevision, 2);
      expect(source.resources.first.sourceRevision, 2);
      expect(source.resources.first.fields, {
        ...previous.first.fields,
        'name': const TextDisplayValue(text),
      });
      expect(source.resources[1].fields, previous[1].fields);
      expect(source.resources[1].sourceRevision, previous[1].sourceRevision);
      // Given the committed source with its accepted read-only mirror.
      // When the consumer explicitly reloads Detail and List.
      final detail = await readSource(source);
      final list = await querySource(source);
      // Then both direct fields project exact bytes while read-only input stays Missing.
      expect(detail.data.sourceRevision, 2);
      expect(fieldValue(detail, 'name'), const TextDisplayValue(text));
      expect(fieldValue(detail, 'status'), const TextDisplayValue(text));
      expect(detail.data.bindings[1].inputValue, const MissingDisplayValue());
      expect(detail.data.bindings[1].writable, false);
      expect(list.data.snapshotId, 'snapshot-2');
      expect(list.data.model.items.first.sourceRevision, 2);
      expect(list.data.model.items.first.fields.map((field) => field.value), [
        const TextDisplayValue(text),
        const TextDisplayValue(text),
      ]);
    });

    test(
      'AL04 multiple read-only lookups project a separate Operation commit',
      () async {
        // Given two state lookups with distinct labels and complete ready/done coverage.
        final wire = fixtureWire();
        final alias = fieldBinding(wire, index: 2);
        alias['semanticField'] = 'state';
        alias['writable'] = false;
        alias['lookup'] = {
          'ready': 'Awaiting label',
          'done': 'Completed label',
        };
        listRowFields(wire).add(detailFields(wire)[2]);
        final source = makeSource(wire: wire);
        final previous = source.resources;
        final port = FixtureOrdinaryOperationTransport(source: source);
        // When the separate Operation port executes the declared transition.
        final result = OrdinaryOperationResponse.fromJson(
          await port.execute(operationRequest()),
        );
        // Then one separate commit advances state without an implicit Display call.
        expect(result.result.outcome, DisplayCommandOutcome.changed);
        expect(result.result.committedRevision, 2);
        expect(result.result.currentRevision, 2);
        expect(source.operationCallCount, 1);
        expect(source.callCount, 0);
        expect(source.resources.first.sourceRevision, 2);
        expect(source.resources.first.fields, {
          ...previous.first.fields,
          'state': const TextDisplayValue('done'),
        });
        expect(source.resources[1].fields, previous[1].fields);
        expect(source.resources[1].sourceRevision, previous[1].sourceRevision);
        // Given the committed source with both admitted finite lookup aliases.
        // When the consumer explicitly reads Detail and queries List.
        final detail = await readSource(source);
        final list = await querySource(source);
        // Then both lookups expose their done labels with Missing read-only inputs.
        expect(detail.data.sourceRevision, 2);
        expect(
          fieldValue(detail, 'status'),
          const TextDisplayValue('Done label'),
        );
        expect(
          fieldValue(detail, 'note'),
          const TextDisplayValue('Completed label'),
        );
        expect(detail.data.bindings[1].inputValue, const MissingDisplayValue());
        expect(detail.data.bindings[2].inputValue, const MissingDisplayValue());
        expect(detail.data.bindings[1].writable, false);
        expect(detail.data.bindings[2].writable, false);
        expect(list.data.snapshotId, 'snapshot-2');
        expect(list.data.model.items.first.sourceRevision, 2);
        expect(list.data.model.items.first.fields.map((field) => field.value), [
          const TextDisplayValue('Original'),
          const TextDisplayValue('Done label'),
          const TextDisplayValue('Completed label'),
        ]);
        expect(source.operationCallCount, 1);
      },
    );

    test(
      'AL05 optional writable alias shares the required semantic constraint',
      () async {
        // Given an optional note alias of the required name and untouched source snapshots.
        final source = makeSource(wire: writableAliasWire());
        final previous = source.resources;
        final submitted = input('note', const TextDisplayValue(' \t\n　\u0085'));
        // When Unicode-blank Text is submitted through that optional alias.
        final result = await updateSource(source, fields: [submitted]);
        // Then the submitted locator reports the shared requirement without any commit.
        expect(result.result.outcome, DisplayCommandOutcome.rejected);
        expect(result.result.fieldErrors.single.code, 'required-nonblank');
        expect(result.result.fieldErrors.single.locator, submitted.locator);
        expect(result.result.currentRevision, 1);
        expect(result.result.committedRevision, isNull);
        expect(result.result.display, isNull);
        expect(
          source.resources.map((resource) => resource.fields),
          previous.map((resource) => resource.fields),
        );
        expect(source.resources.map((resource) => resource.sourceRevision), [
          1,
          4,
        ]);
        // Given the unchanged source after atomic alias rejection.
        // When the consumer explicitly queries its projection snapshot.
        final list = await querySource(source);
        // Then rejection advances neither snapshot nor row revision or projected values.
        expect(list.data.snapshotId, 'snapshot-1');
        expect(list.data.model.items.first.sourceRevision, 1);
        expect(
          list.data.model.items.first.fields.first.value,
          const TextDisplayValue('Original'),
        );
      },
    );

    test(
      'AL06 equal writable alias values coalesce into one commit then noop',
      () async {
        // Given optional and required direct aliases of one semantic name.
        final source = makeSource(wire: writableAliasWire());
        final previous = source.resources;
        const text = '  共通\nΩ　 ';
        final inputs = [
          input('name', const TextDisplayValue(text)),
          input('note', const TextDisplayValue(text)),
        ];
        // When both locators submit equal valid Text at revision one.
        final changed = await updateSource(source, fields: inputs);
        // Then the aliases coalesce into exactly one source commit.
        expect(changed.result.outcome, DisplayCommandOutcome.changed);
        expect(changed.result.currentRevision, 2);
        expect(changed.result.committedRevision, 2);
        expect(source.resources.first.sourceRevision, 2);
        expect(source.resources.first.fields, {
          ...previous.first.fields,
          'name': const TextDisplayValue(text),
        });
        expect(source.resources[1].fields, previous[1].fields);
        expect(source.resources[1].sourceRevision, 4);
        expect(
          changed.result.display!.bindings[0].inputValue,
          const TextDisplayValue(text),
        );
        expect(
          changed.result.display!.bindings[2].inputValue,
          const TextDisplayValue(text),
        );
        expect(changed.result.display!.bindings[0].requiredNonBlank, true);
        expect(changed.result.display!.bindings[2].requiredNonBlank, false);
        // Given the current revision two with the same equal alias values.
        // When both alias inputs are submitted again at the current revision.
        final noop = await updateSource(source, revision: 2, fields: inputs);
        // Then equality returns noop without a second semantic advancement.
        expect(noop.result.outcome, DisplayCommandOutcome.noOp);
        expect(noop.result.currentRevision, 2);
        expect(noop.result.committedRevision, isNull);
        expect(source.resources.first.sourceRevision, 2);
        // Given the coalesced source after its unchanged noop receipt.
        // When the consumer explicitly reloads Detail and List.
        final detail = await readSource(source);
        final list = await querySource(source);
        // Then projection and edit inputs agree at one committed snapshot.
        expect(detail.data.sourceRevision, 2);
        expect(fieldValue(detail, 'name'), const TextDisplayValue(text));
        expect(fieldValue(detail, 'note'), const TextDisplayValue(text));
        expect(
          detail.data.bindings[0].inputValue,
          const TextDisplayValue(text),
        );
        expect(
          detail.data.bindings[2].inputValue,
          const TextDisplayValue(text),
        );
        expect(list.data.snapshotId, 'snapshot-2');
        expect(list.data.model.items.first.sourceRevision, 2);
        expect(
          list.data.model.items.first.fields.first.value,
          const TextDisplayValue(text),
        );
      },
    );

    for (final nameFirst in [true, false]) {
      final caseId = nameFirst ? 'AL07' : 'AL08';
      test(
        '$caseId unequal alias values reject atomically in actual input order',
        () async {
          // Given two valid unequal Text inputs for aliases of the same semantic name.
          final source = makeSource(wire: writableAliasWire());
          final previous = source.resources;
          final inputs = [
            input('name', const TextDisplayValue('One')),
            input('note', const TextDisplayValue('Two')),
          ];
          final ordered = nameFirst ? inputs : inputs.reversed.toList();
          // When both inputs cross one current-revision public update.
          final result = await updateSource(source, fields: ordered);
          // Then the later conflicting locator rejects the whole candidate without a commit.
          expect(result.result.outcome, DisplayCommandOutcome.rejected);
          expect(result.result.fieldErrors.single.code, 'duplicate-field');
          expect(
            result.result.fieldErrors.single.locator,
            ordered.last.locator,
          );
          expect(result.result.currentRevision, 1);
          expect(result.result.committedRevision, isNull);
          expect(result.result.display, isNull);
          expect(
            source.resources.map((resource) => resource.fields),
            previous.map((resource) => resource.fields),
          );
          expect(source.resources.map((resource) => resource.sourceRevision), [
            1,
            4,
          ]);
          // Given the source preserved after the conflicting alias inputs.
          // When the consumer explicitly queries the current List snapshot.
          final list = await querySource(source);
          // Then the original projection proves no snapshot or row advancement.
          expect(list.data.snapshotId, 'snapshot-1');
          expect(list.data.model.items.first.sourceRevision, 1);
          expect(
            list.data.model.items.first.fields.first.value,
            const TextDisplayValue('Original'),
          );
        },
      );
    }
  });

  group('unsupported capability and absent resources', () {
    test(
      'create and known or unknown delete stay unsupported without mutation',
      () async {
        // Given the seed-backed source and capability requests.
        final source = makeSource();
        final previous = source.resources;
        // When create, known delete and absent delete use their public methods.
        final create = DisplayMutationResponse.fromJson(
          await source.create(
            DisplayCreateRequest(
              resourceType: 'neutral-type',
              metadata: metadata(),
              fields: [],
            ),
          ),
        );
        final known = DisplayMutationResponse.fromJson(
          await source.delete(
            DisplayDeleteRequest(
              resourceType: 'neutral-type',
              metadata: metadata(revision: 1),
              resourceId: 'first',
            ),
          ),
        );
        final absent = DisplayMutationResponse.fromJson(
          await source.delete(
            DisplayDeleteRequest(
              resourceType: 'neutral-type',
              metadata: metadata(revision: 1),
              resourceId: 'absent',
            ),
          ),
        );
        // Then capability receipts carry required identities and never imply a commit.
        expect(create.result.resourceId, 'unsupported:create');
        expect(known.result.resourceId, 'first');
        expect(known.result.currentRevision, 1);
        expect(absent.result.resourceId, 'absent');
        expect(absent.result.currentRevision, isNull);
        for (final response in [create, known, absent]) {
          expect(response.result.outcome, DisplayCommandOutcome.unsupported);
          expect(response.result.committedRevision, isNull);
          expect(response.result.display, isNull);
        }
        expect(source.resources.first.fields, previous.first.fields);
        // Given all capability requests returned unsupported without a source commit.
        // When the consumer explicitly queries the List projection.
        final reloadedList = await querySource(source);
        // Then the explicit List retains the original snapshot.
        expect(reloadedList.data.snapshotId, 'snapshot-1');
      },
    );

    test(
      'absent update rejects globally and absent read fails unavailable',
      () async {
        // Given no seed resource with the requested identity.
        final source = makeSource();
        // When update and read address that missing resource.
        final result = await updateSource(source, id: 'absent', fields: []);
        final read = readSource(source, id: 'absent');
        // Then failure kinds remain distinct and source state does not advance.
        expect(result.result.outcome, DisplayCommandOutcome.rejected);
        expect(result.result.currentRevision, isNull);
        expect(result.result.fieldErrors.single.code, 'unknown-resource');
        expect(result.result.fieldErrors.single.locator, isNull);
        await expectLater(
          read,
          throwsA(transportFailure(DisplayTransportFailure.unavailable)),
        );
        expect(source.resources.first.sourceRevision, 1);
        expect(source.callCount, 2);
      },
    );
  });

  group('separate ordinary Operation', () {
    test(
      'admitted transition commits once and only explicit reads remove action',
      () async {
        // Given an availability descriptor whose enabled flag is false.
        final source = makeSource();
        final before = await readSource(source);
        final displayCount = source.callCount;
        final request = operationRequest();
        final OrdinaryOperationTransport port =
            FixtureOrdinaryOperationTransport(source: source);
        // When the separate Operation port admits the declared semantic transition.
        final wire = await port.execute(request);
        final result = OrdinaryOperationResponse.fromJson(wire);
        // Then source advances independently with no Display request or projection body.
        expect(before.data.model.actions.single.enabled, false);
        expect(result.result.outcome, DisplayCommandOutcome.changed);
        expect(result.result.currentRevision, 2);
        expect(result.result.committedRevision, 2);
        expect(wire.containsKey('display'), isFalse);
        expect(source.callCount, displayCount);
        expect(source.operationCallCount, 1);
        expect(source.operationCalls.single, same(request));
        expect(
          source.resources.first.fields['state'],
          const TextDisplayValue('done'),
        );
        expect(
          source.resources.first.fields['name'],
          const TextDisplayValue('Original'),
        );
        expect(source.resources.first.fields['count'], NumberDisplayValue(7));
        expect(source.resources[1].sourceRevision, 4);
        // When the consumer explicitly reloads Detail and List after the separate receipt.
        final detail = await readSource(source);
        final list = await querySource(source);
        // Then fresh projection evidence exposes the committed transition and removes the action.
        expect(detail.data.sourceRevision, 2);
        expect(
          fieldValue(detail, 'status'),
          const TextDisplayValue('Done label'),
        );
        expect(detail.data.model.actions, isEmpty);
        expect(list.data.snapshotId, 'snapshot-2');
      },
    );

    test(
      'unknown resource operation stale revision and precondition never commit',
      () async {
        // Given resources at revisions one and four with different expected states.
        final source = makeSource();
        final port = FixtureOrdinaryOperationTransport(source: source);
        final requests = [
          operationRequest(id: 'absent'),
          operationRequest(operation: 'absent'),
          operationRequest(revision: 2),
          operationRequest(id: 'second', revision: 3),
          operationRequest(id: 'second', revision: 4),
        ];
        // When each invalid Operation crosses only the separate public port.
        final results = <OrdinaryOperationResponse>[];
        for (final request in requests) {
          results.add(
            OrdinaryOperationResponse.fromJson(await port.execute(request)),
          );
        }
        // Then global rejection and conflict ordering preserve both revisions and snapshot.
        expect(results.map((response) => response.result.outcome), [
          DisplayCommandOutcome.rejected,
          DisplayCommandOutcome.rejected,
          DisplayCommandOutcome.conflict,
          DisplayCommandOutcome.conflict,
          DisplayCommandOutcome.rejected,
        ]);
        expect(results[0].result.fieldErrors.single.code, 'unknown-resource');
        expect(results[1].result.fieldErrors.single.code, 'unknown-operation');
        expect(results[2].result.currentRevision, 1);
        expect(results[3].result.currentRevision, 4);
        expect(
          results[4].result.fieldErrors.single.code,
          'operation-precondition',
        );
        expect(
          results
              .expand((response) => response.result.fieldErrors)
              .every((error) => error.locator == null),
          isTrue,
        );
        expect(
          results.every(
            (response) => response.result.committedRevision == null,
          ),
          isTrue,
        );
        expect(source.resources.map((resource) => resource.sourceRevision), [
          1,
          4,
        ]);
        expect(source.callCount, 0);
        // Given all invalid Operations returned rejection or conflict without a commit.
        // When the consumer explicitly queries the List projection.
        final reloadedList = await querySource(source);
        // Then the explicit List retains the original snapshot.
        expect(reloadedList.data.snapshotId, 'snapshot-1');
      },
    );

    test(
      'all declared Operation transition fields commit atomically once',
      () async {
        // Given a transition changing multiple semantic Text fields together.
        final wire = fixtureWire();
        operationBinding(wire)['transition'] = {
          'state': 'done',
          'name': 'Moved',
          'note': '',
        };
        final source = makeSource(wire: wire);
        final previous = source.resources;
        // When the separate public Operation admits that complete declared transition.
        final result = OrdinaryOperationResponse.fromJson(
          await FixtureOrdinaryOperationTransport(source: source)
              .execute(operationRequest()),
        );
        // Then all fields change in one revision while unrelated data and resources survive.
        expect(result.result.committedRevision, 2);
        expect(
          source.resources.first.fields['state'],
          const TextDisplayValue('done'),
        );
        expect(
          source.resources.first.fields['name'],
          const TextDisplayValue('Moved'),
        );
        expect(
          source.resources.first.fields['note'],
          const TextDisplayValue(''),
        );
        expect(
          source.resources.first.fields['count'],
          previous.first.fields['count'],
        );
        expect(source.resources[1].fields, previous[1].fields);
        expect(source.operationCallCount, 1);
        expect(source.callCount, 0);
        // Given the separate atomic transition committed exactly one source revision.
        // When the consumer explicitly queries the List projection.
        final reloadedList = await querySource(source);
        // Then the explicit List exposes exactly one snapshot advancement.
        expect(reloadedList.data.snapshotId, 'snapshot-2');
      },
    );

    test('an admitted equal transition is still a changed Operation', () async {
      // Given a declarative Operation that transitions to its already expected value.
      final wire = fixtureWire();
      final operations = wire['operationBindings'] as Map<String, Object?>;
      (operations['advance'] as Map<String, Object?>)['transition'] = {
        'state': 'ready',
      };
      final source = makeSource(wire: wire);
      // When the Operation executes at the current revision.
      final result = OrdinaryOperationResponse.fromJson(
        await FixtureOrdinaryOperationTransport(source: source)
            .execute(operationRequest()),
      );
      // Then the Operation contract advances revision even when text remains equal.
      expect(result.result.outcome, DisplayCommandOutcome.changed);
      expect(result.result.committedRevision, 2);
      expect(
        source.resources.first.fields['state'],
        const TextDisplayValue('ready'),
      );
      // Given the equal transition returned changed under the Operation contract.
      // When the consumer explicitly queries the List projection.
      final reloadedList = await querySource(source);
      // Then the explicit List exposes the single Operation snapshot advancement.
      expect(reloadedList.data.snapshotId, 'snapshot-2');
    });
  });

  group('projection freshness and ambiguous delivery', () {
    test(
      'idempotent hold preserves old projection while writes commit live data',
      () async {
        // Given a held revision one projection.
        final source = makeSource();
        source.holdProjection();
        // When an update commits and repeated hold follows another Operation commit.
        final result = await updateSource(
          source,
          fields: [input('name', const TextDisplayValue('New'))],
        );
        source.holdProjection();
        await FixtureOrdinaryOperationTransport(source: source)
            .execute(operationRequest(revision: 2));
        final staleList = await querySource(source);
        final staleDetail = await readSource(source);
        source.releaseProjection();
        final freshDetail = await readSource(source);
        final freshList = await querySource(source);
        // Then stale evidence differs from committed state until explicit projection release.
        expect(result.result.committedRevision, 2);
        expect(result.result.display!.sourceRevision, 1);
        expect(source.resources.first.sourceRevision, 3);
        expect(staleDetail.data.sourceRevision, 1);
        expect(staleList.data.snapshotId, 'snapshot-1');
        expect(staleDetail.data.model.actions, hasLength(1));
        expect(freshDetail.data.sourceRevision, 3);
        expect(fieldValue(freshDetail, 'name'), const TextDisplayValue('New'));
        expect(
          fieldValue(freshDetail, 'status'),
          const TextDisplayValue('Done label'),
        );
        expect(freshDetail.data.model.actions, isEmpty);
        expect(freshList.data.snapshotId, 'snapshot-3');
      },
    );

    test('omission waits through rejection and consumes only one successful receipt', () async {
      // Given one queued omission and a valid source revision.
      final source = makeSource();
      source.omitNextMutationProjection();
      // When rejection precedes a changed receipt then a noop and a second omitted noop.
      final rejected = await updateSource(
        source,
        fields: [input('status', const TextDisplayValue('x'))],
      );
      final changed = await updateSource(
        source,
        fields: [input('name', const TextDisplayValue('New'))],
      );
      final noop = await updateSource(source, revision: 2, fields: []);
      source.omitNextMutationProjection();
      final omittedNoop = await updateSource(source, revision: 2, fields: []);
      final following = await updateSource(source, revision: 2, fields: []);
      // Then omitted projections never undo commits and the flag has one-shot receipt scope.
      expect(rejected.result.outcome, DisplayCommandOutcome.rejected);
      expect(changed.result.committedRevision, 2);
      expect(changed.result.display, isNull);
      expect(noop.result.display!.sourceRevision, 2);
      expect(omittedNoop.result.outcome, DisplayCommandOutcome.noOp);
      expect(omittedNoop.result.display, isNull);
      expect(following.result.display!.sourceRevision, 2);
      expect(source.resources.first.sourceRevision, 2);
    });

    for (final fault in FixtureTransportFault.values) {
      test(
        '${fault.name} update has exact commit effects and no automatic replay',
        () async {
          // Given one queued delivery failure on an admitted changed update.
          final source = makeSource();
          source.failNextDisplay(DisplayRequestKind.update, fault);
          // When the changed update is attempted exactly once through the public port.
          final future = updateSource(
            source,
            fields: [input('name', const TextDisplayValue('New'))],
          );
          // Then delivery failure distinguishes possible commit and records one call only.
          await expectLater(
            future,
            throwsA(
              transportFailure(
                fault == FixtureTransportFault.unavailable
                    ? DisplayTransportFailure.unavailable
                    : DisplayTransportFailure.ambiguous,
              ),
            ),
          );
          final revision = fault == FixtureTransportFault.ambiguousAfterCommit
              ? 2
              : 1;
          expect(source.callCount, 1);
          expect(source.resources.first.sourceRevision, revision);
          // Given the observed delivery failure and its possible committed revision.
          // When the consumer explicitly reloads Detail once.
          final detail = await readSource(source);
          // Then projection exposes the actual commit outcome without replaying the update.
          expect(detail.data.sourceRevision, revision);
          expect(
            fieldValue(detail, 'name'),
            TextDisplayValue(revision == 2 ? 'New' : 'Original'),
          );
          expect(
            source.calls.where(
              (call) => call.kind == DisplayRequestKind.update,
            ),
            hasLength(1),
          );
        },
      );

      test(
        '${fault.name} Operation preserves separate delivery and never replays',
        () async {
          // Given one Operation fault and a source in the admitted expected state.
          final source = makeSource();
          source.failNextOperation(fault);
          final port = FixtureOrdinaryOperationTransport(source: source);
          // When the separate Operation is attempted once.
          final future = port.execute(operationRequest());
          // Then only after-commit ambiguity changes semantic state without a Display call.
          await expectLater(
            future,
            throwsA(
              transportFailure(
                fault == FixtureTransportFault.unavailable
                    ? DisplayTransportFailure.unavailable
                    : DisplayTransportFailure.ambiguous,
              ),
            ),
          );
          expect(source.operationCallCount, 1);
          expect(source.callCount, 0);
          expect(
            source.resources.first.sourceRevision,
            fault == FixtureTransportFault.ambiguousAfterCommit ? 2 : 1,
          );
          // Given one recorded Operation attempt after the observed delivery failure.
          // When the consumer explicitly reads the Detail projection.
          await readSource(source);
          // Then the read does not replay the separate Operation.
          expect(source.operationCallCount, 1);
        },
      );
    }

    test('after-commit faults return actual nonchanged outcomes', () async {
      // Given queued after-commit ambiguity for each nonchanged command path.
      final source = makeSource();
      final requests = [
        updateRequest(fields: []),
        updateRequest(revision: 2, fields: []),
        updateRequest(fields: [input('status', const TextDisplayValue('x'))]),
      ];
      // When noop conflict rejection unsupported and precondition failures execute.
      final results = <DisplayCommandOutcome>[];
      for (final request in requests) {
        source.failNextDisplay(
          DisplayRequestKind.update,
          FixtureTransportFault.ambiguousAfterCommit,
        );
        results.add(
          DisplayMutationResponse.fromJson(await source.update(request))
              .result
              .outcome,
        );
      }
      source.failNextDisplay(
        DisplayRequestKind.create,
        FixtureTransportFault.ambiguousAfterCommit,
      );
      final create = DisplayMutationResponse.fromJson(
        await source.create(
          DisplayCreateRequest(
            resourceType: 'neutral-type',
            metadata: metadata(),
            fields: [],
          ),
        ),
      );
      source.failNextOperation(FixtureTransportFault.ambiguousAfterCommit);
      final operation = OrdinaryOperationResponse.fromJson(
        await FixtureOrdinaryOperationTransport(source: source)
            .execute(operationRequest(id: 'second', revision: 4)),
      );
      // Then simulated lost-success delivery never replaces an actual failure or noop receipt.
      expect(results, [
        DisplayCommandOutcome.noOp,
        DisplayCommandOutcome.conflict,
        DisplayCommandOutcome.rejected,
      ]);
      expect(create.result.outcome, DisplayCommandOutcome.unsupported);
      expect(operation.result.outcome, DisplayCommandOutcome.rejected);
      expect(source.resources.map((resource) => resource.sourceRevision), [
        1,
        4,
      ]);
    });
  });

  group('fault queues immutable observations and strict admission', () {
    test(
      'method specific FIFO faults are one-shot and independent of Operation',
      () async {
        // Given two read faults, one query fault and one separate Operation fault.
        final source = makeSource();
        source.failNextDisplay(
          DisplayRequestKind.read,
          FixtureTransportFault.unavailable,
        );
        source.failNextDisplay(
          DisplayRequestKind.read,
          FixtureTransportFault.ambiguousAfterCommit,
        );
        source.failNextDisplay(
          DisplayRequestKind.query,
          FixtureTransportFault.ambiguousBeforeCommit,
        );
        source.failNextOperation(FixtureTransportFault.unavailable);
        // When interleaved methods consume only their own queues.
        final query = querySource(source);
        final readOne = readSource(source);
        final operation = FixtureOrdinaryOperationTransport(source: source)
            .execute(operationRequest());
        final readTwo = readSource(source);
        // Then exact failures are consumed in order without semantic effects or replay.
        await Future.wait([
          expectLater(
            query,
            throwsA(transportFailure(DisplayTransportFailure.ambiguous)),
          ),
          expectLater(
            readOne,
            throwsA(transportFailure(DisplayTransportFailure.unavailable)),
          ),
          expectLater(
            operation,
            throwsA(transportFailure(DisplayTransportFailure.unavailable)),
          ),
          expectLater(
            readTwo,
            throwsA(transportFailure(DisplayTransportFailure.ambiguous)),
          ),
        ]);
        // Given both read faults consumed without a source commit.
        // When the consumer explicitly reads again through the public port.
        final successfulRead = await readSource(source);
        // Then the read succeeds at the original resource revision.
        expect(successfulRead.data.sourceRevision, 1);
        // Given the query fault consumed and the successful read recorded.
        // When the consumer explicitly queries again through the public port.
        final successfulList = await querySource(source);
        // Then the query succeeds at the original snapshot with exact call counts.
        expect(successfulList.data.snapshotId, 'snapshot-1');
        expect(source.callCount, 5);
        expect(source.operationCallCount, 1);
      },
    );

    test(
      'calls semantic values and independent source instances remain immutable',
      () async {
        // Given two independent interpreters of the same supplied fixture.
        final fixture = DisplayPrototypeFixture.fromJson(fixtureWire());
        final source = makeSource(fixture: fixture);
        final other = makeSource(fixture: fixture);
        final initial = source.resources;
        final request = updateRequest(
          fields: [input('name', const TextDisplayValue('New'))],
        );
        // When one instance commits and queues a fault and the caller tries snapshot changes.
        await source.update(request);
        await FixtureOrdinaryOperationTransport(source: source)
            .execute(operationRequest(revision: 2));
        source.failNextDisplay(
          DisplayRequestKind.read,
          FixtureTransportFault.unavailable,
        );
        final calls = source.calls;
        final operations = source.operationCalls;
        final otherDetail = await readSource(other);
        // Then exact immutable requests and earlier snapshots cannot mutate either source.
        expect(calls.single.request, same(request));
        expect(() => calls.clear(), throwsUnsupportedError);
        expect(() => operations.clear(), throwsUnsupportedError);
        expect(() => initial.clear(), throwsUnsupportedError);
        expect(() => initial.first.fields.clear(), throwsUnsupportedError);
        expect(initial.first.sourceRevision, 1);
        expect(
          initial.first.fields['name'],
          const TextDisplayValue('Original'),
        );
        expect(otherDetail.data.sourceRevision, 1);
        expect(other.operationCallCount, 0);
        expect(
          other.resources.first.fields['state'],
          const TextDisplayValue('ready'),
        );
        expect(fixture.semanticSeed, fixtureWire()['semanticSeed']);
        // Given the caller retains an immutable earlier call observation.
        // When another query is recorded on the same source.
        await querySource(source);
        // Then the earlier observation keeps its original single request.
        expect(calls, hasLength(1));
      },
    );

    test('semantic resource constructor defensively copies and validates identities', () {
      // Given mutable typed semantic fields.
      final fields = <String, DisplayValue>{
        'name': const TextDisplayValue('Before'),
      };
      // When the public immutable value is built and the caller replaces its input.
      final resource = FixtureSemanticResource(
        resourceId: 'r',
        sourceRevision: 1,
        fields: fields,
      );
      fields['name'] = const TextDisplayValue('After');
      // Then the snapshot remains independent and invalid constructor identities reject.
      expect(resource.fields['name'], const TextDisplayValue('Before'));
      expect(() => resource.fields.clear(), throwsUnsupportedError);
      expect(
        () => FixtureSemanticResource(
          resourceId: ' ',
          sourceRevision: 1,
          fields: fields,
        ),
        throwsFormatException,
      );
      expect(
        () => FixtureSemanticResource(
          resourceId: 'r',
          sourceRevision: 0,
          fields: fields,
        ),
        throwsFormatException,
      );
      expect(
        () => FixtureSemanticResource(
          resourceId: 'r',
          sourceRevision: 1,
          fields: {' ': const MissingDisplayValue()},
        ),
        throwsFormatException,
      );
    });

    final malformedCases = <String, void Function(Map<String, Object?>)>{
      'empty seed': (wire) => wire['semanticSeed'] = <Object?>[],
      'duplicate resource': (wire) => (wire['semanticSeed'] as List<Object?>)
          .add((wire['semanticSeed'] as List<Object?>).first),
      'seed extra member': (wire) => seedObject(wire)['extra'] = true,
      'seed missing fields': (wire) => seedObject(wire).remove('fields'),
      'seed invalid revision': (wire) =>
          seedObject(wire)['sourceRevision'] = 1.0,
      'empty semantic fields': (wire) =>
          seedObject(wire)['fields'] = <String, Object?>{},
      'unsupported value': (wire) =>
          semanticFields(wire)['name'] = {'type': 'object', 'value': {}},
      'null value': (wire) => semanticFields(wire)['name'] = null,
      'missing semantic key': (wire) => semanticFields(wire).remove('name'),
      'binding extra member': (wire) => fieldBinding(wire)['extra'] = true,
      'nonbool writable': (wire) => fieldBinding(wire)['writable'] = 'true',
      'duplicate field': (wire) =>
          projectionFields(wire).add(projectionFields(wire).first),
      'writable lookup': (wire) =>
          fieldBinding(wire)['lookup'] = {'Original': 'Label'},
      'read only required': (wire) =>
          fieldBinding(wire, index: 1)['requiredNonBlank'] = true,
      'nonText writable': (wire) =>
          semanticFields(wire)['name'] = {'type': 'number', 'value': 1},
      'empty lookup': (wire) =>
          fieldBinding(wire, index: 1)['lookup'] = <String, Object?>{},
      'nonstring lookup': (wire) =>
          fieldBinding(wire, index: 1)['lookup'] = {'ready': 1},
      'unmapped seed lookup': (wire) =>
          fieldBinding(wire, index: 1)['lookup'] = {'done': 'Done label'},
      'nonText lookup': (wire) =>
          semanticFields(wire)['state'] = {'type': 'bool', 'value': true},
      'wrong section': (wire) =>
          (wire['projectionBindings'] as Map<String, Object?>)['sectionId'] =
              'other',
      'wrong field order': (wire) =>
          projectionFields(wire).insert(0, projectionFields(wire).removeAt(1)),
      'nondevelopment operation': (wire) =>
          operationBinding(wire)['developmentOnly'] = false,
      'extra Operation input': (wire) =>
          operationBinding(wire)['inputFields'] = ['resourceId', 'name'],
      'empty expected': (wire) =>
          operationBinding(wire)['expected'] = <String, Object?>{},
      'unknown transition key': (wire) =>
          operationBinding(wire)['transition'] = {'absent': 'x'},
      'nonText Operation key': (wire) =>
          operationBinding(wire)['expected'] = {'count': '7'},
      'unmapped transition': (wire) =>
          operationBinding(wire)['transition'] = {'state': 'unknown'},
      'blank required transition': (wire) =>
          operationBinding(wire)['transition'] = {'name': '\u0085　'},
      'missing action Operation': (wire) =>
          wire['operationBindings'] = <String, Object?>{},
      'duplicate flow': (wire) =>
          (wire['contexts'] as Map<String, Object?>)['duplicate'] =
              neutralContext().toJson(),
      'wrong fixture source': (wire) =>
          (wire['contexts'] as Map<String, Object?>)['neutral'] =
              neutralContext(source: 'other').toJson(),
      'wrong fixture component': (wire) =>
          (wire['contexts'] as Map<String, Object?>)['neutral'] =
              neutralContext(component: 'other').toJson(),
    };
    for (final entry in malformedCases.entries) {
      test('${entry.key} fails strict interpreter admission', () {
        // Given a decoded generic fixture with a malformed interpreter mapping.
        final wire = fixtureWire();
        entry.value(wire);
        // When the fixture/source admission boundary interprets that exact variant.
        FixtureDisplaySource createSource() => makeSource(wire: wire);
        // Then malformed data fails before a source can be used.
        expect(createSource, throwsFormatException);
      });
    }

    for (final variant in [
      'missing list',
      'wrong list kind',
      'wrong detail kind',
      'empty rows',
      'unknown row field',
      'wrong detail target',
    ]) {
      test('$variant rejects selected presentation templates', () {
        // Given decoded templates whose selected presentation structure differs.
        final wire = fixtureWire();
        final responses = wire['displayResponses'] as Map<String, Object?>;
        if (variant == 'missing list') responses.remove('rows');
        if (variant == 'wrong list kind') {
          responses['rows'] = responses['entry'];
        }
        if (variant == 'wrong detail kind') {
          responses['entry'] = responses['rows'];
        }
        if (variant == 'empty rows' ||
            variant == 'unknown row field' ||
            variant == 'wrong detail target') {
          final data =
              (responses['rows'] as Map<String, Object?>)['data']
                  as Map<String, Object?>;
          final model = data['model'] as Map<String, Object?>;
          if (variant == 'empty rows') model['items'] = <Object?>[];
          if (variant == 'wrong detail target') {
            model['detailScreenId'] = 'other';
          }
          if (variant == 'unknown row field') {
            final item =
                (model['items'] as List<Object?>).first as Map<String, Object?>;
            final field =
                (item['fields'] as List<Object?>).first as Map<String, Object?>;
            field['id'] = 'absent';
          }
        }
        // When a source selects these named List and Detail templates.
        FixtureDisplaySource createSource() => makeSource(wire: wire);
        // Then no malformed selected template is admitted.
        expect(createSource, throwsFormatException);
      });
    }
  });

  group('request context and injected clock admission', () {
    test('neutral context echoes permitted producer attempt replacement and omission', () async {
      // Given a neutral non-experiment flow with one expired optional extension.
      final wire = fixtureWire();
      final original = neutralContext(expiredOptional: true);
      (wire['contexts'] as Map<String, Object?>)['neutral'] = original.toJson();
      final source = makeSource(wire: wire);
      final context = neutralContext(
        expiredOptional: true,
        attempt: 'producer-attempt-2',
      );
      // When query update Operation and read carry that same supplied flow.
      final list = DisplayListResponse.fromJson(
        await source.query(
          DisplayQueryRequest(
            resourceType: 'neutral-type',
            metadata: metadata(context: context),
          ),
        ),
      );
      final update = await updateSource(
        source,
        context: context,
        fields: [input('name', const TextDisplayValue('New'))],
      );
      final operation = OrdinaryOperationResponse.fromJson(
        await FixtureOrdinaryOperationTransport(source: source)
            .execute(operationRequest(context: context, revision: 2)),
      );
      final detail = await readSource(source, context: context);
      // Then admitted families echo unchanged except declared optional expiry omission.
      final expected = PresentationContext(
        flowId: context.flowId,
        sourceId: context.sourceId,
        componentId: context.componentId,
        families: context.families
            .where((family) => family.namespace != 'neutral.hints')
            .toList(),
      );
      for (final received in [
        list.context,
        update.context,
        operation.context,
        detail.context,
      ]) {
        expect(received, expected);
        expect(
          received.families.any(
            (family) => family.payload is SuppliedArmPresentationPayload,
          ),
          isFalse,
        );
      }
      expect(source.calls.first.request.metadata.context, context);
      expect(source.operationCalls.single.metadata.context, context);
      expect(source.resources.first.sourceRevision, 3);
    });

    final invalidContexts = <String, PresentationContext Function()>{
      'source': () => neutralContext(source: 'other'),
      'component': () => neutralContext(component: 'other'),
      'unknown flow': () => neutralContext(flow: 'other-flow'),
      'assignment': () => assignedContext(assignment: 'replacement'),
      'required expiry': () => assignedContext(expired: true),
      'required unsupported': () => assignedContext(version: 2),
      'unknown required': () => neutralContext(requiredUnknown: true),
    };
    for (final entry in invalidContexts.entries) {
      test('${entry.key} blocks calls writes and queued fault consumption', () async {
        // Given a source with queued update/Operation faults and incompatible supplied context.
        final source = makeSource();
        source.failNextDisplay(
          DisplayRequestKind.update,
          FixtureTransportFault.unavailable,
        );
        source.failNextOperation(FixtureTransportFault.unavailable);
        final context = entry.value();
        final port = FixtureOrdinaryOperationTransport(source: source);
        // When invalid context attempts query read update and ordinary Operation.
        final attempts = <Future<Object?>>[
          source.query(
            DisplayQueryRequest(
              resourceType: 'neutral-type',
              metadata: metadata(context: context),
            ),
          ),
          source.read(
            DisplayReadRequest(
              resourceType: 'neutral-type',
              resourceId: 'first',
              metadata: metadata(context: context),
            ),
          ),
          source.update(
            updateRequest(
              context: context,
              fields: [input('name', const TextDisplayValue('New'))],
            ),
          ),
          port.execute(operationRequest(context: context)),
        ];
        // Then admission errors precede any recorded call mutation or queued fault consumption.
        await Future.wait(
          attempts.map(
            (future) => expectLater(
              future,
              throwsA(isA<PresentationContextException>()),
            ),
          ),
        );
        expect(source.callCount, 0);
        expect(source.operationCallCount, 0);
        expect(source.resources.first.sourceRevision, 1);
        // Given invalid context left the queued update failure unconsumed.
        // When an admitted update probes that same queued failure.
        final updateProbe = source.update(updateRequest(fields: []));
        // Then the update receives the originally queued unavailable delivery.
        await expectLater(
          updateProbe,
          throwsA(transportFailure(DisplayTransportFailure.unavailable)),
        );
        // Given the separate Operation failure remains queued after the update probe.
        // When an admitted Operation probes its own queue.
        final operationProbe = port.execute(operationRequest());
        // Then the Operation receives its original failure with no source revision change.
        await expectLater(
          operationProbe,
          throwsA(transportFailure(DisplayTransportFailure.unavailable)),
        );
        expect(source.callCount, 1);
        expect(source.operationCallCount, 1);
        expect(source.resources.first.sourceRevision, 1);
      });
    }

    test('explicit optional omission follows current-time policy', () async {
      // Given an initially expired optional family which may be explicitly absent.
      final wire = fixtureWire();
      final context = neutralContext(expiredOptional: true);
      (wire['contexts'] as Map<String, Object?>)['neutral'] = context.toJson();
      final source = makeSource(wire: wire);
      final omitted = PresentationContext(
        flowId: context.flowId,
        sourceId: context.sourceId,
        componentId: context.componentId,
        families: context.families
            .where((family) => family.namespace != 'neutral.hints')
            .toList(),
      );
      // When a producer supplies the declared omission in its request context.
      final response = await readSource(source, context: omitted);
      // Then the response echoes exactly the admitted reduced context.
      expect(response.context, omitted);
      expect(source.callCount, 1);
    });

    test('expired fixture admits structurally but required expiry blocks at request time', () async {
      // Given a structurally valid fixture whose required family has expired.
      final wire = fixtureWire();
      (wire['contexts'] as Map<String, Object?>)['assigned'] = assignedContext(
        expired: true,
      ).toJson();
      final source = makeSource(wire: wire);
      // When the expired declared flow is used with the injected UTC clock.
      final future = readSource(
        source,
        context: assignedContext(expired: true),
      );
      // Then constructor admission permits testing expiry but requests record no call.
      await expectLater(
        future,
        throwsA(
          isA<PresentationContextException>().having(
            (error) => error.code,
            'code',
            'expired',
          ),
        ),
      );
      expect(source.callCount, 0);
    });

    test('local clock and wrong resource type reject before recording or fault consumption', () async {
      // Given a clock that starts local and a pending query failure.
      var clock = DateTime(2026, 10, 2);
      final source = makeSource(clock: () => clock);
      source.failNextDisplay(
        DisplayRequestKind.query,
        FixtureTransportFault.unavailable,
      );
      // When the source is queried while its injected clock is local.
      final local = querySource(source);
      // Then clock admission rejects that request before delivery.
      await expectLater(local, throwsA(isA<PresentationContextException>()));
      // Given the pending query failure still untouched after clock rejection.
      clock = DateTime.utc(2026, 10, 2);
      // When the UTC source is queried with the wrong resource type.
      final wrong = source.query(
        DisplayQueryRequest(resourceType: 'other', metadata: metadata()),
      );
      // Then resource-type admission rejects without records or fault consumption.
      await expectLater(wrong, throwsFormatException);
      expect(source.callCount, 0);
      expect(source.resources.first.sourceRevision, 1);
      // Given the queued query failure survived both admission errors.
      // When a correct UTC request reaches the public query port.
      final admitted = querySource(source);
      // Then that request receives the original queued unavailable delivery.
      await expectLater(
        admitted,
        throwsA(transportFailure(DisplayTransportFailure.unavailable)),
      );
      expect(source.callCount, 1);
    });
  });
}

Matcher transportFailure(DisplayTransportFailure failure) =>
    isA<DisplayTransportException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

PresentationContext neutralContext({
  String source = 'neutral-source',
  String component = 'neutral-component',
  String flow = 'neutral-flow',
  String attempt = 'attempt-1',
  bool expiredOptional = false,
  bool requiredUnknown = false,
}) => PresentationContext(
  flowId: flow,
  sourceId: source,
  componentId: component,
  families: [
    PresentationContextFamily(
      namespace: 'textus.presentation.locale',
      version: 1,
      producerId: 'neutral-producer',
      isRequired: false,
      expiresAt: null,
      payload: LocalePresentationPayload(localeTag: 'en-GB'),
    ),
    PresentationContextFamily(
      namespace: 'textus.presentation.correlation',
      version: 1,
      producerId: 'neutral-producer',
      isRequired: false,
      expiresAt: null,
      payload: CorrelationPresentationPayload(
        flowReference: flow,
        attemptReference: attempt,
      ),
    ),
    if (expiredOptional || requiredUnknown)
      PresentationContextFamily(
        namespace: 'neutral.hints',
        version: 1,
        producerId: 'neutral-producer',
        isRequired: requiredUnknown,
        expiresAt: expiredOptional ? DateTime.utc(2026, 10, 1) : null,
        payload: OpaquePresentationPayload({'density': 'wide'}),
      ),
  ],
);

PresentationContext assignedContext({
  String assignment = 'supplied-reference',
  bool expired = false,
  int version = 1,
}) => PresentationContext(
  flowId: 'assigned-flow',
  sourceId: 'neutral-source',
  componentId: 'neutral-component',
  families: [
    PresentationContextFamily(
      namespace: 'textus.presentation.arm',
      version: version,
      producerId: 'neutral-producer',
      isRequired: true,
      expiresAt: expired ? DateTime.utc(2026, 10, 1) : null,
      payload: version == 1
          ? SuppliedArmPresentationPayload(
              namespace: 'neutral.presentation',
              presentationSet: 'resources',
              armId: 'supplied',
              definitionVersion: 1,
              assignmentReference: assignment,
            )
          : OpaquePresentationPayload({'future': true}),
    ),
  ],
);

FixtureDisplaySource makeSource({
  Map<String, Object?>? wire,
  DisplayPrototypeFixture? fixture,
  DateTime Function()? clock,
}) => FixtureDisplaySource(
  fixture: fixture ?? DisplayPrototypeFixture.fromJson(wire ?? fixtureWire()),
  listTemplateId: 'rows',
  detailTemplateId: 'entry',
  componentId: 'neutral-component',
  contextPolicy: PresentationContextPolicy(
    allowedProducerIds: {'neutral-producer'},
  ),
  nowUtc: clock ?? () => DateTime.utc(2026, 10, 2),
);
DisplayRequestMetadata metadata({
  int? revision,
  PresentationContext? context,
}) => DisplayRequestMetadata(
  context: context ?? neutralContext(),
  observedRevision: revision,
);
DisplayFieldInput input(
  String id,
  DisplayValue value, {
  String screen = 'detail',
  String section = 'body',
}) => DisplayFieldInput(
  locator: DisplayFieldLocator(
    screenId: screen,
    sectionId: section,
    fieldId: id,
  ),
  value: value,
);
DisplayUpdateRequest updateRequest({
  int revision = 1,
  String id = 'first',
  PresentationContext? context,
  required List<DisplayFieldInput> fields,
}) => DisplayUpdateRequest(
  resourceType: 'neutral-type',
  resourceId: id,
  metadata: metadata(revision: revision, context: context),
  fields: fields,
);
Future<DisplayMutationResponse> updateSource(
  FixtureDisplaySource source, {
  int revision = 1,
  String id = 'first',
  PresentationContext? context,
  required List<DisplayFieldInput> fields,
}) async => DisplayMutationResponse.fromJson(
  await source.update(
    updateRequest(revision: revision, id: id, context: context, fields: fields),
  ),
);
Future<DisplayListResponse> querySource(FixtureDisplaySource source) async =>
    DisplayListResponse.fromJson(
      await source.query(
        DisplayQueryRequest(resourceType: 'neutral-type', metadata: metadata()),
      ),
    );
Future<DisplayDetailResponse> readSource(
  FixtureDisplaySource source, {
  String id = 'first',
  PresentationContext? context,
}) async => DisplayDetailResponse.fromJson(
  await source.read(
    DisplayReadRequest(
      resourceType: 'neutral-type',
      resourceId: id,
      metadata: metadata(context: context),
    ),
  ),
);
OrdinaryOperationRequest operationRequest({
  int revision = 1,
  String id = 'first',
  String operation = 'advance',
  PresentationContext? context,
}) => OrdinaryOperationRequest(
  operationId: operation,
  resourceId: id,
  metadata: metadata(revision: revision, context: context),
);
DisplayValue fieldValue(DisplayDetailResponse response, String id) => response
    .data
    .model
    .sections
    .single
    .fields
    .firstWhere((field) => field.id == id)
    .value;
Map<String, Object?> seedObject(Map<String, Object?> wire) =>
    (wire['semanticSeed'] as List<Object?>).first as Map<String, Object?>;
Map<String, Object?> semanticFields(Map<String, Object?> wire) =>
    seedObject(wire)['fields'] as Map<String, Object?>;
List<Object?> projectionFields(Map<String, Object?> wire) =>
    (wire['projectionBindings'] as Map<String, Object?>)['fields']
        as List<Object?>;
Map<String, Object?> fieldBinding(Map<String, Object?> wire, {int index = 0}) =>
    projectionFields(wire)[index] as Map<String, Object?>;
Map<String, Object?> operationBinding(Map<String, Object?> wire) =>
    (wire['operationBindings'] as Map<String, Object?>)['advance']
        as Map<String, Object?>;

List<Object?> detailFields(Map<String, Object?> wire) {
  final responses = wire['displayResponses'] as Map<String, Object?>;
  final data =
      (responses['entry'] as Map<String, Object?>)['data']
          as Map<String, Object?>;
  final model = data['model'] as Map<String, Object?>;
  final section =
      (model['sections'] as List<Object?>).single as Map<String, Object?>;
  return section['fields'] as List<Object?>;
}

List<Object?> listRowFields(Map<String, Object?> wire) {
  final responses = wire['displayResponses'] as Map<String, Object?>;
  final data =
      (responses['rows'] as Map<String, Object?>)['data']
          as Map<String, Object?>;
  final model = data['model'] as Map<String, Object?>;
  final row = (model['items'] as List<Object?>).first as Map<String, Object?>;
  return row['fields'] as List<Object?>;
}

Map<String, Object?> writableAliasWire() {
  final wire = fixtureWire();
  fieldBinding(wire, index: 2)['semanticField'] = 'name';
  return wire;
}

Map<String, Object?> fixtureWire() {
  final context = neutralContext();
  final fields = [
    DisplayField(
      id: 'name',
      label: 'Name',
      role: 'title',
      value: const TextDisplayValue('Template'),
    ),
    DisplayField(
      id: 'status',
      label: 'State',
      role: 'status',
      value: const TextDisplayValue('Old label'),
    ),
    DisplayField(
      id: 'note',
      label: 'Note',
      role: 'description',
      value: const TextDisplayValue('Template note'),
    ),
    DisplayField(
      id: 'count',
      label: 'Count',
      role: 'number',
      value: NumberDisplayValue(99),
    ),
  ];
  final detail = DisplayDetailResponse(
    context: context,
    data: DisplayDetailData(
      resourceId: 'template-only',
      sourceRevision: 99,
      provenance: DisplayProvenance(
        producerId: 'detail-producer',
        sourceId: 'neutral-source',
        revision: '99',
      ),
      bindings: [],
      model: DisplayDetailModel(
        screenId: 'detail',
        title: 'Resource',
        sections: [DisplaySection(id: 'body', fields: fields)],
        actions: [
          DisplayAction(id: 'advance', label: 'Advance', enabled: false),
        ],
      ),
    ),
  );
  final list = DisplayListResponse(
    context: context,
    data: DisplayListData(
      resourceType: 'neutral-type',
      snapshotId: 'template-snapshot',
      provenance: DisplayProvenance(
        producerId: 'list-producer',
        sourceId: 'neutral-source',
        revision: 'template-snapshot',
      ),
      model: DisplayListModel(
        screenId: 'collection',
        title: 'Collection',
        detailScreenId: 'detail',
        items: [
          DisplayResourceSummary(
            resourceId: 'template-only',
            sourceRevision: 99,
            fields: [fields[0], fields[1]],
          ),
        ],
      ),
    ),
  );
  final wire = <String, Object?>{
    'schema': 'textus.display.fixture.v1',
    'reference': {
      'sampleId': 'neutral-source',
      'sampleRevision': 1,
      'provisionalVersion': 1,
      'developmentOnly': true,
    },
    'resourceType': 'neutral-type',
    'contexts': {
      'neutral': context.toJson(),
      'assigned': assignedContext().toJson(),
    },
    'displayResponses': {'rows': list.toJson(), 'entry': detail.toJson()},
    'operationResponses': <String, Object?>{},
    'semanticSeed': [
      {
        'resourceId': 'first',
        'sourceRevision': 1,
        'fields': {
          'name': const TextDisplayValue('Original').toJson(),
          'note': const TextDisplayValue('Note').toJson(),
          'state': const TextDisplayValue('ready').toJson(),
          'count': NumberDisplayValue(7).toJson(),
        },
      },
      {
        'resourceId': 'second',
        'sourceRevision': 4,
        'fields': {
          'name': const TextDisplayValue('Another').toJson(),
          'note': const TextDisplayValue('Other note').toJson(),
          'state': const TextDisplayValue('done').toJson(),
          'count': NumberDisplayValue(8).toJson(),
        },
      },
    ],
    'projectionBindings': {
      'screenId': 'detail',
      'sectionId': 'body',
      'fields': [
        {
          'fieldId': 'name',
          'semanticField': 'name',
          'writable': true,
          'requiredNonBlank': true,
        },
        {
          'fieldId': 'status',
          'semanticField': 'state',
          'writable': false,
          'requiredNonBlank': false,
          'lookup': {'ready': 'Ready label', 'done': 'Done label'},
        },
        {
          'fieldId': 'note',
          'semanticField': 'note',
          'writable': true,
          'requiredNonBlank': false,
        },
        {
          'fieldId': 'count',
          'semanticField': 'count',
          'writable': false,
          'requiredNonBlank': false,
        },
      ],
    },
    'operationBindings': {
      'advance': {
        'developmentOnly': true,
        'inputFields': ['resourceId'],
        'expected': {'state': 'ready'},
        'transition': {'state': 'done'},
      },
    },
  };
  return Map<String, Object?>.from(jsonDecode(jsonEncode(wire)) as Map);
}
