import 'dart:math';

import '../repository/local_capture_store.dart';
import 'capture_material.dart';
import 'video_input.dart';

/// Opaque caller identities. Core assigns no Book/annotation meaning to them.
final class VideoRecoveryTarget {
  VideoRecoveryTarget({required this.ownerId, required this.elementId}) {
    _token(ownerId);
    _token(elementId);
  }
  final String ownerId;
  final String elementId;
  Map<String, Object?> toJson() => {'ownerId': ownerId, 'elementId': elementId};
  @override
  bool operator ==(Object other) =>
      other is VideoRecoveryTarget &&
      ownerId == other.ownerId &&
      elementId == other.elementId;
  @override
  int get hashCode => Object.hash(ownerId, elementId);
}

enum VideoRecoveryState { acquiring, ready, acknowledged, discarded }

/// One picker intent; a ready original awaits explicit caller adoption/save.
final class PendingVideoCapture {
  PendingVideoCapture._({
    required this.id,
    required this.target,
    required this.label,
    required this.requestedAt,
    required this.state,
    this.original,
  });
  final String id;
  final VideoRecoveryTarget target;
  final String label;
  final DateTime requestedAt;
  final VideoRecoveryState state;
  final CaptureMaterialReference? original;
  bool get active =>
      state == VideoRecoveryState.acquiring ||
      state == VideoRecoveryState.ready;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'target': target.toJson(),
    'label': label,
    'requestedAt': requestedAt.toIso8601String(),
    'state': state.name,
    'original': original?.toJson(),
  };
  PendingVideoCapture _with(
    VideoRecoveryState next, [
    CaptureMaterialReference? value,
  ]) => PendingVideoCapture._(
    id: id,
    target: target,
    label: label,
    requestedAt: requestedAt,
    state: next,
    original: value ?? original,
  );

  factory PendingVideoCapture.fromJson(Map<String, Object?> value) {
    const keys = {
      'schemaVersion',
      'id',
      'target',
      'label',
      'requestedAt',
      'state',
      'original',
    };
    if (value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['schemaVersion'] != 1 ||
        value['schemaVersion'] is! int ||
        value['id'] is! String ||
        value['label'] is! String ||
        value['requestedAt'] is! String ||
        value['target'] is! Map) {
      throw const FormatException('Invalid pending video document');
    }
    try {
      final target = Map<String, Object?>.from(value['target']! as Map);
      if (target.length != 2 ||
          target['ownerId'] is! String ||
          target['elementId'] is! String) {
        throw const FormatException('Invalid pending video target');
      }
      final id = value['id']! as String;
      _token(id);
      final label = value['label']! as String;
      if (label.isEmpty || label.length > 512) {
        throw const FormatException('Invalid video target label');
      }
      final time = DateTime.tryParse(value['requestedAt']! as String);
      if (time == null ||
          time.toUtc().toIso8601String() != value['requestedAt']) {
        throw const FormatException('Invalid pending video time');
      }
      final state = VideoRecoveryState.values.singleWhere(
        (s) => s.name == value['state'],
      );
      final raw = value['original'];
      final original = raw == null
          ? null
          : CaptureMaterialReference.fromJson(
              Map<String, Object?>.from(raw as Map),
            );
      if ((state == VideoRecoveryState.acquiring && original != null) ||
          ((state == VideoRecoveryState.ready ||
                  state == VideoRecoveryState.acknowledged) &&
              original == null) ||
          (original != null &&
              !const {
                'video/mp4',
                'video/quicktime',
              }.contains(original.mediaType))) {
        throw const FormatException('Inconsistent pending video state');
      }
      return PendingVideoCapture._(
        id: id,
        target: VideoRecoveryTarget(
          ownerId: target['ownerId']! as String,
          elementId: target['elementId']! as String,
        ),
        label: label,
        requestedAt: time.toUtc(),
        state: state,
        original: original,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid pending video value');
    }
  }
}

