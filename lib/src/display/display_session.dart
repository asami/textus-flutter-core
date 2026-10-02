import 'package:flutter/foundation.dart';

import 'display_protocol.dart';
import 'display_transport.dart';
import 'presentation_context.dart';

/// Lifecycle of a safe projection request.
enum DisplaySessionReadPhase { idle, loading, ready, failed }

/// Lifecycle of one explicit command attempt, independently of its projection.
enum DisplaySessionCommandPhase { idle, running, settled, failed }

/// Separate candidate command capabilities.
enum DisplaySessionCommandKind { update, create, delete, operation }

/// Admission, decoding and delivery failures, distinct from decoded outcomes.
enum DisplaySessionFailureKind {
  context,
  codec,
  unavailable,
  ambiguous,
  unexpected,
}

/// Immutable visible failure; a delivery tag never asserts rollback.
final class DisplaySessionFailure {
  const DisplaySessionFailure._(this.kind, this.message, this.contextCode);

  /// Failure category.
  final DisplaySessionFailureKind kind;

  /// Original diagnostic message.
  final String message;

  /// Exact policy code for a context failure.
  final String? contextCode;
}

/// Immutable read state retaining the last admitted projection through failures.
final class DisplaySessionReadState<T> {
  const DisplaySessionReadState._(this.phase, this.data, this.failure);

  /// Read lifecycle.
  final DisplaySessionReadPhase phase;

  /// Last admitted projection, possibly stale.
  final T? data;

  /// Failure of this read, never a command receipt.
  final DisplaySessionFailure? failure;
}

/// Immutable history of the latest explicit command, preserved by safe reads.
final class DisplaySessionCommandState {
  const DisplaySessionCommandState._({
    required this.sequence,
    required this.kind,
    required this.phase,
    this.mutation,
    this.operation,
    this.failure,
  });

  /// Monotonic explicit attempt number, starting at zero.
  final int sequence;

  /// Capability attempted, absent before the first command.
  final DisplaySessionCommandKind? kind;

  /// Receipt or delivery lifecycle.
  final DisplaySessionCommandPhase phase;

  /// Admitted Display command receipt.
  final DisplayMutationResult? mutation;

  /// Admitted ordinary Operation receipt.
  final DisplayOperationResult? operation;

  /// Delivery, codec or admission failure without an accepted receipt.
  final DisplaySessionFailure? failure;
}

/// Immutable reactive session snapshot. Drafts and UI definitions belong to callers.
final class DisplaySessionState {
  DisplaySessionState._({
    required this.context,
    required List<PresentationContextDiagnostic> diagnostics,
    required this.list,
    required this.detail,
    required this.selectedResourceId,
    required this.command,
    required this.busy,
    required this.projectionPending,
    required this.commandUncertain,
    required this.contextFailure,
    required Map<String, int> minimumRevisions,
    required Map<String, int> committedRevisions,
  }) : diagnostics = List.unmodifiable(diagnostics),
       minimumRevisions = Map.unmodifiable(minimumRevisions),
       committedRevisions = Map.unmodifiable(committedRevisions);

  /// Last admitted producer-owned continuation.
  final PresentationContext context;

  /// Unique optional omission diagnostics retained for this fixed flow.
  final List<PresentationContextDiagnostic> diagnostics;

  /// Collection projection state.
  final DisplaySessionReadState<DisplayListData> list;

  /// Active Detail projection state.
  final DisplaySessionReadState<DisplayDetailData> detail;

  /// Last successfully admitted explicit resource selection.
  final String? selectedResourceId;

  /// Latest explicit command history.
  final DisplaySessionCommandState command;

  /// One activity reserved, including bounded update refresh.
  final bool busy;

  /// Safe projection evidence still required.
  final bool projectionPending;

  /// Dispatched command outcome lacks an accepted receipt and reconciliation.
  final bool commandUncertain;

  /// Context admission currently prevents editing.
  final DisplaySessionFailure? contextFailure;

