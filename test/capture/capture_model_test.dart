import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('public library exposes the capture model contracts', () {
    // Given a consumer that imports only the package entry point.
    final source = CaptureProvenanceSource('manual-entry');

    // When it creates an externally defined item type and text content.
    final itemType = CaptureItemType('field-note');
    final content = TextCaptureContent('observation');

    // Then those public model contracts are available without a src import.
    expect(source.value, 'manual-entry');
    expect(itemType.value, 'field-note');
    expect(content.text, 'observation');
  });

  test('value objects compare by value and reject blank values', () {
    // Given identifiers and open value types created with matching values.
    final sessionId = CaptureSessionId('session-1');
    final itemId = CaptureItemId('item-1');
    final itemType = CaptureItemType('custom-note');
    final source = CaptureProvenanceSource('user-entry');

    // When their matching counterparts are constructed independently.
    final matchingSessionId = CaptureSessionId('session-1');
    final matchingItemId = CaptureItemId('item-1');
    final matchingItemType = CaptureItemType('custom-note');
    final matchingSource = CaptureProvenanceSource('user-entry');

    // Then equality is value-based and blank identifiers are rejected.
    expect(sessionId, matchingSessionId);
    expect(itemId, matchingItemId);
    expect(itemType, matchingItemType);
    expect(source, matchingSource);
    expect(() => CaptureSessionId('  '), throwsArgumentError);
    expect(() => MediaReferenceCaptureContent(''), throwsArgumentError);
  });

  test('a session rejects duplicate item identifiers', () {
    // Given two independently created items with the same identifier value.
    final first = _item('duplicate-item');
    final second = _item('duplicate-item');

    // When they are used to construct the same session.
    CaptureSession createSession() => CaptureSession(
      id: CaptureSessionId('session-1'),
      lifecycle: CaptureSessionLifecycle.draft,
      items: <CaptureItem>[first, second],
      createdAt: DateTime.utc(2026, 9, 16),
      updatedAt: DateTime.utc(2026, 9, 16),
    );

    // Then the duplicate identifier is rejected.
    expect(createSession, throwsArgumentError);
  });

  test('lifecycle and item replacements leave prior sessions unchanged', () {
    // Given a draft session with one captured item.
    final original = CaptureSession(
      id: CaptureSessionId('session-1'),
      lifecycle: CaptureSessionLifecycle.draft,
      items: <CaptureItem>[_item('item-1')],
      createdAt: DateTime.utc(2026, 9, 16),
      updatedAt: DateTime.utc(2026, 9, 16),
    );

    // When explicit lifecycle and item replacements are requested.
    final ready = original.withLifecycle(
      CaptureSessionLifecycle.readyForSubmission,
      updatedAt: DateTime.utc(2026, 9, 16, 1),
    );
    final replaced = ready.withItems(<CaptureItem>[
      _item('item-2'),
    ], updatedAt: DateTime.utc(2026, 9, 16, 2));

    // Then each earlier session remains immutable and unchanged.
    expect(original.lifecycle, CaptureSessionLifecycle.draft);
    expect(original.items.single.id, CaptureItemId('item-1'));
    expect(ready.lifecycle, CaptureSessionLifecycle.readyForSubmission);
    expect(replaced.items.single.id, CaptureItemId('item-2'));
    expect(replaced.updatedAt, DateTime.utc(2026, 9, 16, 2));
  });

  test('collection data is defensively copied and exposed immutably', () {
    // Given mutable data and item collections used to create model values.
    final metadataData = <String, String>{'label': 'initial'};
    final provenanceData = <String, String>{'origin': 'draft'};
    final sessionItems = <CaptureItem>[_item('item-1')];
    final metadata = CaptureMetadata(metadataData);
    final provenance = CaptureProvenance(
      source: CaptureProvenanceSource('manual-entry'),
      recordedAt: DateTime.utc(2026, 9, 16),
      data: provenanceData,
    );
    final session = CaptureSession(
      id: CaptureSessionId('session-1'),
      lifecycle: CaptureSessionLifecycle.draft,
      items: sessionItems,
      createdAt: DateTime.utc(2026, 9, 16),
      updatedAt: DateTime.utc(2026, 9, 16),
    );

    // When the source collections are changed after construction.
    metadataData['label'] = 'changed';
    provenanceData['origin'] = 'changed';
    sessionItems.add(_item('item-2'));

    // Then snapshots retain their data and their public views cannot mutate.
    expect(metadata.data, <String, String>{'label': 'initial'});
    expect(provenance.data, <String, String>{'origin': 'draft'});
    expect(session.items, hasLength(1));
    expect(() => metadata.data['new'] = 'value', throwsUnsupportedError);
    expect(() => provenance.data['new'] = 'value', throwsUnsupportedError);
    expect(() => session.items.add(_item('item-3')), throwsUnsupportedError);
  });
}

CaptureItem _item(String id) {
  return CaptureItem(
    id: CaptureItemId(id),
    type: CaptureItemType('note'),
    content: const TextCaptureContent('draft'),
    metadata: CaptureMetadata(<String, String>{}),
    provenance: CaptureProvenance(
      source: CaptureProvenanceSource('manual-entry'),
      recordedAt: DateTime.utc(2026, 9, 16),
      data: <String, String>{},
    ),
  );
}
