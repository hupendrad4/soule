package com.soulo.app.utilities

import android.os.Build
import java.io.File

class WhisperWrapper {
    companion object {
        private var loaded = false
        private var nativePtr: Long = 0

        fun loadLibrary() {
            if (!loaded) {
                System.loadLibrary("soulo_whisper")
                loaded = true
            }
        }

        fun isLoaded(): Boolean = loaded
    }

    private var initialized = false

    fun init(modelPath: String): Boolean {
        if (!loaded) loadLibrary()
        if (initialized) return true

        val modelFile = File(modelPath)
        if (!modelFile.exists()) return false

        nativePtr = nativeInit(modelPath)
        initialized = nativePtr != 0L
        return initialized
    }

    fun transcribe(pcmData: ShortArray, sampleRate: Int = 16000, nThreads: Int = 4): String {
        if (!initialized || nativePtr == 0L) return ""
        return nativeTranscribe(nativePtr, pcmData, sampleRate, nThreads) ?: ""
    }

    fun release() {
        if (initialized && nativePtr != 0L) {
            nativeRelease(nativePtr)
            nativePtr = 0
            initialized = false
        }
    }

    private external fun nativeInit(modelPath: String): Long
    private external fun nativeTranscribe(ctxPtr: Long, pcmData: ShortArray, sampleRate: Int, nThreads: Int): String?
    private external fun nativeRelease(ctxPtr: Long)
}