  /// Maximum positive admitted per-resource revisions.
  final Map<String, int> minimumRevisions;

  /// Maximum accepted changed command commit revisions.
  final Map<String, int> committedRevisions;

  bool get _allFloorsRepresented {
    final rows = list.data?.model.items;
    return rows != null &&
        minimumRevisions.entries.every(
          (entry) => rows.any(
            (row) =>
                row.resourceId == entry.key &&
                row.sourceRevision >= entry.value,
          ),
        );
  }

  bool get _coherent {
    final active = detail.data;
    return selectedResourceId != null &&
        active != null &&
        active.resourceId == selectedResourceId &&
        _allFloorsRepresented &&
        active.sourceRevision >= (minimumRevisions[selectedResourceId] ?? 0) &&
        list.data!.model.items.any(
          (row) =>
              row.resourceId == selectedResourceId &&
              row.sourceRevision == active.sourceRevision,
        );
  }

  /// Local projection eligibility, never server authority or UI compatibility.
  bool get canMutate =>
      !busy &&
      contextFailure == null &&
      !projectionPending &&
      !commandUncertain &&
      list.phase == DisplaySessionReadPhase.ready &&
      detail.phase == DisplaySessionReadPhase.ready &&
      _coherent;

  /// Local collection eligibility for the bounded unsupported create capability.
  bool get canCreate =>
      !busy &&
      contextFailure == null &&
      !projectionPending &&
      !commandUncertain &&
      list.phase == DisplaySessionReadPhase.ready &&
      _allFloorsRepresented;
}

/// Common fixed-flow Display dispatcher with immutable observable snapshots.
///
/// Successful command receipts precede projection refresh. Disposal prevents
/// continuation/publication without cancelling or rolling back a started port.
final class DisplaySession extends ChangeNotifier {
  DisplaySession({
    required String resourceType,
    required String sourceId,
    required String componentId,
    required String listScreenId,
    required String detailScreenId,
    required PresentationContext initialContext,
    required PresentationContextPolicy contextPolicy,
    required DisplayTransport displayTransport,
    required OrdinaryOperationTransport operationTransport,
    required this._nowUtc,
  }) : resourceType = _identifier(resourceType),
       sourceId = _identifier(sourceId),
       componentId = _identifier(componentId),
       listScreenId = _identifier(listScreenId),
       detailScreenId = _identifier(detailScreenId),
       flowId = initialContext.flowId,
       _context = initialContext,
       _initialNamespaces = initialContext.families
           .map((family) => family.namespace)
           .toSet(),
       _policy = contextPolicy,
       _display = displayTransport,
       _operations = operationTransport {
    _state = _snapshot();
  }

  /// Fixed resource collection identity.
  final String resourceType;

  /// Fixed semantic source identity.
  final String sourceId;

  /// Fixed component identity.
  final String componentId;

  /// Configured List envelope screen identity.
  final String listScreenId;

  /// Configured Detail envelope screen identity.
  final String detailScreenId;

  /// Initial flow identity, never rebound or inherited from another instance.
  final String flowId;

  final PresentationContextPolicy _policy;
  final DisplayTransport _display;
  final OrdinaryOperationTransport _operations;
  final DateTime Function() _nowUtc;
  final Set<String> _initialNamespaces;
  PresentationContext _context;
  final List<PresentationContextDiagnostic> _diagnostics = [];
  final Map<String, int> _minimum = {};
  final Map<String, int> _committed = {};
  DisplaySessionReadState<DisplayListData> _list =
      const DisplaySessionReadState._(DisplaySessionReadPhase.idle, null, null);
  DisplaySessionReadState<DisplayDetailData> _detail =
      const DisplaySessionReadState._(DisplaySessionReadPhase.idle, null, null);
  DisplaySessionCommandState _command = const DisplaySessionCommandState._(
    sequence: 0,
    kind: null,
    phase: DisplaySessionCommandPhase.idle,
  );
  String? _selected;
  bool _busy = false;
  bool _pending = false;
  bool _uncertain = false;
  bool _obligation = false;
  bool _freshList = false;
  bool _freshDetail = false;
  bool _disposed = false;
  bool _notifying = false;
  bool _notifierDisposed = false;
  bool _contextLatched = false;
  DisplaySessionFailure? _contextFailure;
  late DisplaySessionState _state;

