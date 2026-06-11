package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class ProcessingStatus { pending, processing, completed, failed }

@Serializable
data class JournalEntry(
    val id: String,
    val timestamp: Long,
    val durationMs: Long,
    val transcript: String? = null,
    val audioFile: String? = null,
    val isQuickEntry: Boolean = false,
    val biomarkers: VoiceBiomarkers? = null,
    val emotion: EmotionalState? = null,
    val topics: List<TopicAnalysis>? = null,
    val transcriptStatus: ProcessingStatus = ProcessingStatus.pending,
    val biomarkersStatus: ProcessingStatus = ProcessingStatus.pending,
    val emotionStatus: ProcessingStatus = ProcessingStatus.pending,
    val topicsStatus: ProcessingStatus = ProcessingStatus.pending,
    val appVersion: String = "1.0.0",
    val deviceModel: String = "",
    val osVersion: String = "",
    val createdAt: Long = System.currentTimeMillis() / 1000,
    val updatedAt: Long = System.currentTimeMillis() / 1000
) {
    val formattedDate: String
        get() = java.text.SimpleDateFormat("MMM d, yyyy", java.util.Locale.getDefault())
            .format(java.util.Date(timestamp * 1000))

    val durationFormatted: String
        get() {
            val secs = durationMs / 1000
            val m = secs / 60
            val s = secs % 60
            return "${m}m ${s}s"
        }

    companion object {
        val deviceModel: String get() = android.os.Build.MODEL
        val osVersion: String get() = android.os.Build.VERSION.RELEASE
    }
}
