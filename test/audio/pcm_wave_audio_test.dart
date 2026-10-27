import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('canonical PCM WAV', () {
    test('preserves exact samples and floors duration with detached snapshots', () {
      // Given 16001 known PCM16 samples and mutable caller input.
      final pcm = Uint8List.fromList(
        List.generate(32002, (index) => index % 256),
      );
      final expected = Uint8List.fromList(pcm);
      // When encoding/parsing and mutating caller and returned byte snapshots.
      final wave = PcmWaveAudio.encode(pcm);
      final parsed = PcmWaveAudio.parse(wave);
      pcm[0] = 99;
      wave[44] = 88;
      parsed.bytes[44] = 77;
      parsed.pcmBytes[0] = 66;
      // Then exact PCM survives independently and sample-derived duration is floored.
      expect(parsed.sampleCount, 16001);
      expect(parsed.durationMilliseconds, 1000);
      expect(parsed.pcmBytes, orderedEquals(expected));
      expect(parsed.bytes, orderedEquals(PcmWaveAudio.encode(expected)));
      expect(parsed.bytes.length, 32046);
    });

    test('rejects invalid format fields and inconsistent RIFF/data sizes', () {
      // Given a valid waveform and each fixed header field that defines the format.
      final valid = PcmWaveAudio.encode(Uint8List(32000));
      final replacements = <int, int>{
        4: 0,
        16: 18,
        20: 3,
        22: 2,
        24: 44100,
        28: 64000,
        32: 4,
        34: 8,
        40: 31998,
      };
      // When every format/size field or required chunk tag is corrupted separately.
      for (final entry in replacements.entries) {
        final invalid = Uint8List.fromList(valid);
        final data = ByteData.sublistView(invalid);
        if ([20, 22, 32, 34].contains(entry.key)) {
          data.setUint16(entry.key, entry.value, Endian.little);
        } else {
          data.setUint32(entry.key, entry.value, Endian.little);
        }
        // Then no unsupported header is misread as canonical audio.
        expect(() => PcmWaveAudio.parse(invalid), throwsFormatException);
      }
      for (final offset in [0, 8, 12, 36]) {
        final invalid = Uint8List.fromList(valid)..[offset] = 0;
        expect(() => PcmWaveAudio.parse(invalid), throwsFormatException);
      }
    });

    test(
      'rejects empty submillisecond odd truncated extra and over-limit data',
      () {
        // Given a canonical original and PCM sizes outside the bounded format.
        final valid = PcmWaveAudio.encode(Uint8List(32));
        final badPcm = [
          Uint8List(0),
          Uint8List(2),
          Uint8List(33),
          Uint8List(3840002),
        ];
        // When encoding invalid PCM or parsing truncated/extra/empty payloads.
        for (final pcm in badPcm) {
          // Then invalid payloads cannot become successful originals.
          expect(() => PcmWaveAudio.encode(pcm), throwsArgumentError);
        }
        for (final invalid in [
          Uint8List(0),
          valid.sublist(0, 43),
          valid.sublist(0, valid.length - 1),
          Uint8List.fromList([...valid, 0, 0]),
          valid.sublist(0, 44),
        ]) {
          expect(() => PcmWaveAudio.parse(invalid), throwsFormatException);
        }
        for (final size in [0, 1, 2, 33, 3840002]) {
          final invalid = Uint8List(44 + size)..setRange(0, 44, valid);
          final header = ByteData.sublistView(invalid);
          header.setUint32(4, invalid.length - 8, Endian.little);
          header.setUint32(40, size, Endian.little);
          expect(() => PcmWaveAudio.parse(invalid), throwsFormatException);
        }
      },
    );

    test('accepts the exact 120 second cap', () {
      // Given the largest supported payload of 1920000 mono samples.
      final pcm = Uint8List(PcmWaveAudio.maximumPcmBytes);
      // When the exact cap is encoded and parsed.
      final parsed = PcmWaveAudio.parse(PcmWaveAudio.encode(pcm));
      // Then the whole payload and duration are retained without truncation.
      expect(parsed.durationMilliseconds, 120000);
      expect(parsed.pcmBytes.length, 3840000);
      expect(parsed.sampleCount, 1920000);
    });
  });
}
