package org.textus.flutter.core.audio

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Canonical PCM16LE mono 16 kHz WAV; no extra chunks or transcoding. */
internal object PcmWaveAudio {
    const val MAXIMUM_PCM_BYTES = 3840000

    data class Parsed(val pcm: ByteArray, val durationMilliseconds: Long)

    fun encode(pcm: ByteArray): ByteArray {
        require(pcm.isNotEmpty() && pcm.size % 2 == 0 &&
            pcm.size <= MAXIMUM_PCM_BYTES && pcm.size / 2L * 1000 / 16000 > 0) {
            "PCM must contain 1..120000 milliseconds of samples"
        }
        val buffer = ByteBuffer.allocate(44 + pcm.size).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(36 + pcm.size)
        buffer.put("WAVEfmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)
        buffer.putShort(1.toShort())
        buffer.putShort(1.toShort())
        buffer.putInt(16000)
        buffer.putInt(32000)
        buffer.putShort(2.toShort())
        buffer.putShort(16.toShort())
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(pcm.size)
        buffer.put(pcm)
        return buffer.array()
    }

    fun parse(wave: ByteArray): Parsed {
        require(wave.size >= 44) { "Truncated WAV header" }
        val buffer = ByteBuffer.wrap(wave).order(ByteOrder.LITTLE_ENDIAN)
        fun tag(offset: Int, expected: String) =
            String(wave, offset, 4, Charsets.US_ASCII) == expected
        val size = buffer.getInt(40)
        require(tag(0, "RIFF") && tag(8, "WAVE") && tag(12, "fmt ") &&
            tag(36, "data") && buffer.getInt(4) == wave.size - 8 &&
            buffer.getInt(16) == 16 && buffer.getShort(20).toInt() == 1 &&
            buffer.getShort(22).toInt() == 1 && buffer.getInt(24) == 16000 &&
            buffer.getInt(28) == 32000 && buffer.getShort(32).toInt() == 2 &&
            buffer.getShort(34).toInt() == 16 && size == wave.size - 44 &&
            size > 0 && size % 2 == 0 && size <= MAXIMUM_PCM_BYTES &&
            size / 2L * 1000 / 16000 > 0) { "Unsupported or inconsistent canonical WAV" }
        return Parsed(wave.copyOfRange(44, wave.size), size / 2L * 1000 / 16000)
    }
}
