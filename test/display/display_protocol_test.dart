import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('typed Display values', () {
    test('typed values roundtrip preserving empty and Unicode bytes', () {
      // Given fresh typed values, including whitespace, combining marks and lines.
      final values = <DisplayValue>[
        const TextDisplayValue(''),
        const TextDisplayValue('  日本\ne\u0301  '),
        NumberDisplayValue(1.5),
        const BoolDisplayValue(true),
        TimestampDisplayValue(DateTime.utc(2026, 10, 2)),
        const MissingDisplayValue(),
      ];
      for (final value in values) {
        // When the public candidate codec roundtrips each value.
        final decoded = DisplayValue.fromJson(value.toJson());
        // Then value equality, hashing and encoded text bytes are preserved.
        expect(decoded, value);
        expect(decoded.hashCode, value.hashCode);
        expect(
          utf8.encode(jsonEncode(decoded.toJson())),
          utf8.encode(jsonEncode(value.toJson())),
        );
      }
    });

    test(
      'value codec rejects wrong types schemas numbers and invalid instants',
      () {
        // Given malformed values including normalization-prone calendar dates.
        final wires = <Map<String, Object?>>[
          {'type': 'text', 'value': null},
          {'type': 'number', 'value': true},
          {'type': 'number', 'value': double.infinity},
          {'type': 'bool', 'value': 1},
          {'type': 'missing', 'value': null},
          {'type': 'text'},
          {'type': 'text', 'value': '', 'extra': 1},
          {'type': 'unknown', 'value': ''},
          {'type': 'timestamp', 'value': '2026-02-30T00:00:00Z'},
          {'type': 'timestamp', 'value': '2026-01-01T24:00:00Z'},
          {'type': 'timestamp', 'value': '2026-01-01T00:00:00+00:00'},
          {'type': 'timestamp', 'value': '2026-01-01'},
        ];
        for (final wire in wires) {
          // When an invalid value is decoded.
          DisplayValue action() => DisplayValue.fromJson(wire);
          // Then the codec rejects instead of coercing or normalizing.
          expect(action, throwsFormatException);
        }
        // Given a local constructor timestamp and a nonfinite number.
        final local = DateTime(2026, 10, 2);
        // When constructors receive these invalid typed inputs.
        final actions = [
          () => TimestampDisplayValue(local),
          () => NumberDisplayValue(double.nan),
        ];
        // Then constructors enforce the same value contract.
        for (final action in actions) {
          expect(action, throwsFormatException);
        }
      },
    );
  });

  group('Display projections and scoped identity', () {
    test(
      'list keeps ordered summaries without eager Detail and checks provenance',
      () {
        // Given two ordered neutral rows and an explicit snapshot.
        final data = listData();
        // When list data passes through the public codec.
        final decoded = DisplayListData.fromJson(data.toJson());
        // Then ordering, row revisions, logical target and snapshot stay distinct.
        expect(decoded.model.items.map((item) => item.resourceId), [
          'r1',
          'r2',
        ]);
        expect(decoded.model.items.map((item) => item.sourceRevision), [1, 1]);
        expect(decoded.model.detailScreenId, 'detail');
        expect(decoded.provenance.revision, 'snapshot-1');
        expect(decoded.model.items.first.toJson().keys, [
          'resourceId',
          'sourceRevision',
          'fields',
        ]);
        // Given mismatched provenance and an extra eager-detail row member.
        final bad = data.toJson();
        final metadata = bad['metadata'] as Map<String, Object?>;
        metadata['snapshotId'] = 'other';
        final row = data.model.items.first.toJson()
          ..['detail'] = detailData().toJson();
        // When these inconsistent shapes are decoded.
        final actions = [
          () => DisplayListData.fromJson(bad),
          () => DisplayResourceSummary.fromJson(row),
        ];
        // Then provenance mismatch and eager Detail are rejected.
        for (final action in actions) {
          expect(action, throwsFormatException);
        }
      },
    );

    test(
      'scoped repeated fields resolve while same-scope duplicates reject',
      () {
        // Given repeated title IDs in different sections with distinct scoped inputs.
        final data = detailData(secondSection: true);
        // When Detail and locator codecs roundtrip.
        final decoded = DisplayDetailData.fromJson(data.toJson());
        final locator = decoded.bindings.first.locator;
        // Then the exact scoped identity resolves and metadata stays outside fields.
        expect(decoded.bindings.length, 2);
        expect(decoded.model.sections.length, 2);
        expect(DisplayFieldLocator.fromJson(locator.toJson()), locator);
        expect(
          DisplayFieldLocator.fromJson(locator.toJson()).hashCode,
          locator.hashCode,
        );
        expect(decoded.model.sections.first.fields.first.toJson().keys, [
          'id',
          'label',
          'role',
          'value',
        ]);
        expect(
          decoded.bindings.first.inputValue,
          const TextDisplayValue('semantic'),
        );
        // Given duplicate fields, sections, actions, resources and invalid bindings.
        final field = neutralField();
        final binding = data.bindings.first;
        // When constructors attempt ambiguous or unresolved identities.
        final actions = [
          () => DisplaySection(id: 's', fields: [field, field]),
          () => DisplayResourceSummary(
            resourceId: 'r',
            sourceRevision: 1,
            fields: [field, field],
          ),
          () => DisplayDetailModel(
            screenId: 'detail',
            title: '',
            sections: [data.model.sections.first, data.model.sections.first],
            actions: [],
          ),
          () => DisplayDetailModel(
            screenId: 'detail',
            title: '',
            sections: [],
            actions: [
              DisplayAction(id: 'a', label: '', enabled: true),
              DisplayAction(id: 'a', label: '', enabled: false),
            ],
          ),
          () => DisplayListModel(
            screenId: 'list',
            title: '',
            detailScreenId: 'detail',
            items: [listData().model.items.first, listData().model.items.first],
          ),
          () => DisplayDetailData(
            resourceId: 'r1',
            sourceRevision: 1,
            provenance: provenance('1'),
            bindings: [binding, binding],
            model: data.model,
          ),
          () => detailData(bindingScreen: 'wrong'),
          () => detailData(bindingSection: 'missing'),
          () => DisplayEditBinding(
            locator: binding.locator,
            writable: false,
            inputValue: const TextDisplayValue('derived'),
            requiredNonBlank: false,
          ),
        ];
        // Then every same-scope duplicate or inconsistent binding rejects.
        for (final action in actions) {
          expect(action, throwsFormatException);
        }
      },
    );

    test(
      'positive source revisions and exact Detail provenance are required',
      () {
        // Given noninteger/zero revisions and a mismatched Detail provenance.
        final zero = detailData().toJson();
        (zero['metadata'] as Map<String, Object?>)['sourceRevision'] = 0;
        final decimal = detailData().toJson();
        (decimal['metadata'] as Map<String, Object?>)['sourceRevision'] = 1.0;
        final wrong = detailData().toJson();
        ((wrong['metadata'] as Map<String, Object?>)['provenance']
                as Map<String, Object?>)['revision'] =
            '2';
        // When these Detail data shapes decode.
        final actions = [
          () => DisplayDetailData.fromJson(zero),
          () => DisplayDetailData.fromJson(decimal),
          () => DisplayDetailData.fromJson(wrong),
        ];
        // Then source revisions cannot be substituted by another identity or type.
        for (final action in actions) {
          expect(action, throwsFormatException);
        }
      },
    );

    test('closed model codecs reject missing and extra members', () {
      // Given each public known object decoder and its minimal valid wire.
      final cases =
          <(Map<String, Object?>, Object Function(Map<String, Object?>))>[
            (neutralField().toJson(), DisplayField.fromJson),
            (
              DisplaySection(id: 's', fields: []).toJson(),
              DisplaySection.fromJson,
            ),
            (
              DisplayAction(id: 'a', label: '', enabled: true).toJson(),
              DisplayAction.fromJson,
            ),
            (provenance('1').toJson(), DisplayProvenance.fromJson),
            (detailData().bindings.first.toJson(), DisplayEditBinding.fromJson),
            (listData().model.toJson(), DisplayListModel.fromJson),
            (detailData().model.toJson(), DisplayDetailModel.fromJson),
            (
              DisplayFieldError(
                locator: null,
                code: 'global',
                message: '',
              ).toJson(),
              DisplayFieldError.fromJson,
            ),
          ];
      for (final (wire, decode) in cases) {
        // When a known shape gains an extra member or loses a mandatory member.
        final extra = {...wire, 'unexpected': true};
        final missing = {...wire}..remove(wire.keys.first);
        // Then both shapes reject through public codecs.
        expect(() => decode(extra), throwsFormatException);
        expect(() => decode(missing), throwsFormatException);
      }
    });
  });

  group('Display mutation receipts', () {
    test(
      'mutation receipts distinguish fresh pending noop and failure outcomes',
      () {
        // Given fresh, stale and absent projections of a committed revision plus failures.
        final results = [
          receipt(
            DisplayCommandOutcome.changed,
            current: 2,
            committed: 2,
            display: detailData(revision: 2),
          ),
          receipt(
            DisplayCommandOutcome.changed,
            current: 2,
            committed: 2,
            display: detailData(),
          ),
          receipt(DisplayCommandOutcome.changed, current: 2, committed: 2),
          receipt(
            DisplayCommandOutcome.noOp,
            current: 2,
            display: detailData(revision: 2),
          ),
          receipt(DisplayCommandOutcome.rejected),
          receipt(DisplayCommandOutcome.conflict, current: 2),
          receipt(DisplayCommandOutcome.unsupported),
        ];
        // When each receipt roundtrips.
        final decoded = results
            .map((result) => DisplayMutationResult.fromJson(result.toJson()))
            .toList();
        // Then stale projection never invalidates the successful receipt.
        expect(
          decoded.map((result) => result.outcome),
          results.map((result) => result.outcome),
        );
        expect(decoded[1].committedRevision, 2);
        expect(decoded[1].display!.sourceRevision, 1);
        expect(decoded[2].display, isNull);
        expect(decoded[3].toJson()['outcome'], 'noop');
        expect(
          decoded
              .skip(4)
              .every(
                (result) =>
                    result.display == null && result.committedRevision == null,
              ),
          isTrue,
        );
      },
    );

    test('inconsistent mutation receipts and resource identity reject', () {
      // Given outcome/revision combinations that cannot be valid receipts.
      final actions = [
        () => receipt(DisplayCommandOutcome.changed, current: 2),
        () => receipt(DisplayCommandOutcome.changed, current: 1, committed: 2),
        () => receipt(DisplayCommandOutcome.noOp),
        () => receipt(DisplayCommandOutcome.noOp, current: 2, committed: 2),
        () => receipt(DisplayCommandOutcome.conflict),
        () => receipt(DisplayCommandOutcome.rejected, display: detailData()),
        () => receipt(DisplayCommandOutcome.unsupported, committed: 1),
        () => DisplayMutationResult(
          resourceId: 'other',
          outcome: DisplayCommandOutcome.changed,
          currentRevision: 2,
          committedRevision: 2,
          fieldErrors: [],
          message: null,
          display: detailData(),
        ),
        () => DisplayMutationResult.fromJson({
          ...receipt(DisplayCommandOutcome.rejected).toJson(),
          'outcome': 'unknown',
        }),
      ];
      for (final action in actions) {
        Object? observedfailure;
        // When constructing or decoding these receipts.
        try {
          action();
        } catch (error) {
          observedfailure = error;
        }
        // Then no invalid command receipt is accepted.
        expect(observedfailure, isA<FormatException>());
      }
    });
  });

  group('ordinary Operation receipts', () {
    test('ordinary Operation receipt cannot include Display or noop', () {
      // Given a successful ordinary Operation receipt.
      final result = DisplayOperationResult(
        resourceId: 'r1',
        outcome: DisplayCommandOutcome.changed,
        currentRevision: 3,
        committedRevision: 3,
        fieldErrors: [],
        message: null,
      );
      // When its closed codec roundtrips.
      final decoded = DisplayOperationResult.fromJson(result.toJson());
      // Then success carries revision only and forbids implicit reload.
      expect(decoded.committedRevision, 3);
      expect(decoded.toJson().containsKey('display'), isFalse);
      expect(
        () => DisplayOperationResult.fromJson({
          ...result.toJson(),
          'display': detailData().toJson(),
        }),
        throwsFormatException,
      );
      expect(
        () => DisplayOperationResult(
          resourceId: 'r1',
          outcome: DisplayCommandOutcome.noOp,
          currentRevision: 3,
          committedRevision: null,
          fieldErrors: [],
          message: null,
        ),
        throwsFormatException,
      );
    });
  });

  group('Display response envelopes', () {
    test(
      'response envelopes reject wrong schema kind body source and extra keys',
      () {
        // Given a fresh neutral context and valid List/Detail envelopes.
        final context = PresentationContext(
          flowId: 'f',
          sourceId: 'source',
          componentId: 'component',
          families: [],
        );
        final list = DisplayListResponse(
          context: context,
          data: listData(),
        ).toJson();
        final detail = DisplayDetailResponse(
          context: context,
          data: detailData(),
        ).toJson();
        // When valid envelopes decode.
        final decoded = DisplayDetailResponse.fromJson(detail);
        // Then the public envelope preserves context and resource data.
        expect(decoded.context, context);
        expect(
          DisplayListResponse.fromJson(list).data.snapshotId,
          'snapshot-1',
        );
        // Given malformed envelope/schema/body/source variants.
        final other = PresentationContext(
          flowId: 'f',
          sourceId: 'other',
          componentId: 'component',
          families: [],
        );
        // When decoding or constructing these incompatible envelopes.
        final actions = [
          () => DisplayListResponse.fromJson({...list, 'schema': 'production'}),
          () => DisplayListResponse.fromJson({...list, 'kind': 'detail'}),
          () => DisplayDetailResponse.fromJson({...detail, 'extra': 1}),
          () => DisplayDetailResponse.fromJson({...detail, 'data': {}}),
          () => DisplayDetailResponse(context: other, data: detailData()),
          () => DisplayMutationResponse.fromJson({
            'schema': 'textus.display.prototype.v1',
            'kind': 'mutation',
            'context': context.toJson(),
            'data': {},
          }),
          () => OrdinaryOperationResponse.fromJson({
            'schema': 'wrong',
            'context': context.toJson(),
            'result': {},
          }),
        ];
        // Then every incompatible response is rejected before use.
        for (final action in actions) {
          expect(action, throwsFormatException);
        }
      },
    );
  });
}