/// Borrows one local store/provider. Construction and metadata reads are inert.
/// The caller owns provider close and supplies the explicit recovery target.
/// One owner sequences this service; no cross-process transaction is promised.
final class VideoCaptureRecovery {
  VideoCaptureRecovery({
    required this._store,
    required this._provider,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  static const collection = 'video_capture_recovery_v1';
  static const documentId = 'pending';
  final LocalCaptureStore _store;
  final VideoInputProvider _provider;
  final DateTime Function() _now;
  bool _busy = false;
  bool _retired = false;
  (String, CapturedVideo)? _staged;
  (String, CaptureMaterialReference)? _retained;

  static Future<PendingVideoCapture?> pendingIn(LocalCaptureStore store) async {
    final raw = await store.readDocument(collection, documentId);
    if (raw == null) return null;
    final value = PendingVideoCapture.fromJson(raw);
    return value.active ? value : null;
  }

  Future<PendingVideoCapture?> pending() => pendingIn(_store);
  bool canRecover(PendingVideoCapture intent) =>
      !_retired &&
      (intent.original != null ||
          _staged?.$1 == intent.id ||
          _retained?.$1 == intent.id ||
          _provider.canRecoverLostVideo);

  /// The application supplies its successful save acknowledgement; Core checks
  /// only the exact pending intent and retained original, not domain persistence.
  static Future<void> acknowledgeStored(
    LocalCaptureStore store, {
    required String id,
    required VideoRecoveryTarget target,
    required CaptureMaterialReference original,
  }) async {
    final intent = await pendingIn(store);
    if (intent == null ||
        intent.id != id ||
        intent.target != target ||
        intent.state != VideoRecoveryState.ready ||
        intent.original != original) {
      throw StateError('Saved video does not match the pending intent');
    }
    final bytes = await store.readMaterial(original);
    if (inspectVideoContainer(bytes) != original.mediaType) {
      throw const FormatException(
        'Saved video container disagrees with reference',
      );
    }
    final latest = await pendingIn(store);
    if (latest == null ||
        latest.id != intent.id ||
        latest.target != target ||
        latest.state != VideoRecoveryState.ready ||
        latest.original != original) {
      throw StateError(
        'Video intent changed while validating the saved original',
      );
    }
    await store.saveDocument(
      collection,
      documentId,
      intent._with(VideoRecoveryState.acknowledged).toJson(),
    );
  }

  void retire() {
    _retired = true;
  }

  /// Shared image_picker lost data is consumed once. Other picker users must
  /// not consume/replace an unfinished video acquisition for a different caller.
  static Future<void> requireNoPending(LocalCaptureStore store) async {
    if (await pendingIn(store) != null) {
      throw StateError(
        'An unfinished video must be recovered or discarded first',
      );
    }
  }

  Future<CaptureMaterialReference?> acquire({
    required VideoRecoveryTarget target,
    required String label,
    bool fromGallery = false,
  }) => _operate(() async {
    if (fromGallery ? !_provider.canImport : !_provider.canCapture) {
      throw UnsupportedError('Video input unsupported');
    }
    if (label.isEmpty || label.length > 512) {
      throw ArgumentError('Invalid video target label');
    }
    await requireNoPending(_store);
    _alive();
    final random = Random.secure();
    final intent = PendingVideoCapture._(
      id: List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      target: target,
      label: label,
      requestedAt: _now().toUtc(),
      state: VideoRecoveryState.acquiring,
    );
    // Failure here prevents the OS picker from starting.
    await _write(intent);
    _alive();
    final captured = fromGallery
        ? await _provider.importVideo()
        : await _provider.capture();
    _alive();
    if (captured == null) {
      await _current(intent.id, target);
      await _write(intent._with(VideoRecoveryState.discarded));
      return null;
    }
    _staged = (intent.id, captured);
    return _retain(intent, captured);
  });

  Future<CaptureMaterialReference?> recover({
    required String id,
    required VideoRecoveryTarget target,
  }) => _operate(() async {
    final intent = await _current(id, target);
    if (intent.original case final original?) {
      await _validateOriginal(original);
      return original;
    }
    if (_retained case (final retainedId, final original)
        when retainedId == id) {
      await _validateOriginal(original);
      await _write(intent._with(VideoRecoveryState.ready, original));
      return original;
    }
    if (!canRecover(intent)) {
      throw UnsupportedError(
        'Unreturned picker video cannot be recovered on this platform',
      );
    }
    final captured = switch (_staged) {
      (final stagedId, final video) when stagedId == id => video,
      _ => await _provider.recoverLostVideo(),
    };
    // Absence is observable; it does not erase the target or authorize a new one.
    if (captured == null) return null;
    _alive();
    _staged = (id, captured);
    return _retain(intent, captured);
  });

  Future<void> acknowledge({
    required String id,
    required VideoRecoveryTarget target,
    required CaptureMaterialReference original,
  }) => _operate(() async {
    final intent = await _current(id, target);
    if (intent.state != VideoRecoveryState.ready ||
        intent.original != original) {
      throw StateError('Saved video does not match the pending original');
    }
    await _validateOriginal(original);
    await _write(intent._with(VideoRecoveryState.acknowledged));
    _staged = null;
    _retained = null;
  });

  /// Explicit discard retires the association intent, never original bytes.
  Future<void> discard({
    required String id,
    required VideoRecoveryTarget target,
  }) => _operate(() async {
    final intent = await _current(id, target);
    await _write(intent._with(VideoRecoveryState.discarded));
    _staged = null;
    _retained = null;
  });

  Future<CaptureMaterialReference> _retain(
    PendingVideoCapture intent,
    CapturedVideo video,
  ) async {
    await _current(intent.id, intent.target);
    _alive();
    final original = await _store.saveMaterial(
      bytes: video.bytes,
      mediaType: video.mediaType,
      capturedAt: video.capturedAt,
      originalName: video.originalName,
    );
    _retained = (intent.id, original);
    await _current(intent.id, intent.target);
    _alive();
    await _write(intent._with(VideoRecoveryState.ready, original));
    _staged = null;
    return original;
  }

  Future<void> _validateOriginal(CaptureMaterialReference original) async {
    final bytes = await _store.readMaterial(original);
    _alive();
    if (inspectVideoContainer(bytes) != original.mediaType) {
      throw const FormatException(
        'Recovered video container disagrees with reference',
      );
    }
  }

  Future<PendingVideoCapture> _current(
    String id,
    VideoRecoveryTarget target,
  ) async {
    final intent = await pending();
    _alive();
    if (intent == null || intent.id != id || intent.target != target) {
      throw StateError(
        'Video recovery target changed; no picker data was consumed',
      );
    }
    return intent;
  }

  Future<void> _write(PendingVideoCapture value) {
    _alive();
    return _store.saveDocument(collection, documentId, value.toJson());
  }

  void _alive() {
    if (_retired) throw StateError('Video recovery owner retired');
  }

  Future<T> _operate<T>(Future<T> Function() work) async {
    _alive();
    if (_busy) throw StateError('Video recovery is busy');
    _busy = true;
    try {
      final result = await work();
      _alive();
      return result;
    } finally {
      _busy = false;
    }
  }
}

void _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError('Invalid video recovery identity');
  }
}
