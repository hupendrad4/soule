package com.soulo.app.utilities

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.soulo.app.SouloApplication

object HapticManager {
    private val context = SouloApplication.instance
    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun vibrate(effect: VibrationEffect) {
        try {
            vibrator?.vibrate(effect)
        } catch (_: Exception) {}
    }

    fun recordStart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrate(VibrationEffect.createOneShot(30, 128))
        }
    }

    fun recordStop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrate(VibrationEffect.createOneShot(50, 200))
        }
    }

    fun success() {
        val pattern = longArrayOf(0, 30, 50, 30)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrate(VibrationEffect.createWaveform(pattern, -1))
        }
    }

    fun error() {
        val pattern = longArrayOf(0, 100, 50, 100)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrate(VibrationEffect.createWaveform(pattern, -1))
        }
    }

    fun warning() {
        val pattern = longArrayOf(0, 50, 30, 50)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrate(VibrationEffect.createWaveform(pattern, -1))
        }
    }

    fun processingComplete() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrate(VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE))
        }
    }
}
