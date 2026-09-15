import 'dart:collection';

import 'capture_identifiers.dart';
import 'capture_session.dart';

/// Immutable workflow guidance supplied by an external capture profile.
final class CaptureWorkflowHints {
  /// Creates workflow hints from a defensive copy of [values].
  CaptureWorkflowHints(Map<String, String> values)
    : _values = UnmodifiableMapView(Map<String, String>.of(values));

  final Map<String, String> _values;

  /// An immutable snapshot of the workflow hint values.
  Map<String, String> get values => _values;
}

/// Immutable presentation guidance supplied by an external capture profile.
final class CapturePresentationHints {
  /// Creates presentation hints from a defensive copy of [values].
  CapturePresentationHints(Map<String, String> values)
    : _values = UnmodifiableMapView(Map<String, String>.of(values));

  final Map<String, String> _values;

  /// An immutable snapshot of the presentation hint values.
  Map<String, String> get values => _values;
}

/// A validation issue reported by a [CaptureProfileValidator].
final class CaptureProfileValidationIssue {
  /// Creates an issue with a non-blank [code] and [message].
  CaptureProfileValidationIssue({
    required String code,
    required String message,
    this.itemId,
  }) : code = _requireNonBlank(code, 'code'),
       message = _requireNonBlank(message, 'message');

  /// A stable, consumer-defined issue classification.
  final String code;

  /// A human-readable description of the validation issue.
  final String message;

  /// The affected item when this issue is item-specific.
  final CaptureItemId? itemId;
}

/// Validates a [CaptureSession] according to an external capture profile.
typedef CaptureProfileValidator =
    Iterable<CaptureProfileValidationIssue> Function(CaptureSession session);

/// Immutable external contract for capture item types and validation behavior.
final class CaptureProfile {
  /// Creates a profile with item types, optional validators, and optional hints.
  CaptureProfile({
    required this.id,
    required Iterable<CaptureItemType> itemTypes,
    Iterable<CaptureProfileValidator> validators =
        const <CaptureProfileValidator>[],
    this.workflowHints,
    this.presentationHints,
  }) : _itemTypes = _copyValidatedItemTypes(itemTypes),
       _validators = UnmodifiableListView(
         List<CaptureProfileValidator>.of(validators),
       );

  /// The externally defined profile identifier.
  final CaptureProfileId id;

  final List<CaptureItemType> _itemTypes;

  /// An immutable snapshot of the item types accepted by this profile.
  List<CaptureItemType> get itemTypes => _itemTypes;

  final List<CaptureProfileValidator> _validators;

  /// An immutable snapshot of validators evaluated in their declared order.
  List<CaptureProfileValidator> get validators => _validators;

  /// Optional workflow guidance for the profile's consumer.
  final CaptureWorkflowHints? workflowHints;

  /// Optional presentation guidance for the profile's consumer.
  final CapturePresentationHints? presentationHints;

  /// Aggregates validation issues in declared validator order.
  List<CaptureProfileValidationIssue> validate(CaptureSession session) {
    final issues = <CaptureProfileValidationIssue>[];
    for (final validator in _validators) {
      issues.addAll(validator(session));
    }
    return UnmodifiableListView(issues);
  }

  static List<CaptureItemType> _copyValidatedItemTypes(
    Iterable<CaptureItemType> itemTypes,
  ) {
    final snapshot = List<CaptureItemType>.of(itemTypes);
    if (snapshot.isEmpty) {
      throw ArgumentError.value(itemTypes, 'itemTypes', 'must not be empty');
    }
    final uniqueItemTypes = <CaptureItemType>{};
    for (final itemType in snapshot) {
      if (!uniqueItemTypes.add(itemType)) {
        throw ArgumentError.value(
          itemTypes,
          'itemTypes',
          'must not contain duplicate capture item types',
        );
      }
    }
    return UnmodifiableListView(snapshot);
  }
}

String _requireNonBlank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return value;
}
