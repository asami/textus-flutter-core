import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

Future<({VideoPlayerController controller, Future<void> Function() release})>
createMediaPlayback(Uint8List bytes, String mediaType) =>
    throw UnsupportedError('Local media playback is unavailable');
