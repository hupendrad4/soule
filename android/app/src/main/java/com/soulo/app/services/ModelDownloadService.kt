package com.soulo.app.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import androidx.core.app.NotificationCompat
import com.soulo.app.MainActivity
import com.soulo.app.SouloApplication
import com.soulo.app.models.ProcessingStatus
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.math.min

data class ModelDownload(
    val name: String,
    val url: String,
    val fileName: String,
    val expectedSize: Long,
    val sha256: String,
    val isRequired: Boolean = false
)

data class DownloadProgress(
    val modelName: String,
    val bytesDownloaded: Long,
    val totalBytes: Long,
    val speedBytesPerSec: Long = 0,
    val status: DownloadStatus = DownloadStatus.downloading
)

enum class DownloadStatus { pending, downloading, completed, failed, verifying }

object ModelDownloadService {
    private val ctx = SouloApplication.instance
    private val notificationManager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val NOTIFICATION_ID = 1002
    private val CHANNEL_ID = "model_download"

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val _progress = MutableStateFlow<List<DownloadProgress>>(emptyList())
    val progress: StateFlow<List<DownloadProgress>> = _progress

    // Model registry — update URLs to actual hosted model locations
    val models = listOf(
        ModelDownload(
            name = "Whisper Tiny EN",
            url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin",
            fileName = "ggml-tiny.en.bin",
            expectedSize = 77_100_000,
            sha256 = "0f3e4f5a6b7c8d9e0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f",
            isRequired = false
        ),
        ModelDownload(
            name = "emotion2vec ONNX",
            url = "https://huggingface.co/emotion2vec/emotion2vec_plus_large/resolve/main/emotion2vec.onnx",
            fileName = "emotion2vec.onnx",
            expectedSize = 125_000_000,
            sha256 = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
            isRequired = false
        ),
        ModelDownload(
            name = "Phi-3-mini Q4 ONNX",
            url = "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/phi3_mini_q4.onnx",
            fileName = "phi3_mini_q4.onnx",
            expectedSize = 2_200_000_000,
            sha256 = "b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3",
            isRequired = false
        ),
        ModelDownload(
            name = "Phi-3 Tokenizer",
            url = "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/tokenizer.json",
            fileName = "tokenizer.json",
            expectedSize = 2_400_000,
            sha256 = "c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4",
            isRequired = false
        )
    )

    private val modelDir: File
        get() = File(ctx.filesDir, "models").also { it.mkdirs() }

    fun isDownloaded(model: ModelDownload): Boolean {
        val file = File(modelDir, model.fileName)
        return file.exists() && file.length() == model.expectedSize
    }

    fun allRequiredDownloaded(): Boolean {
        return models.filter { it.isRequired }.all { isDownloaded(it) }
    }

    fun downloadModel(model: ModelDownload, onProgress: ((Float) -> Unit)? = null) {
        if (isDownloaded(model)) return
        createNotificationChannel()

        scope.launch {
            val file = File(modelDir, model.fileName)
            file.parentFile?.mkdirs()

            try {
                val url = URL(model.url)
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 15000
                conn.readTimeout = 30000
                conn.setRequestProperty("User-Agent", "Soulo-Android/1.0")

                // Resume support
                var downloadedBytes = 0L
                if (file.exists()) {
                    downloadedBytes = file.length()
                    conn.setRequestProperty("Range", "bytes=$downloadedBytes-")
                }

                conn.connect()
                val totalBytes = if (downloadedBytes > 0) model.expectedSize
                else conn.contentLength.toLong().coerceAtLeast(model.expectedSize)

                val inputStream: InputStream = if (downloadedBytes > 0 && conn.responseCode == 206) {
                    file.appendBytes(ByteArray(0))
                    conn.inputStream
                } else {
                    file.outputStream().use { it.close() }
                    val fresh = URL(model.url).openConnection()
                    fresh.connectTimeout = 15000
                    fresh.readTimeout = 30000
                    fresh.setRequestProperty("User-Agent", "Soulo-Android/1.0")
                    fresh.connect()
                    fresh.inputStream
                }

                val outputStream = FileOutputStream(file, true)
                val buffer = ByteArray(8192)
                var bytesRead: Int
                var lastNotify = 0L

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    downloadedBytes += bytesRead

                    val pct = if (totalBytes > 0) downloadedBytes.toFloat() / totalBytes else 0f
                    onProgress?.invoke(pct)
                    updateNotification(model.name, pct)

                    // Throttle StateFlow updates
                    val now = System.currentTimeMillis()
                    if (now - lastNotify > 250) {
                        _progress.value = _progress.value.filter { it.modelName != model.name } + DownloadProgress(
                            modelName = model.name,
                            bytesDownloaded = downloadedBytes,
                            totalBytes = totalBytes
                        )
                        lastNotify = now
                    }
                }

                inputStream.close()
                outputStream.close()

                // Verify
                _progress.value = _progress.value.filter { it.modelName != model.name } + DownloadProgress(
                    modelName = model.name,
                    bytesDownloaded = downloadedBytes,
                    totalBytes = totalBytes,
                    status = DownloadStatus.verifying
                )

                val hash = sha256(file)
                val verified = hash == model.sha256 || model.sha256 == "skip"

                if (verified) {
                    _progress.value = _progress.value.filter { it.modelName != model.name } + DownloadProgress(
                        modelName = model.name,
                        bytesDownloaded = downloadedBytes,
                        totalBytes = totalBytes,
                        status = DownloadStatus.completed
                    )
                    showCompletionNotification(model.name)
                } else {
                    file.delete()
                    _progress.value = _progress.value.filter { it.modelName != model.name } + DownloadProgress(
                        modelName = model.name,
                        bytesDownloaded = 0,
                        totalBytes = totalBytes,
                        status = DownloadStatus.failed
                    )
                }
            } catch (e: Exception) {
                _progress.value = _progress.value.filter { it.modelName != model.name } + DownloadProgress(
                    modelName = model.name,
                    bytesDownloaded = 0,
                    totalBytes = model.expectedSize,
                    status = DownloadStatus.failed
                )
            }
        }
    }

    fun downloadAll() {
        for (model in models) {
            if (!isDownloaded(model)) {
                downloadModel(model)
            }
        }
    }

    fun isWifiConnected(): Boolean {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    fun totalDownloadSize(): Long = models.filter { !isDownloaded(it) }.sumOf { it.expectedSize }

    fun getFile(name: String): File? {
        val file = File(modelDir, name)
        return if (file.exists()) file else null
    }

    fun getModelDir(): File = modelDir

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(8192)
            var read: Int
            while (stream.read(buffer).also { read = it } != -1) {
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Model Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "AI model download progress" }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun updateNotification(modelName: String, progress: Float) {
        val pct = (progress * 100).toInt()
        val intent = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading $modelName")
            .setContentText("$pct%")
            .setProgress(100, pct, false)
            .setContentIntent(intent)
            .setOngoing(true)
            .build()
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun showCompletionNotification(modelName: String) {
        val intent = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("$modelName Ready")
            .setContentText("Model downloaded and verified")
            .setContentIntent(intent)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(NOTIFICATION_ID, notification)
    }
}
