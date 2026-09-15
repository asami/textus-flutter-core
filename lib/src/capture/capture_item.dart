import 'capture_identifiers.dart';

/// The sealed content carried by a [CaptureItem].
sealed class CaptureItemContent {
  /// Creates content for a captured item.
  const CaptureItemContent();
}

/// Text captured for an item.
///
/// [text] may be empty while an application is editing a draft.
final class TextCaptureContent extends CaptureItemContent {
  /// Creates text content, including empty draft text.
  const TextCaptureContent(this.text);

  /// The captured or draft text.
  final String text;
}

/// A reference to media associated with an item.
final class MediaReferenceCaptureContent extends CaptureItemContent {
  /// Creates a media reference from a non-blank URI [value].
  MediaReferenceCaptureContent(String value) : uri = _requireUri(value);

  /// The non-blank URI string that references the media.
  final String uri;
}

/// Immutable, domain-independent item captured within a session.
final class CaptureItem {
  /// Creates a capture item from its identity, open item type, content, and
  /// associated metadata and provenance.
  const CaptureItem({
    required this.id,
    required this.type,
    required this.content,
    required this.metadata,
    required this.provenance,
  });

  /// The identifier unique within its containing session.
  final CaptureItemId id;

  /// The open application-defined type of this item.
  final CaptureItemType type;

  /// The item's captured content.
  final CaptureItemContent content;

  /// Immutable descriptive data for the item.
  final CaptureMetadata metadata;

  /// Immutable source and timing information for the item.
  final CaptureProvenance provenance;
}

String _requireUri(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, 'value', 'must not be blank');
  }
  return value;
}
