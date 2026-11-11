import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'local_media_playback_stub.dart'
    if (dart.library.io) 'local_media_playback_io.dart'
    if (dart.library.js_interop) 'local_media_playback_web.dart'
    as platform;

/// Owns decoder and a temporary playback source, never the durable original.
final class LocalMediaPlayback {
  LocalMediaPlayback._(this.controller, this._release);
  final VideoPlayerController controller;
  final Future<void> Function() _release;
  Future<void>? _closing;
  static Future<LocalMediaPlayback> open(
    Uint8List bytes,
    String mediaType,
  ) async {
    if (bytes.isEmpty ||
        bytes.length > 67108864 ||
        !const {
          'video/mp4',
          'video/quicktime',
          'audio/wav',
          'audio/mp4',
          'audio/aac',
          'audio/mpeg',
        }.contains(mediaType)) {
      throw ArgumentError('Unsupported or oversized playback source');
    }
    final source = await platform.createMediaPlayback(
      Uint8List.fromList(bytes),
      mediaType,
    );
    final handle = LocalMediaPlayback._(source.controller, source.release);
    try {
      await handle.controller.initialize().timeout(const Duration(seconds: 30));
      if (handle.controller.value.hasError) {
        throw StateError(handle.controller.value.errorDescription!);
      }
      return handle;
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  Future<void> close() => _closing ??= () async {
    try {
      await controller.dispose();
    } finally {
      await _release();
    }
  }();
}
