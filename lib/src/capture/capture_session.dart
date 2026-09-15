import 'dart:collection';

import 'capture_identifiers.dart';
import 'capture_item.dart';

/// The lifecycle states of a capture session.
enum CaptureSessionLifecycle {
  /// The session is being assembled or edited.
  draft,

  /// The session has been prepared for submission by its consumer.
  readyForSubmission,

  /// The session was submitted by its consumer.
  submitted,

  /// The most recent submission attempt failed.
  submissionFailed,
}

/// Immutable collection of captured items and its lifecycle state.
final class CaptureSession {
  /// Creates a session with a defensive, duplicate-free copy of [items].
  CaptureSession({
    required this.id,
    required this.lifecycle,
    required Iterable<CaptureItem> items,
    required this.createdAt,
    required this.updatedAt,
  }) : _items = _copyValidatedItems(items);

  /// The session identifier.
  final CaptureSessionId id;

  /// The current lifecycle state.
  final CaptureSessionLifecycle lifecycle;

  final List<CaptureItem> _items;

  /// An immutable snapshot of the items in this session.
  List<CaptureItem> get items => _items;

  /// The time at which the session was created.
  final DateTime createdAt;

  /// The time represented by this immutable session version.
  final DateTime updatedAt;

  /// Returns a replacement session with [lifecycle].
  ///
  /// The original instance and its items remain unchanged. Omit [updatedAt] to
  /// retain this session's timestamp.
  CaptureSession withLifecycle(
    CaptureSessionLifecycle lifecycle, {
    DateTime? updatedAt,
  }) {
    return CaptureSession(
      id: id,
      lifecycle: lifecycle,
      items: _items,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns a replacement session with a defensive, duplicate-free copy of
  /// [items].
  ///
  /// The original instance and its items remain unchanged. Omit [updatedAt] to
  /// retain this session's timestamp.
  CaptureSession withItems(Iterable<CaptureItem> items, {DateTime? updatedAt}) {
    return CaptureSession(
      id: id,
      lifecycle: lifecycle,
      items: items,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<CaptureItem> _copyValidatedItems(Iterable<CaptureItem> items) {
    final snapshot = List<CaptureItem>.of(items);
    final itemIds = <CaptureItemId>{};
    for (final item in snapshot) {
      if (!itemIds.add(item.id)) {
        throw ArgumentError.value(
          items,
          'items',
          'must not contain duplicate capture item identifiers',
        );
      }
    }
    return UnmodifiableListView(snapshot);
  }
}
