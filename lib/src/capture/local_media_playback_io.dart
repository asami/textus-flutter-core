import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

Future<({VideoPlayerController controller, Future<void> Function() release})>
createMediaPlayback(Uint8List bytes, String mediaType) async {
  final directory = await Directory.systemTemp.createTemp('textus-playback-');
  try {
    final suffix = switch (mediaType) {
      'video/quicktime' => 'mov',
      'audio/wav' => 'wav',
      'audio/aac' => 'aac',
      'audio/mpeg' => 'mp3',
      _ => 'mp4',
    };
    final file = File('${directory.path}/original.$suffix');
    await file.writeAsBytes(bytes, flush: true);
    return (
      controller: VideoPlayerController.file(file),
      release: () async {
        if (await directory.exists()) await directory.delete(recursive: true);
      },
    );
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}
