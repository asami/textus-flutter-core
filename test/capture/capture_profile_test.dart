import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('an external profile declares custom types, hints, and validation', () {
    // Given a session and a consumer-defined profile contract.
    final session = _session();
    final profile = CaptureProfile(
      id: CaptureProfileId('field-observation'),
      itemTypes: <CaptureItemType>[CaptureItemType('field-note')],
      workflowHints: CaptureWorkflowHints(<String, String>{'entry': 'guided'}),
      presentationHints: CapturePresentationHints(<String, String>{
        'label': 'Field note',
      }),
      validators: <CaptureProfileValidator>[
        (CaptureSession current) => current.items.isEmpty
            ? <CaptureProfileValidationIssue>[
                CaptureProfileValidationIssue(
                  code: 'item-required',
                  message: 'Add at least one field note.',
                ),
              ]
            : const <CaptureProfileValidationIssue>[],
      ],
    );

    // When the external profile validates the existing session.
    final issues = profile.validate(session);

    // Then its custom contract is available and the session satisfies it.
    expect(profile.id, CaptureProfileId('field-observation'));
    expect(profile.itemTypes, <CaptureItemType>[CaptureItemType('field-note')]);
    expect(profile.workflowHints!.values['entry'], 'guided');
    expect(profile.presentationHints!.values['label'], 'Field note');
    expect(issues, isEmpty);
  });

  test(
    'validation preserves validator order and optional item association',
    () {
      // Given a profile with two ordered validators and an existing session.
      final session = _session();
      final first = CaptureProfileValidationIssue(
        code: 'session-warning',
        message: 'Review the session.',
      );
      final second = CaptureProfileValidationIssue(
        code: 'item-warning',
        message: 'Review the item.',
        itemId: CaptureItemId('item-1'),
      );
      final profile = CaptureProfile(
        id: CaptureProfileId('ordered-validation'),
        itemTypes: <CaptureItemType>[CaptureItemType('field-note')],
        validators: <CaptureProfileValidator>[
          (_) => <CaptureProfileValidationIssue>[first],
          (_) => <CaptureProfileValidationIssue>[second],
        ],
      );

      // When the profile aggregates its validator results.
      final issues = profile.validate(session);

      // Then issue order and the optional item association are retained.
      expect(issues, <CaptureProfileValidationIssue>[first, second]);
      expect(issues[0].itemId, isNull);
      expect(issues[1].itemId, CaptureItemId('item-1'));
    },
  );

  test('profile inputs and validation results are defensive snapshots', () {
    // Given mutable inputs used to construct a profile and its validation.
    final itemTypes = <CaptureItemType>[CaptureItemType('field-note')];
    final validators = <CaptureProfileValidator>[
      (_) => <CaptureProfileValidationIssue>[
        CaptureProfileValidationIssue(
          code: 'review',
          message: 'Review the field note.',
        ),
      ],
    ];
    final workflowValues = <String, String>{'entry': 'guided'};
    final presentationValues = <String, String>{'label': 'Field note'};
    final profile = CaptureProfile(
      id: CaptureProfileId('immutable-profile'),
      itemTypes: itemTypes,
      validators: validators,
      workflowHints: CaptureWorkflowHints(workflowValues),
      presentationHints: CapturePresentationHints(presentationValues),
    );

    // When the sources change and consumers attempt to mutate snapshots.
    itemTypes.add(CaptureItemType('photo'));
    validators.clear();
    workflowValues['entry'] = 'freeform';
    presentationValues['label'] = 'Changed';
    final issues = profile.validate(_session());

    // Then the profile and validation result snapshots remain immutable.
    expect(profile.itemTypes, <CaptureItemType>[CaptureItemType('field-note')]);
    expect(profile.validators, hasLength(1));
    expect(profile.workflowHints!.values['entry'], 'guided');
    expect(profile.presentationHints!.values['label'], 'Field note');
    expect(
      () => profile.itemTypes.add(CaptureItemType('photo')),
      throwsUnsupportedError,
    );
    expect(() => profile.validators.clear(), throwsUnsupportedError);
    expect(
      () => profile.workflowHints!.values['entry'] = 'freeform',
      throwsUnsupportedError,
    );
    expect(
      () => profile.presentationHints!.values['label'] = 'Changed',
      throwsUnsupportedError,
    );
    expect(() => issues.add(issues.single), throwsUnsupportedError);
  });

  test('invalid profile declarations and issue values are rejected', () {
    // Given invalid profile and validation-issue inputs.
    CaptureProfile emptyTypes() => CaptureProfile(
      id: CaptureProfileId('empty-types'),
      itemTypes: const <CaptureItemType>[],
    );
    CaptureProfile duplicateTypes() => CaptureProfile(
      id: CaptureProfileId('duplicate-types'),
      itemTypes: <CaptureItemType>[
        CaptureItemType('field-note'),
        CaptureItemType('field-note'),
      ],
    );

    // When each invalid input is used to create its public contract.
    CaptureProfileId blankProfileId() => CaptureProfileId('  ');
    CaptureProfileValidationIssue blankIssueCode() =>
        CaptureProfileValidationIssue(code: ' ', message: 'A message.');
    CaptureProfileValidationIssue blankIssueMessage() =>
        CaptureProfileValidationIssue(code: 'issue', message: ' ');

    // Then each rejected invariant reports an argument error.
    expect(emptyTypes, throwsArgumentError);
    expect(duplicateTypes, throwsArgumentError);
    expect(blankProfileId, throwsArgumentError);
    expect(blankIssueCode, throwsArgumentError);
    expect(blankIssueMessage, throwsArgumentError);
  });
}

CaptureSession _session() {
  return CaptureSession(
    id: CaptureSessionId('session-1'),
    lifecycle: CaptureSessionLifecycle.draft,
    items: <CaptureItem>[
      CaptureItem(
        id: CaptureItemId('item-1'),
        type: CaptureItemType('field-note'),
        content: const TextCaptureContent('observation'),
        metadata: CaptureMetadata(<String, String>{}),
        provenance: CaptureProvenance(
          source: CaptureProvenanceSource('manual-entry'),
          recordedAt: DateTime.utc(2026, 9, 16),
          data: <String, String>{},
        ),
      ),
    ],
    createdAt: DateTime.utc(2026, 9, 16),
    updatedAt: DateTime.utc(2026, 9, 16),
  );
}