  /// Latest immutable snapshot; retained snapshots never change.
  DisplaySessionState get state => _state;

  /// Whether this instance has been discarded.
  bool get isDisposed => _disposed;

  DisplaySessionState _snapshot() => DisplaySessionState._(
    context: _context,
    diagnostics: _diagnostics,
    list: _list,
    detail: _detail,
    selectedResourceId: _selected,
    command: _command,
    busy: _busy,
    projectionPending: _pending,
    commandUncertain: _uncertain,
    contextFailure: _contextFailure,
    minimumRevisions: _minimum,
    committedRevisions: _committed,
  );

  void _publish() {
    if (_disposed) {
      return;
    }
    _state = _snapshot();
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
      if (_disposed && !_notifierDisposed) {
        _notifierDisposed = true;
        super.dispose();
      }
    }
  }

  void _available() {
    if (_disposed) {
      throw StateError('DisplaySession is disposed');
    }
    if (_busy) {
      throw StateError('DisplaySession is busy');
    }
  }

  void _start() {
    _busy = true;
    _publish();
  }

  void _finish() {
    if (_disposed) {
      return;
    }
    _busy = false;
    _publish();
  }

  void _retainDiagnostics(List<PresentationContextDiagnostic> diagnostics) {
    for (final diagnostic in diagnostics) {
      if (_initialNamespaces.contains(diagnostic.namespace) &&
          !_diagnostics.any(
            (old) =>
                old.namespace == diagnostic.namespace &&
                old.code == diagnostic.code,
          )) {
        _diagnostics.add(diagnostic);
      }
    }
  }

  PresentationContext _beforeCall() {
    if (_contextLatched) {
      throw PresentationContextException(
        _contextFailure!.contextCode!,
        _contextFailure!.message,
      );
    }
    try {
      final admission = _policy.admit(
        _context,
        sourceId: sourceId,
        componentId: componentId,
        flowId: flowId,
        nowUtc: _nowUtc(),
      );
      _context = admission.context;
      _retainDiagnostics(admission.diagnostics);
      _contextFailure = null;
      return admission.context;
    } catch (error) {
      _contextFailure = _failure(error);
      rethrow;
    }
  }

  void _admitReply(PresentationContext request, PresentationContext received) {
    try {
      final clock = _nowUtc();
      // Also retain omission evidence when an expired optional family is absent
      // from the response rather than echoed by its producer.
      final current = _policy.admit(
        request,
        sourceId: sourceId,
        componentId: componentId,
        flowId: flowId,
        nowUtc: clock,
      );
      final admission = _policy.admitResponse(request, received, nowUtc: clock);
      _context = admission.context;
      _retainDiagnostics(current.diagnostics);
      _retainDiagnostics(admission.diagnostics);
      _contextFailure = null;
    } catch (error) {
      _contextFailure = _failure(error);
      if (error is PresentationContextException) {
        _contextLatched = true;
      }
      rethrow;
    }
  }

  void _floor(String id, int? revision, {bool committed = false}) {
    if (revision == null) {
      return;
    }
    if (revision > (_minimum[id] ?? 0)) {
      _minimum[id] = revision;
    }
    if (committed && revision > (_committed[id] ?? 0)) {
      _committed[id] = revision;
    }
  }

  void _requireRefresh({bool uncertain = false}) {
    _obligation = true;
    _freshDetail = false;
    _freshList = false;
    _pending = true;
    _uncertain = uncertain;
  }

  void _freshness() {
    final snapshot = _snapshot();
    final coherent = _selected == null
        ? snapshot._allFloorsRepresented
        : snapshot._coherent;
    if (!coherent) {
      _pending = true;
      return;
    }
    if (!_obligation || (_freshList && _freshDetail)) {
      _pending = false;
      _uncertain = false;
      _obligation = false;
    }
  }

  DisplayRequestMetadata _metadata(
    PresentationContext context, [
    int? revision,
  ]) => DisplayRequestMetadata(context: context, observedRevision: revision);

  /// Query once; no eager Detail or selection change.
  Future<void> query() async {
    _available();
    _list = DisplaySessionReadState._(
      DisplaySessionReadPhase.loading,
      _list.data,
      null,
    );
    _start();
    try {
      if (!_disposed) {
        await _query();
      }
    } finally {
      _finish();
    }
  }

  Future<void> _query() async {
    if (_disposed) {
      return;
    }
    _list = DisplaySessionReadState._(
      DisplaySessionReadPhase.loading,
      _list.data,
      null,
    );
    _publish();
    if (_disposed) {
      return;
    }
    try {
      final context = _beforeCall();
      final wire = await _display.query(
        DisplayQueryRequest(
          resourceType: resourceType,
          metadata: _metadata(context),
        ),
      );
      if (_disposed) {
        return;
      }
      final response = DisplayListResponse.fromJson(wire);
      final data = response.data;
      if (data.resourceType != resourceType ||
          data.model.screenId != listScreenId ||
          data.model.detailScreenId != detailScreenId) {
        throw const FormatException(
          'List identity differs from configured session',
        );
      }
      _admitReply(context, response.context);
      _list = DisplaySessionReadState._(
        DisplaySessionReadPhase.ready,
        data,
        null,
      );
      for (final row in data.model.items) {
        _floor(row.resourceId, row.sourceRevision);
      }
      _freshList = _snapshot()._allFloorsRepresented;
      _freshness();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _list = DisplaySessionReadState._(
        DisplaySessionReadPhase.failed,
        _list.data,
        _failure(error),
      );
    }
    _publish();
  }

  /// Explicitly read an opaque resource ID, selecting it only after admission.
  Future<void> read(String resourceId) async {
    _available();
    _identifier(resourceId);
    if ((_pending || _uncertain) && resourceId != _selected) {
      throw StateError('Pending projection prevents resource switching');
    }
    _detail = DisplaySessionReadState._(
      DisplaySessionReadPhase.loading,
      _detail.data,
      null,
    );
    _start();
    try {
      if (!_disposed) {
        await _read(resourceId);
      }
    } finally {
      _finish();
    }
  }

  Future<void> _read(String resourceId) async {
    if (_disposed) {
      return;
    }
    _detail = DisplaySessionReadState._(
      DisplaySessionReadPhase.loading,
      _detail.data,
      null,
    );
    _publish();
    if (_disposed) {
      return;
    }
    try {
      final context = _beforeCall();
      final wire = await _display.read(
        DisplayReadRequest(
          resourceType: resourceType,
          metadata: _metadata(context),
          resourceId: resourceId,
        ),
      );
      if (_disposed) {
        return;
      }
      final response = DisplayDetailResponse.fromJson(wire);
      _detailIdentity(response.data, resourceId);
      _admitReply(context, response.context);
      _selected = resourceId;
      _detail = DisplaySessionReadState._(
        DisplaySessionReadPhase.ready,
        response.data,
        null,
      );
      _floor(resourceId, response.data.sourceRevision);
      _freshDetail =
          response.data.sourceRevision >= (_minimum[resourceId] ?? 0);
      _freshness();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _detail = DisplaySessionReadState._(
        DisplaySessionReadPhase.failed,
        _detail.data,
        _failure(error),
      );
    }
    _publish();
  }

  void _detailIdentity(DisplayDetailData data, String id) {
    if (data.resourceId != id || data.model.screenId != detailScreenId) {
      throw const FormatException(
        'Detail identity differs from requested resource/screen',
      );
    }
  }

  /// One explicit collection retry, preserving command history.
  Future<void> retryList() => query();

  /// One explicit retry of the last accepted focus.
  Future<void> retryDetail() async {
    _available();
    final id = _active();
    await read(id);
  }

  /// One active-resource read followed by one query, or only query without focus.
  Future<void> reload() async {
    _available();
    _start();
    try {
      await _refresh();
    } finally {
      _finish();
    }
  }

  Future<void> _refresh() async {
    if (_disposed) {
      return;
    }
    if (_selected != null) {
      await _read(_selected!);
    }
    if (_disposed || (_selected != null && _contextFailure != null)) {
      return;
    }
    await _query();
  }

  String _active() {
    if (_selected == null || _detail.data == null) {
      throw StateError('No active Detail');
    }
    return _selected!;
  }

  void _commandGuard({bool create = false}) {
    _available();
    if (!create) {
      _active();
    }
    if (!(create ? state.canCreate : state.canMutate)) {
      throw StateError('Projection/context is not eligible for a command');
    }
  }

  void _commandStart(DisplaySessionCommandKind kind) {
    _command = DisplaySessionCommandState._(
      sequence: _command.sequence + 1,
      kind: kind,
      phase: DisplaySessionCommandPhase.running,
    );
    _start();
  }

  /// Submit exact ordered inputs and caller revision; auto-refresh at most once.
  Future<void> update({
    required int observedRevision,
    required List<DisplayFieldInput> fields,
  }) async {
    _commandGuard();
    _revision(observedRevision);
    final inputs = List<DisplayFieldInput>.unmodifiable(fields);
    final id = _selected!;
    _commandStart(DisplaySessionCommandKind.update);
    await _mutation(
      DisplaySessionCommandKind.update,
      id,
      observedRevision,
      inputs,
    );
  }

  /// Dispatch the bounded typed create capability without inventing success.
  Future<void> create({required List<DisplayFieldInput> fields}) async {
    _commandGuard(create: true);
    final inputs = List<DisplayFieldInput>.unmodifiable(fields);
    _commandStart(DisplaySessionCommandKind.create);
    await _mutation(DisplaySessionCommandKind.create, null, null, inputs);
  }

  /// Dispatch the bounded typed delete capability for the active resource.
  Future<void> delete({required int observedRevision}) async {
    _commandGuard();
    _revision(observedRevision);
    final id = _selected!;
    _commandStart(DisplaySessionCommandKind.delete);
    await _mutation(
      DisplaySessionCommandKind.delete,
      id,
      observedRevision,
      const [],
    );
  }

  Future<void> _mutation(
    DisplaySessionCommandKind kind,
    String? id,
    int? revision,
    List<DisplayFieldInput> fields,
  ) async {
    var crossed = false;
    try {
      if (_disposed) {
        return;
      }
      final context = _beforeCall();
      final metadata = _metadata(context, revision);
      crossed = true;
      final wire = await switch (kind) {
        DisplaySessionCommandKind.update => _display.update(
          DisplayUpdateRequest(
            resourceType: resourceType,
            metadata: metadata,
            resourceId: id!,
            fields: fields,
          ),
        ),
        DisplaySessionCommandKind.create => _display.create(
          DisplayCreateRequest(
            resourceType: resourceType,
            metadata: metadata,
            fields: fields,
          ),
        ),
        DisplaySessionCommandKind.delete => _display.delete(
          DisplayDeleteRequest(
            resourceType: resourceType,
            metadata: metadata,
            resourceId: id!,
          ),
        ),
        DisplaySessionCommandKind.operation => throw StateError(
          'Separate Operation port required',
        ),
      };
      if (_disposed) {
        return;
      }
      final response = DisplayMutationResponse.fromJson(wire);
      final result = response.result;
      if (id != null && result.resourceId != id) {
        throw const FormatException('Mutation resource differs');
      }
      if (result.display != null) {
        _detailIdentity(result.display!, id ?? result.resourceId);
      }
      final success =
          result.outcome == DisplayCommandOutcome.changed ||
          result.outcome == DisplayCommandOutcome.noOp;
      if (kind != DisplaySessionCommandKind.update &&
          result.outcome != DisplayCommandOutcome.rejected &&
          result.outcome != DisplayCommandOutcome.unsupported) {
        throw const FormatException(
          'Prototype create/delete accepts rejected or unsupported only',
        );
      }
      _admitReply(context, response.context);
      _command = DisplaySessionCommandState._(
        sequence: _command.sequence,
        kind: kind,
        phase: DisplaySessionCommandPhase.settled,
        mutation: result,
      );
      _floor(result.resourceId, result.currentRevision);
      _floor(result.resourceId, result.committedRevision, committed: true);
      if (success) {
        _requireRefresh();
        if (result.display != null) {
          _detail = DisplaySessionReadState._(
            DisplaySessionReadPhase.ready,
            result.display,
            null,
          );
          _floor(result.resourceId, result.display!.sourceRevision);
        }
      }
      _freshness();
      _publish();
      if (!_disposed && success) {
        await _refresh();
      }
    } catch (error) {
      if (_disposed) {
        return;
      }
      _commandFailed(kind, error, crossed);
    } finally {
      _finish();
    }
  }

  /// Execute a separate ordinary Operation with zero implicit Display requests.
  Future<void> executeOperation({
    required String operationId,
    required int observedRevision,
  }) async {
    _commandGuard();
    _identifier(operationId);
    _revision(observedRevision);
    final id = _selected!;
    _commandStart(DisplaySessionCommandKind.operation);
    var crossed = false;
    try {
      if (_disposed) {
        return;
      }
      final context = _beforeCall();
      final request = OrdinaryOperationRequest(
        operationId: operationId,
        resourceId: id,
        metadata: _metadata(context, observedRevision),
      );
      crossed = true;
      final wire = await _operations.execute(request);
      if (_disposed) {
        return;
      }
      final response = OrdinaryOperationResponse.fromJson(wire);
      final result = response.result;
      if (result.resourceId != id) {
        throw const FormatException('Operation resource differs');
      }
      _admitReply(context, response.context);
      _command = DisplaySessionCommandState._(
        sequence: _command.sequence,
        kind: DisplaySessionCommandKind.operation,
        phase: DisplaySessionCommandPhase.settled,
        operation: result,
      );
      _floor(id, result.currentRevision);
      _floor(id, result.committedRevision, committed: true);
      if (result.outcome == DisplayCommandOutcome.changed) {
        _requireRefresh();
      }
      _freshness();
      _publish();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _commandFailed(DisplaySessionCommandKind.operation, error, crossed);
    } finally {
      _finish();
    }
  }

  void _commandFailed(
    DisplaySessionCommandKind kind,
    Object error,
    bool crossed,
  ) {
    _command = DisplaySessionCommandState._(
      sequence: _command.sequence,
      kind: kind,
      phase: DisplaySessionCommandPhase.failed,
      failure: _failure(error),
    );
    if (crossed) {
      _requireRefresh(uncertain: true);
    }
    _publish();
  }

  /// Discard this flow; already-started source effects are neither cancelled nor rolled back.
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (!_notifying) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}

String _identifier(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, 'identity', 'Must be nonblank');
  }
  return value;
}

void _revision(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'observedRevision', 'Must be positive');
  }
}

DisplaySessionFailure _failure(Object error) => switch (error) {
  PresentationContextException() => DisplaySessionFailure._(
    DisplaySessionFailureKind.context,
    error.message,
    error.code,
  ),
  FormatException() => DisplaySessionFailure._(
    DisplaySessionFailureKind.codec,
    error.message,
    null,
  ),
  DisplayTransportException() => DisplaySessionFailure._(
    error.failure == DisplayTransportFailure.unavailable
        ? DisplaySessionFailureKind.unavailable
        : DisplaySessionFailureKind.ambiguous,
    error.message,
    null,
  ),
  _ => DisplaySessionFailure._(
    DisplaySessionFailureKind.unexpected,
    error.toString(),
    null,
  ),
};
