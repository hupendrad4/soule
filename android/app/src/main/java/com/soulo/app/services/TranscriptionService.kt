package com.soulo.app.services

import android.os.Build
import com.soulo.app.SouloApplication
import com.soulo.app.utilities.WhisperWrapper
import java.io.File
import java.io.RandomAccessFile
import java.nio.ShortBuffer
import java.nio.ByteOrder
import java.nio.ByteBuffer

class TranscriptionService {
    private var whisper: WhisperWrapper? = null
    private var initialized = false
    private val modelDir: File
        get() = File(SouloApplication.instance.filesDir, "models")

    val isModelDownloaded: Boolean
        get() = File(modelDir, "ggml-tiny.en.bin").exists()

    suspend fun initialize(): Boolean {
        if (initialized) return true
        val modelFile = File(modelDir, "ggml-tiny.en.bin")
        if (!modelFile.exists()) return false

        return try {
            whisper = WhisperWrapper()
            initialized = whisper!!.init(modelFile.absolutePath)
            initialized
        } catch (e: Exception) {
            false
        }
    }

    suspend fun transcribe(audioFile: File?, pcmData: ShortArray? = null): String {
        if (!initialized && !initialize()) return ""

        val pcm = pcmData ?: readWavPcm(audioFile) ?: return ""
        if (pcm.isEmpty()) return ""

        return try {
            whisper?.transcribe(pcm, 16000, (Build.VERSION.SDK_INT / 2).coerceIn(2, 8)) ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    fun release() {
        whisper?.release()
        whisper = null
        initialized = false
    }

    private fun readWavPcm(file: File?): ShortArray? {
        if (file == null || !file.exists()) return null
        return try {
            RandomAccessFile(file, "r").use { raf ->
                val data = ByteArray(raf.length().toInt())
                raf.readFully(data)
                val buffer = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
                buffer.getInt(4) // skip RIFF header, but verify
                if (data[8] != 'W'.code.toByte() || data[9] != 'A'.code.toByte() ||
                    data[10] != 'V'.code.toByte() || data[11] != 'E'.code.toByte()) {
                    return null
                }
                // Find "data" chunk
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
        } catch (e: Exception) {
            null
        }
    }
}