DisplayField neutralField() => DisplayField(
  id: 'title',
  label: 'Title',
  role: 'title',
  value: const TextDisplayValue('projected'),
);
DisplayProvenance provenance(String revision) => DisplayProvenance(
  producerId: 'producer',
  sourceId: 'source',
  revision: revision,
);
DisplayDetailData detailData({
  int revision = 1,
  bool secondSection = false,
  String bindingScreen = 'detail',
  String bindingSection = 'main',
}) => DisplayDetailData(
  resourceId: 'r1',
  sourceRevision: revision,
  provenance: provenance('$revision'),
  bindings: [
    for (final section in ['main', if (secondSection) 'other'])
      DisplayEditBinding(
        locator: DisplayFieldLocator(
          screenId: bindingScreen,
          sectionId: section == 'main' ? bindingSection : section,
          fieldId: 'title',
        ),
        writable: true,
        inputValue: const TextDisplayValue('semantic'),
        requiredNonBlank: true,
      ),
  ],
  model: DisplayDetailModel(
    screenId: 'detail',
    title: 'Detail',
    sections: [
      for (final id in ['main', if (secondSection) 'other'])
        DisplaySection(id: id, fields: [neutralField()]),
    ],
    actions: [],
  ),
);
DisplayListData listData() => DisplayListData(
  resourceType: 'neutral',
  snapshotId: 'snapshot-1',
  provenance: provenance('snapshot-1'),
  model: DisplayListModel(
    screenId: 'list',
    title: 'List',
    detailScreenId: 'detail',
    items: [
      for (final id in ['r1', 'r2'])
        DisplayResourceSummary(
          resourceId: id,
          sourceRevision: 1,
          fields: [neutralField()],
        ),
    ],
  ),
);
DisplayMutationResult receipt(
  DisplayCommandOutcome outcome, {
  int? current,
  int? committed,
  DisplayDetailData? display,
}) => DisplayMutationResult(
  resourceId: 'r1',
  outcome: outcome,
  currentRevision: current,
  committedRevision: committed,
  fieldErrors: [],
  message: null,
  display: display,
);
