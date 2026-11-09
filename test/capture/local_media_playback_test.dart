import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VideoPlayerPlatform previous;
  late _Player player;
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    player = _Player();
    VideoPlayerPlatform.instance = player;
  });
  tearDown(() async {
    VideoPlayerPlatform.instance = previous;
    await player.events.close();
  });

  test(
    'closing releases the decoder before deleting only its temporary copy',
    () async {
      // Given unchanged bytes and a controlled decoder, not a real playable fixture.
      final bytes = Uint8List.fromList([1, 2, 3]);
      final handle = await LocalMediaPlayback.open(bytes, 'video/mp4');
      final copy = File.fromUri(Uri.parse(player.source!.uri!));
      // When playback is explicitly closed twice.
      expect(await copy.readAsBytes(), bytes);
      await handle.close();
      await handle.close();
      // Then its one decoder and owned temporary directory are released exactly once.
      expect(player.disposals, 1);
      expect(await copy.parent.exists(), isFalse);
      expect(bytes, [1, 2, 3]);
    },
  );

  test(
    'decoder failure cleans its temporary source and remains observable',
    () async {
      // Given a decoder rejecting the selected original.
      player.fail = true;
      // When initialization fails.
      await expectLater(
        LocalMediaPlayback.open(Uint8List.fromList([1, 2, 3]), 'video/mp4'),
        throwsA(isA<PlatformException>()),
      );
      // Then no owned source survives and no fake playable handle is returned.
      expect(player.disposals, 1);
      expect(
        await File.fromUri(Uri.parse(player.source!.uri!)).parent.exists(),
        isFalse,
      );
    },
  );
}

class _Player extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  DataSource? source;
  bool fail = false;
  int disposals = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    if (fail) {
      events.addError(
        PlatformException(
          code: 'decoderRejected',
          message: 'Controlled decoder rejection',
        ),
      );
    } else {
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 2),
          size: const Size(20, 20),
        ),
      );
    }
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposals++;
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
}
