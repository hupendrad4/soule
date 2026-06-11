package com.soulo.app.services

import com.soulo.app.models.VoiceBiomarkers
import com.soulo.app.utilities.AudioDSP
import java.io.File
import java.util.UUID

class BiomarkerService {

    suspend fun analyze(audioFile: File?, pcmData: ShortArray? = null): VoiceBiomarkers? {
        val pcm = pcmData ?: readPcmFromWav(audioFile) ?: return null
        if (pcm.size < 16000) return null // need at least 1 second

        val result = AudioDSP.compute(pcm)

        return VoiceBiomarkers(
            id = UUID.randomUUID().toString(),
            speechRate = result.speechRate,
            vocalEnergy = result.vocalEnergy,
            pitchInstability = result.pitchInstability,
            hesitationRate = result.hesitationRate,
            microBreathCount = result.microBreathCount,
            jitter = result.jitter,
            shimmer = result.shimmer,
            recordedAt = System.currentTimeMillis() / 1000
        )
    }

    private fun readPcmFromWav(file: File?): ShortArray? {
        if (file == null || !file.exists()) return null
        return try {
            java.io.RandomAccessFile(file, "r").use { raf ->
                val data = ByteArray(raf.length().toInt())
                raf.readFully(data)
                val buffer = java.nio.ByteBuffer.wrap(data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
                var offset = 12
                while (offset < data.size - 8) {
                    val chunkId = String(data, offset, 4)
                    val chunkSize = buffer.getInt(offset + 4)
                    if (chunkId == "data") {
                        val pcmCount = chunkSize / 2
                        val pcm = ShortArray(pcmCount)
                        for (i in 0 until pcmCount) {
                            pcm[i] = buffer.getShort(offset + 8 + i * 2)
                        }
                        return pcm
                    }
                    offset += 8 + chunkSize
                }
                null
            }
        } catch (_: Exception) { null }
    }
}
