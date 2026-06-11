package com.soulo.app.services

import android.content.Context
import com.soulo.app.SouloApplication
import com.soulo.app.models.*
import com.soulo.app.services.StorageService
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.json.JSONObject
import java.io.*

enum class RecoveryAction { retry, skip, abort }
data class RecoveryPlan(val action: RecoveryAction, val detail: String)

object ErrorRecoveryService {
    private const val MAX_RETRY = 3
    private const val CRASH_LOG = "crash_recovery.json"
    private const val BACKUP_DIR = "recovery_backups"
    private val ctx = SouloApplication.instance
    private val storage = StorageService.instance

    data class RecoveryState(
        val stage: String,
        val recordingPath: String?,
        val transcriptionProgress: Int,
        val analysisProgress: Int,
        val retryCount: Int = 0
    )

    fun saveRecoveryState(state: RecoveryState) {
        try {
            val json = JSONObject().apply {
                put("stage", state.stage)
                put("recording_path", state.recordingPath ?: JSONObject.NULL)
                put("transcription_progress", state.transcriptionProgress)
                put("analysis_progress", state.analysisProgress)
                put("retry_count", state.retryCount)
            }
            ctx.openFileOutput(CRASH_LOG, Context.MODE_PRIVATE).use {
                it.write(json.toString(2).toByteArray())
            }
        } catch (_: Exception) {}
    }

    fun clearRecoveryState() {
        ctx.deleteFile(CRASH_LOG)
    }

    fun loadRecoveryState(): RecoveryState? {
        return try {
            val json = ctx.openFileInput(CRASH_LOG).bufferedReader().use { it.readText() }
            val obj = JSONObject(json)
            RecoveryState(
                stage = obj.getString("stage"),
                recordingPath = obj.optString("recording_path", null).takeIf { it != "null" },
                transcriptionProgress = obj.getInt("transcription_progress"),
                analysisProgress = obj.getInt("analysis_progress"),
                retryCount = obj.optInt("retry_count", 0)
            )
        } catch (_: Exception) { null }
    }

    fun assessAndRecover(state: RecoveryState): RecoveryPlan {
        return when {
            state.retryCount >= MAX_RETRY -> {
                if (state.recordingPath != null) {
                    // Try to recover raw recording, skip analysis
                    val recordingFile = File(state.recordingPath)
                    if (recordingFile.exists()) {
                        // Create entry from raw recording
                        RecoveryPlan(RecoveryAction.retry,
                            "Previous session crashed after ${state.stage}. Raw audio preserved; re-processing.")
                    } else {
                        RecoveryPlan(RecoveryAction.skip,
                            "Previous session crashed. Raw audio lost; skipping.")
                    }
                } else {
                    RecoveryPlan(RecoveryAction.skip,
                        "Previous session crashed in ${state.stage} after ${state.retryCount} retries.")
                }
            }
            state.stage == "transcription" && state.transcriptionProgress < 100 -> {
                RecoveryPlan(RecoveryAction.retry, "Resuming transcription from ${state.transcriptionProgress}%")
            }
            state.stage == "analysis" && state.analysisProgress < 100 -> {
                RecoveryPlan(RecoveryAction.retry, "Resuming analysis from ${state.analysisProgress}%")
            }
            else -> RecoveryPlan(RecoveryAction.skip, "Recovery state is stale; starting fresh.")
        }
    }

    // Backup an entry before potentially destructive operation
    private val backupJson = Json { prettyPrint = true; ignoreUnknownKeys = true }

    fun backupEntryForRecovery(entry: JournalEntry) {
        try {
            val dir = File(ctx.filesDir, BACKUP_DIR)
            dir.mkdirs()
            val file = File(dir, "entry_${System.currentTimeMillis()}.json")
            file.writeText(backupJson.encodeToString(entry))
        } catch (_: Exception) {}
    }

    fun listBackups(): List<File> {
        val dir = File(ctx.filesDir, BACKUP_DIR)
        return if (dir.exists()) dir.listFiles()?.sortedByDescending { it.lastModified() }?.take(10) ?: emptyList()
        else emptyList()
    }

    fun restoreFromBackup(file: File): JournalEntry? {
        return try {
            backupJson.decodeFromString<JournalEntry>(file.readText())
        } catch (_: Exception) { null }
    }

    fun cleanupOldBackups() {
        val dir = File(ctx.filesDir, BACKUP_DIR)
        if (!dir.exists()) return
        val files = dir.listFiles()?.sortedByDescending { it.lastModified() } ?: return
        if (files.size > 20) {
            files.drop(20).forEach { it.delete() }
        }
    }
}
