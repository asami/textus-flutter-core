import 'display_transport.dart';

/// One immutable raw response or an explicit delivery failure.
final class ScriptedTransportReply {
  ScriptedTransportReply.response(Map<String, Object?> wire)
    : wire = _freeze(wire) as Map<String, Object?>,
      exception = null;
  const ScriptedTransportReply.failure(DisplayTransportException failure)
    : exception = failure,
      wire = null;
  final Map<String, Object?>? wire;
  final DisplayTransportException? exception;
  Future<Map<String, Object?>> _consume() async {
    if (exception != null) {
      throw exception!;
    }
    return wire!;
  }
}

/// Expected FIFO method and its raw reply.
final class ScriptedDisplayExchange {
  const ScriptedDisplayExchange({required this.kind, required this.reply});
  final DisplayRequestKind kind;
  final ScriptedTransportReply reply;
}

/// Immutable observation of the exact typed request crossing the raw port.
final class DisplayTransportCall {
  const DisplayTransportCall({required this.kind, required this.request});
  final DisplayRequestKind kind;
  final DisplayRequest request;
}

/// Controllable FIFO playback; no admission, source mutation, reload or retry.
final class ScriptedDisplayTransport implements DisplayTransport {
  ScriptedDisplayTransport(List<ScriptedDisplayExchange> exchanges)
    : _exchanges = List.unmodifiable(exchanges);
  final List<ScriptedDisplayExchange> _exchanges;
  final List<DisplayTransportCall> _calls = [];
  int _cursor = 0;
  int get callCount => _calls.length;
  List<DisplayTransportCall> get calls => List.unmodifiable(_calls);
  Future<Map<String, Object?>> _call(DisplayRequest request) async {
    _calls.add(DisplayTransportCall(kind: request.kind, request: request));
    if (_cursor >= _exchanges.length) {
      throw StateError('Fixture mismatch: Display exchanges exhausted');
    }
    final exchange = _exchanges[_cursor++];
    if (exchange.kind != request.kind) {
      throw StateError(
        'Fixture mismatch: expected ${exchange.kind.name}, received ${request.kind.name}',
      );
    }
    return exchange.reply._consume();
  }

  @override
  Future<Map<String, Object?>> query(DisplayQueryRequest request) =>
      _call(request);
  @override
  Future<Map<String, Object?>> read(DisplayReadRequest request) =>
      _call(request);
  @override
  Future<Map<String, Object?>> update(DisplayUpdateRequest request) =>
      _call(request);
  @override
  Future<Map<String, Object?>> create(DisplayCreateRequest request) =>
      _call(request);
  @override
  Future<Map<String, Object?>> delete(DisplayDeleteRequest request) =>
      _call(request);
}

/// Independent ordinary Operation FIFO; execution never calls the Display port.
final class ScriptedOrdinaryOperationTransport
    implements OrdinaryOperationTransport {
  ScriptedOrdinaryOperationTransport(List<ScriptedTransportReply> replies)
    : _replies = List.unmodifiable(replies);
  final List<ScriptedTransportReply> _replies;
  final List<OrdinaryOperationRequest> _calls = [];
  int _cursor = 0;
  int get callCount => _calls.length;
  List<OrdinaryOperationRequest> get calls => List.unmodifiable(_calls);
  @override
  Future<Map<String, Object?>> execute(OrdinaryOperationRequest request) async {
    _calls.add(request);
    if (_cursor >= _replies.length) {
      throw StateError('Fixture mismatch: Operation replies exhausted');
    }
    return _replies[_cursor++]._consume();
  }
}

Object? _freeze(Object? value, [Set<Object>? ancestors]) {
  final path = ancestors ?? Set<Object>.identity();
  if (value is Map || value is List) {
    if (!path.add(value!)) {
      throw const FormatException('Reply cannot contain a JSON cycle');
    }
  }
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw const FormatException('Reply requires string JSON keys');
    }
    final result = Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key as String, _freeze(item, path))),
    );
    path.remove(value);
    return result;
  }
  if (value is List) {
    final result = List<Object?>.unmodifiable(
      value.map((item) => _freeze(item, path)),
    );
    path.remove(value);
    return result;
  }
  if (value == null ||
      value is String ||
      value is bool ||
      (value is num && value.isFinite)) {
    return value;
  }
  throw const FormatException('Reply must be finite JSON');
}
