package com.soulo.app.services

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import androidx.core.content.ContextCompat
import com.soulo.app.SouloApplication
import java.io.File

class RecordingService {
    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null
    var isRecording: Boolean = false
        private set

    fun hasPermission(): Boolean {
        val ctx = SouloApplication.instance
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
    }

    fun startRecording(): File? {
        if (isRecording || !hasPermission()) return null
        val dir = File(SouloApplication.instance.filesDir, "recordings")
        dir.mkdirs()
        val file = File(dir, "entry_${System.currentTimeMillis()}.wav")
        outputFile = file

        recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(SouloApplication.instance)
        } else {
            MediaRecorder()
        }.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(16000)
            setOutputFile(file.absolutePath)
            try {
                prepare()
                start()
                isRecording = true
            } catch (e: Exception) {
                release()
                return null
            }
        }
        return file
    }

    fun stopRecording(): File? {
        if (!isRecording) return null
        try {
            recorder?.apply { stop(); release() }
        } catch (_: Exception) {}
        recorder = null
        isRecording = false
        return outputFile
    }

    fun cancelRecording() {
        if (!isRecording) return
        try {
            recorder?.apply { stop(); release() }
        } catch (_: Exception) {}
        recorder = null
        isRecording = false
        outputFile?.delete()
        outputFile = null
    }
}
