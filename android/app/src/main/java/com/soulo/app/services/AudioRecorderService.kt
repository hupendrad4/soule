package com.soulo.app.services

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import androidx.core.content.ContextCompat
import com.soulo.app.SouloApplication
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.cos
import kotlin.math.PI
import kotlin.math.sqrt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

class AudioRecorderService {
    companion object {
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        const val BUFFER_SIZE_MULTIPLIER = 2
    }

    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var outputFile: File? = null
    private var pcmBuffer: ShortArray? = null
    val isRecording = AtomicBoolean(false)

    private val _amplitude = MutableStateFlow(0f)
    val amplitude: StateFlow<Float> = _amplitude

    private val _durationMs = MutableStateFlow(0L)
    val durationMs: StateFlow<Long> = _durationMs

    fun hasPermission(): Boolean {
        val ctx = SouloApplication.instance
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
    }

    fun startRecording(): File? {
        if (isRecording.get() || !hasPermission()) return null

        val bufferSize = maxOf(
            AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT) * BUFFER_SIZE_MULTIPLIER,
            SAMPLE_RATE * 2
        )
        if (bufferSize == AudioRecord.ERROR_BAD_VALUE) return null

        val dir = File(SouloApplication.instance.filesDir, "recordings")
        dir.mkdirs()
        val file = File(dir, "entry_${System.currentTimeMillis()}.wav")
        outputFile = file

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT, bufferSize
            )
        } catch (e: UnsupportedOperationException) {
            return null
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord?.release()
            audioRecord = null
            return null
        }

        audioRecord?.startRecording()
        isRecording.set(true)

        val buffer = ShortArray(bufferSize / 2)
        pcmBuffer = ShortArray(0)
        val pcmCollector = mutableListOf<ShortArray>()
        var totalSamples = 0L

        recordingThread = Thread {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
            val startTime = System.currentTimeMillis()

            while (isRecording.get()) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                if (read > 0) {
                    val copy = buffer.copyOf(read)
                    pcmCollector.add(copy)
                    totalSamples += read

                    val rms = sqrt(copy.map { it.toDouble() / Short.MAX_VALUE }
                        .sumOf { it * it } / read)
                    _amplitude.value = (rms * 10f).coerceAtMost(1f)
                    _durationMs.value = System.currentTimeMillis() - startTime
                }
            }

            // Write WAV
            val totalLen = pcmCollector.sumOf { it.size }
            val allPcm = ShortArray(totalLen)
            var offset = 0
            for (arr in pcmCollector) {
                System.arraycopy(arr, 0, allPcm, offset, arr.size)
                offset += arr.size
            }
            pcmBuffer = allPcm
            writeWavFile(file, allPcm, SAMPLE_RATE)
        }
        recordingThread?.start()
        return file
    }

    fun stopRecording(): File? {
        if (!isRecording.getAndSet(false)) return null
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
        recordingThread?.join(5000)
        recordingThread = null
        _amplitude.value = 0f
        _durationMs.value = 0L
        return outputFile
    }

    fun cancelRecording() {
        if (!isRecording.getAndSet(false)) return
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
        recordingThread?.join(2000)
        recordingThread = null
        outputFile?.delete()
        outputFile = null
        pcmBuffer = null
        _amplitude.value = 0f
        _durationMs.value = 0L
    }

    fun getPcmData(): ShortArray? = pcmBuffer

    private fun writeWavFile(file: File, samples: ShortArray, sampleRate: Int) {
        val byteRate = sampleRate * 2 // 16-bit = 2 bytes
        val dataSize = samples.size * 2
        val fileSize = 44 + dataSize

        file.outputStream().use { os ->
            // RIFF header
            os.write("RIFF".toByteArray())
            os.write(intToLittleEndian(fileSize - 8))
            os.write("WAVE".toByteArray())

            // fmt chunk
            os.write("fmt ".toByteArray())
            os.write(intToLittleEndian(16)) // chunk size
            os.write(shortToLittleEndian(1)) // PCM
            os.write(shortToLittleEndian(1)) // mono
            os.write(intToLittleEndian(sampleRate))
            os.write(intToLittleEndian(byteRate))
            os.write(shortToLittleEndian(2)) // block align
            os.write(shortToLittleEndian(16)) // bits per sample

            // data chunk
            os.write("data".toByteArray())
            os.write(intToLittleEndian(dataSize))
            val bytes = ByteArray(samples.size * 2)
            for (i in samples.indices) {
                val v = samples[i]
                bytes[i * 2] = (v.toInt() and 0xFF).toByte()
                bytes[i * 2 + 1] = ((v.toInt() shr 8) and 0xFF).toByte()
            }
            os.write(bytes)
        }
    }

    private fun intToLittleEndian(value: Int): ByteArray = byteArrayOf(
        (value and 0xFF).toByte(),
        ((value shr 8) and 0xFF).toByte(),
        ((value shr 16) and 0xFF).toByte(),
        ((value shr 24) and 0xFF).toByte()
    )

    private fun shortToLittleEndian(value: Int): ByteArray = byteArrayOf(
        (value and 0xFF).toByte(),
        ((value shr 8) and 0xFF).toByte()
    )
}
