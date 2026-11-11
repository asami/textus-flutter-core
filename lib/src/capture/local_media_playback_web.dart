import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

Future<({VideoPlayerController controller, Future<void> Function() release})>
createMediaPlayback(Uint8List bytes, String mediaType) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mediaType),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    return (
      controller: VideoPlayerController.networkUrl(Uri.parse(url)),
      release: () async {
        web.URL.revokeObjectURL(url);
      },
    );
  } catch (_) {
    web.URL.revokeObjectURL(url);
    rethrow;
  }
}
