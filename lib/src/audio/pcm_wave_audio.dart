import 'dart:typed_data';

/// Canonical PCM16 little-endian, mono, 16 kHz RIFF/WAVE audio.
///
/// Only the fixed 44-byte header and one positive data payload are accepted.
/// No transcoding, extra chunks, padding or trailing bytes are inferred.
final class PcmWaveAudio {
  PcmWaveAudio._(Uint8List bytes, Uint8List pcm) : _bytes = bytes, _pcm = pcm;

  /// Maximum PCM payload for 120 seconds at 16 kHz mono PCM16.
  static const int maximumPcmBytes = 3840000;

  final Uint8List _bytes;
  final Uint8List _pcm;

  /// A detached copy of the unchanged WAV, including its header.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// A detached copy of headerless PCM16 little-endian samples.
  Uint8List get pcmBytes => Uint8List.fromList(_pcm);

  /// Number of mono samples in the payload.
  int get sampleCount => _pcm.length ~/ 2;

  /// Duration floored to whole milliseconds from the actual sample count.
  int get durationMilliseconds => sampleCount * 1000 ~/ 16000;

  /// Validates and snapshots one exact canonical WAV.
  static PcmWaveAudio parse(Uint8List bytes) {
    if (bytes.length < 44) throw const FormatException('Truncated WAV header');
    final copy = Uint8List.fromList(bytes);
    final header = ByteData.sublistView(copy);
    bool tag(int offset, String value) =>
        List.generate(4, (index) => copy[offset + index]).join(',') ==
        value.codeUnits.join(',');
    final size = header.getUint32(40, Endian.little);
    if (!tag(0, 'RIFF') ||
        !tag(8, 'WAVE') ||
        !tag(12, 'fmt ') ||
        !tag(36, 'data') ||
        header.getUint32(4, Endian.little) != copy.length - 8 ||
        header.getUint32(16, Endian.little) != 16 ||
        header.getUint16(20, Endian.little) != 1 ||
        header.getUint16(22, Endian.little) != 1 ||
        header.getUint32(24, Endian.little) != 16000 ||
        header.getUint32(28, Endian.little) != 32000 ||
        header.getUint16(32, Endian.little) != 2 ||
        header.getUint16(34, Endian.little) != 16 ||
        size != copy.length - 44 ||
        size <= 0 ||
        size.isOdd ||
        size > maximumPcmBytes ||
        size ~/ 2 * 1000 ~/ 16000 == 0) {
      throw const FormatException('Unsupported or inconsistent canonical WAV');
    }
    return PcmWaveAudio._(copy, Uint8List.fromList(copy.sublist(44)));
  }

  /// Encodes exact headerless PCM in the same fixed canonical format.
  static Uint8List encode(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty ||
        pcmBytes.length.isOdd ||
        pcmBytes.length > maximumPcmBytes ||
        pcmBytes.length ~/ 2 * 1000 ~/ 16000 == 0) {
      throw ArgumentError('PCM must contain 1..120000 milliseconds of samples');
    }
    final bytes = Uint8List(44 + pcmBytes.length);
    final header = ByteData.sublistView(bytes);
    void tag(int offset, String value) =>
        bytes.setRange(offset, offset + 4, value.codeUnits);
    tag(0, 'RIFF');
    header.setUint32(4, bytes.length - 8, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    header.setUint32(40, pcmBytes.length, Endian.little);
    bytes.setRange(44, bytes.length, pcmBytes);
    return bytes;
  }
}
