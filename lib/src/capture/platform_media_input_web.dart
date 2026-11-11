import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'media_input.dart';
import 'photo_capture.dart';

MediaInputProvider createPlatformMediaInputProvider() =>
    BrowserFileMediaInputProvider();

/// File import only. Missing capture adapters do not assert absent hardware.
/// A supported capture adapter can be injected through the common provider port.
final class BrowserFileMediaInputProvider implements MediaInputProvider {
  BrowserFileMediaInputProvider({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  web.HTMLInputElement? _input;
  Completer<CapturedPhoto?>? _pending;
  bool _closed = false;
  @override
  Map<MediaInputAction, MediaInputCapability> get capabilities => {
    for (final action in MediaInputAction.values)
      action: MediaInputCapability.unsupported,
    MediaInputAction.imageImport: const MediaInputCapability(
      support: MediaAdapterSupport.supported,
      device: MediaDeviceAvailability.available,
      permission: MediaPermissionState.allowed,
    ),
  };
  @override
  Future<Map<MediaInputAction, MediaInputCapability>> inspect() async =>
      capabilities;
  @override
  Future<CapturedPhoto?> importImage() {
    if (_closed) {
      return Future.error(const MediaInputException(MediaInputFailure.retired));
    }
    if (_pending != null) {
      return Future.error(const MediaInputException(MediaInputFailure.busy));
    }
    final done = Completer<CapturedPhoto?>();
    _pending = done;
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/png,image/jpeg,image/webp';
    _input = input;
    input.style.display = 'none';
    web.document.body!.appendChild(input);
    void finish(CapturedPhoto? value, [Object? error]) {
      if (done.isCompleted) return;
      _pending = null;
      _input = null;
      input.remove();
      if (error == null) {
        done.complete(value);
      } else {
        done.completeError(error);
      }
    }

    input.oncancel = ((web.Event _) => finish(null)).toJS;
    input.onchange = ((web.Event _) {
      unawaited(() async {
        try {
          final files = input.files;
          if (files == null || files.length == 0) {
            finish(null);
            return;
          }
          if (files.length != 1) {
            throw const MediaInputException(MediaInputFailure.invalidImage);
          }
          final file = files.item(0)!;
          if (file.size > 16777216) {
            throw const MediaInputException(MediaInputFailure.tooLarge);
          }
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          if (_closed || !identical(_pending, done)) return;
          finish(
            validateImportedImage(
              bytes: bytes,
              acquiredAt: _clock(),
              originalName: file.name,
            ),
          );
        } catch (error) {
          finish(
            null,
            error is MediaInputException
                ? error
                : const MediaInputException(MediaInputFailure.unavailable),
          );
        }
      }());
    }).toJS;
    // Keep native user activation: no async observation precedes this click.
    try {
      input.click();
    } catch (_) {
      finish(null, const MediaInputException(MediaInputFailure.unavailable));
    }
    return done.future;
  }

  @override
  Future<CapturedPhoto?> captureImage() async =>
      throw const MediaInputException(MediaInputFailure.unsupported);
  @override
  Future<void> close() async {
    _closed = true;
    _input?.remove();
    _input = null;
    final done = _pending;
    _pending = null;
    if (done != null && !done.isCompleted) {
      done.completeError(const MediaInputException(MediaInputFailure.retired));
    }
  }
}
