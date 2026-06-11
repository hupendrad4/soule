package com.soulo.app.services

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.soulo.app.SouloApplication
import com.soulo.app.models.*
import com.soulo.app.services.StorageService
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

enum class ExportFormat { json, csv, txt }

object ExportService {
    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }
    private val ctx = SouloApplication.instance
    private val dateFmt = SimpleDateFormat("yyyy-MM-dd_HHmmss", Locale.US)

    private fun getExportDir(): File {
        val dir = File(ctx.cacheDir, "exports")
        dir.mkdirs()
        return dir
    }

    fun exportEntries(
        entries: List<JournalEntry>,
        format: ExportFormat = ExportFormat.json
    ): File {
        val timestamp = dateFmt.format(Date())
        val fileName = "soulo_export_$timestamp"
        val file = when (format) {
            ExportFormat.json -> File(getExportDir(), "$fileName.json").also {
                it.writeText(json.encodeToString(entries))
            }
            ExportFormat.csv -> File(getExportDir(), "$fileName.csv").also {
                it.writeText(entriesToCsv(entries))
            }
            ExportFormat.txt -> File(getExportDir(), "$fileName.txt").also {
                it.writeText(entriesToTxt(entries))
            }
        }
        return file
    }

    fun exportWithAudio(
        entries: List<JournalEntry>,
        format: ExportFormat = ExportFormat.json,
        includeRawAudio: Boolean = false
    ): File {
        val timestamp = dateFmt.format(Date())
        val exportDir = getExportDir()
        val bundleDir = File(exportDir, "soulo_export_$timestamp")
        bundleDir.mkdirs()

        // Write journal data
        val dataFile = File(bundleDir, "journal.${format.name}")
        when (format) {
            ExportFormat.json -> dataFile.writeText(json.encodeToString(entries))
            ExportFormat.csv -> dataFile.writeText(entriesToCsv(entries))
            ExportFormat.txt -> dataFile.writeText(entriesToTxt(entries))
        }

        // Copy audio files
        if (includeRawAudio) {
            val audioDir = File(bundleDir, "recordings")
            audioDir.mkdirs()
            entries.forEach { entry ->
                entry.audioFile?.let { path ->
                    val source = File(path)
                    if (source.exists()) {
                        source.copyTo(File(audioDir, source.name), overwrite = true)
                    }
                }
            }
        }

        return bundleDir
    }

    fun shareFile(file: File) {
        val uri: Uri = FileProvider.getUriForFile(
            ctx,
            "${ctx.packageName}.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = if (file.isDirectory) "application/zip" else getMimeType(file)
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val label = if (file.isDirectory) "Share Export Bundle" else "Share Export"
        ctx.startActivity(Intent.createChooser(intent, label).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }

    private fun entriesToCsv(entries: List<JournalEntry>): String {
        val sb = StringBuilder()
        sb.appendLine("id,timestamp,title,transcript,emotion,valence,topics,isQuickEntry,source")
        for (entry in entries) {
            val timestamp = entry.timestamp
            val title = csvEscape(entry.transcript?.take(50) ?: "")
            val transcript = csvEscape(entry.transcript ?: "")
            val emotion = entry.emotion?.primaryEmotion?.name ?: ""
            val valence = entry.emotion?.valence?.toString() ?: ""
            val topics = entry.topics?.joinToString(";") { "${it.topic}:${it.sentiment}" } ?: ""
            sb.appendLine("${entry.id},$timestamp,$title,$transcript,$emotion,$valence,$topics,${entry.isQuickEntry},voice")
        }
        return sb.toString()
    }

    private fun entriesToTxt(entries: List<JournalEntry>): String {
        val sb = StringBuilder()
        val df = SimpleDateFormat("MMM d, yyyy HH:mm", Locale.US)
        for (entry in entries.sortedBy { it.timestamp }) {
            sb.appendLine("---")
            sb.appendLine("Date: ${df.format(Date(entry.timestamp * 1000))}")
            sb.appendLine("Title: ${entry.transcript?.take(50) ?: "Untitled"}")
            entry.transcript?.let { sb.appendLine("Transcript: $it") }
            entry.emotion?.let { e ->
                sb.appendLine("Emotion: ${e.primaryEmotion.name} (valence: ${e.valence})")
                if (!e.secondaryEmotions.isNullOrEmpty()) {
                    sb.appendLine("Secondary: ${e.secondaryEmotions.joinToString(", ") { it.name }}")
                }
            }
            if (!entry.topics.isNullOrEmpty()) {
                sb.appendLine("Topics: ${entry.topics.joinToString(", ") { "${it.topic} (${"%.1f".format(it.sentiment)})" }}")
            }
            if (entry.audioFile != null) {
                sb.appendLine("Audio: ${entry.audioFile}")
            }
            sb.appendLine()
        }
        return sb.toString()
    }

    private fun csvEscape(value: String): String {
        return if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
            "\"${value.replace("\"", "\"\"")}\""
        } else value
    }

    private fun getMimeType(file: File): String {
        return when {
            file.extension == "json" -> "application/json"
            file.extension == "csv" -> "text/csv"
            file.extension == "txt" -> "text/plain"
            file.extension == "wav" -> "audio/wav"
            file.isDirectory -> "application/zip"
            else -> "application/octet-stream"
        }
    }
}
