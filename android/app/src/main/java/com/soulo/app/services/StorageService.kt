package com.soulo.app.services

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.soulo.app.models.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString

class StorageService(context: Context) : SQLiteOpenHelper(context, "soulo.db", null, 6) {
    companion object {
        val instance: StorageService by lazy { StorageService(com.soulo.app.SouloApplication.instance) }
    }
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE entries (
                id TEXT PRIMARY KEY, timestamp INTEGER, duration_ms INTEGER,
                transcript TEXT, audio_file TEXT, is_quick_entry INTEGER DEFAULT 0,
                biomarkers_json TEXT, emotion_json TEXT, topics_json TEXT,
                transcript_status TEXT DEFAULT 'pending', biomarkers_status TEXT DEFAULT 'pending',
                emotion_status TEXT DEFAULT 'pending', topics_status TEXT DEFAULT 'pending',
                app_version TEXT, device_model TEXT, os_version TEXT,
                created_at INTEGER, updated_at INTEGER
            )
        """)
        db.execSQL("""
            CREATE TABLE patterns (
                id TEXT PRIMARY KEY, type TEXT, title TEXT, message TEXT,
                confidence REAL, first_detected INTEGER, last_detected INTEGER,
                occurrence_count INTEGER DEFAULT 1, related_topic TEXT,
                related_emotions TEXT
            )
        """)
        db.execSQL("""
            CREATE TABLE decisions (
                id TEXT PRIMARY KEY, decision_text TEXT, category TEXT,
                made_at INTEGER, status TEXT, days_since_decision INTEGER,
                follow_up_sentiment REAL, regret_score REAL
            )
        """)
        db.execSQL("""
            CREATE TABLE insights (
                id TEXT PRIMARY KEY, type TEXT, title TEXT, message TEXT,
                relevance_score REAL, related_patterns TEXT,
                generated_at INTEGER, read INTEGER DEFAULT 0
            )
        """)
        db.execSQL("""
            CREATE TABLE settings (
                key TEXT PRIMARY KEY, value TEXT
            )
        """)
        db.execSQL("CREATE TABLE IF NOT EXISTS baseline_cache (metric TEXT PRIMARY KEY, value REAL, sample_count INTEGER, updated_at INTEGER)")
        db.execSQL("CREATE TABLE IF NOT EXISTS predictions_cache (id TEXT PRIMARY KEY, data TEXT, expires_at INTEGER)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 6) {
            db.execSQL("CREATE TABLE IF NOT EXISTS baseline_cache (metric TEXT PRIMARY KEY, value REAL, sample_count INTEGER, updated_at INTEGER)")
            db.execSQL("CREATE TABLE IF NOT EXISTS predictions_cache (id TEXT PRIMARY KEY, data TEXT, expires_at INTEGER)")
        }
    }

    fun saveEntry(entry: JournalEntry) {
        val db = writableDatabase
        db.execSQL("""
            INSERT OR REPLACE INTO entries 
            (id, timestamp, duration_ms, transcript, audio_file, is_quick_entry,
             biomarkers_json, emotion_json, topics_json,
             transcript_status, biomarkers_status, emotion_status, topics_status,
             app_version, device_model, os_version, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arrayOf(
            entry.id, entry.timestamp, entry.durationMs,
            entry.transcript, entry.audioFile, if (entry.isQuickEntry) 1 else 0,
            entry.biomarkers?.let { json.encodeToString(it) },
            entry.emotion?.let { json.encodeToString(it) },
            entry.topics?.let { json.encodeToString(it) },
            entry.transcriptStatus.name, entry.biomarkersStatus.name,
            entry.emotionStatus.name, entry.topicsStatus.name,
            entry.appVersion, entry.deviceModel, entry.osVersion,
            entry.createdAt, entry.updatedAt
        ))
    }

    fun loadEntries(limit: Int = 50, offset: Int = 0): List<JournalEntry> {
        val db = readableDatabase
        val cursor = db.rawQuery(
            "SELECT * FROM entries ORDER BY timestamp DESC LIMIT ? OFFSET ?",
            arrayOf(limit.toString(), offset.toString())
        )
        val entries = mutableListOf<JournalEntry>()
        while (cursor.moveToNext()) {
            entries.add(parseEntry(cursor))
        }
        cursor.close()
        return entries
    }

    fun deleteEntry(id: String) {
        writableDatabase.delete("entries", "id = ?", arrayOf(id))
    }

    fun entryCount(): Int {
        val cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM entries", null)
        cursor.moveToFirst()
        val count = cursor.getInt(0)
        cursor.close()
        return count
    }

    fun savePatterns(patterns: List<DetectedPattern>) {
        val db = writableDatabase
        db.execSQL("DELETE FROM patterns")
        for (p in patterns) {
            db.execSQL("""
                INSERT INTO patterns (id, type, title, message, confidence, first_detected,
                    last_detected, occurrence_count, related_topic, related_emotions)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arrayOf(
                p.id, p.type.name, p.title, p.message, p.confidence,
                p.firstDetected, p.lastDetected, p.occurrenceCount,
                p.relatedTopic, p.relatedEmotions.joinToString(",") { it.name }
            ))
        }
    }

    fun loadPatterns(): List<DetectedPattern> {
        val db = readableDatabase
        val cursor = db.rawQuery("SELECT * FROM patterns ORDER BY first_detected DESC", null)
        val patterns = mutableListOf<DetectedPattern>()
        while (cursor.moveToNext()) {
            patterns.add(
                DetectedPattern(
                    id = cursor.getString(cursor.getColumnIndexOrThrow("id")),
                    type = PatternType.valueOf(cursor.getString(cursor.getColumnIndexOrThrow("type"))),
                    title = cursor.getString(cursor.getColumnIndexOrThrow("title")),
                    message = cursor.getString(cursor.getColumnIndexOrThrow("message")),
                    confidence = cursor.getDouble(cursor.getColumnIndexOrThrow("confidence")),
                    firstDetected = cursor.getLong(cursor.getColumnIndexOrThrow("first_detected")),
                    lastDetected = cursor.getLong(cursor.getColumnIndexOrThrow("last_detected")),
                    occurrenceCount = cursor.getInt(cursor.getColumnIndexOrThrow("occurrence_count")),
                    relatedTopic = cursor.getString(cursor.getColumnIndexOrThrow("related_topic")),
                    relatedEmotions = emptyList()
                )
            )
        }
        cursor.close()
        return patterns
    }

    fun saveDecisions(decisions: List<JournalDecision>) {
        val db = writableDatabase
        db.execSQL("DELETE FROM decisions")
        for (d in decisions) {
            db.execSQL("""
                INSERT OR REPLACE INTO decisions (id, decision_text, category, made_at, status,
                    days_since_decision, follow_up_sentiment, regret_score)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arrayOf(
                d.id, d.decisionText, d.category?.name, d.madeAt, d.status.name,
                d.daysSinceDecision, d.followUpSentiment, d.regretScore
            ))
        }
    }

    fun loadDecisions(): List<JournalDecision> {
        val db = readableDatabase
        val cursor = db.rawQuery("SELECT * FROM decisions ORDER BY made_at DESC", null)
        val decisions = mutableListOf<JournalDecision>()
        while (cursor.moveToNext()) {
            decisions.add(
                JournalDecision(
                    id = cursor.getString(cursor.getColumnIndexOrThrow("id")),
                    decisionText = cursor.getString(cursor.getColumnIndexOrThrow("decision_text")),
                    category = cursor.getString(cursor.getColumnIndexOrThrow("category"))?.let { DecisionCategory.valueOf(it) },
                    madeAt = cursor.getLong(cursor.getColumnIndexOrThrow("made_at")),
                    status = DecisionStatus.valueOf(cursor.getString(cursor.getColumnIndexOrThrow("status"))),
                    daysSinceDecision = cursor.getInt(cursor.getColumnIndexOrThrow("days_since_decision")),
                    followUpSentiment = cursor.getDouble(cursor.getColumnIndexOrThrow("follow_up_sentiment")).takeIf { !it.isNaN() },
                    regretScore = cursor.getDouble(cursor.getColumnIndexOrThrow("regret_score")).takeIf { !it.isNaN() }
                )
            )
        }
        cursor.close()
        return decisions
    }

    fun saveSettings(settings: Settings) {
        val db = writableDatabase
        val map = mapOf(
            "dailyReminderEnabled" to settings.dailyReminderEnabled.toString(),
            "reminderHour" to settings.reminderHour.toString(),
            "reminderMinute" to settings.reminderMinute.toString(),
            "dailyInsightEnabled" to settings.dailyInsightEnabled.toString(),
            "insightHour" to settings.insightHour.toString(),
            "insightMinute" to settings.insightMinute.toString(),
            "keepRawAudio" to settings.keepRawAudio.toString(),
            "backupEnabled" to settings.backupEnabled.toString(),
            "backupFrequency" to settings.backupFrequency.name,
            "faceIdEnabled" to settings.faceIdEnabled.toString(),
            "hapticFeedback" to settings.hapticFeedback.toString(),
            "modelDownloaded" to settings.modelDownloaded.toString()
        )
        db.execSQL("DELETE FROM settings")
        for ((key, value) in map) {
            db.execSQL("INSERT INTO settings (key, value) VALUES (?, ?)", arrayOf(key, value))
        }
    }

    fun loadSettings(): Settings {
        val db = readableDatabase
        val cursor = db.rawQuery("SELECT key, value FROM settings", null)
        val map = mutableMapOf<String, String>()
        while (cursor.moveToNext()) {
            map[cursor.getString(0)] = cursor.getString(1)
        }
        cursor.close()
        return Settings(
            dailyReminderEnabled = map["dailyReminderEnabled"]?.toBoolean() ?: true,
            reminderHour = map["reminderHour"]?.toIntOrNull() ?: 20,
            reminderMinute = map["reminderMinute"]?.toIntOrNull() ?: 0,
            dailyInsightEnabled = map["dailyInsightEnabled"]?.toBoolean() ?: true,
            insightHour = map["insightHour"]?.toIntOrNull() ?: 7,
            insightMinute = map["insightMinute"]?.toIntOrNull() ?: 30,
            keepRawAudio = map["keepRawAudio"]?.toBoolean() ?: false,
            backupEnabled = map["backupEnabled"]?.toBoolean() ?: false,
            backupFrequency = map["backupFrequency"]?.let { BackupFrequency.valueOf(it) } ?: BackupFrequency.weekly,
            faceIdEnabled = map["faceIdEnabled"]?.toBoolean() ?: true,
            hapticFeedback = map["hapticFeedback"]?.toBoolean() ?: true,
            modelDownloaded = map["modelDownloaded"]?.toBoolean() ?: false
        )
    }

    private fun parseEntry(cursor: android.database.Cursor): JournalEntry {
        return JournalEntry(
            id = cursor.getString(cursor.getColumnIndexOrThrow("id")),
            timestamp = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp")),
            durationMs = cursor.getLong(cursor.getColumnIndexOrThrow("duration_ms")),
            transcript = cursor.getString(cursor.getColumnIndexOrThrow("transcript")),
            audioFile = cursor.getString(cursor.getColumnIndexOrThrow("audio_file")),
            isQuickEntry = cursor.getInt(cursor.getColumnIndexOrThrow("is_quick_entry")) == 1,
            biomarkers = cursor.getString(cursor.getColumnIndexOrThrow("biomarkers_json"))?.let {
                try { json.decodeFromString<VoiceBiomarkers>(it) } catch (_: Exception) { null }
            },
            emotion = cursor.getString(cursor.getColumnIndexOrThrow("emotion_json"))?.let {
                try { json.decodeFromString<EmotionalState>(it) } catch (_: Exception) { null }
            },
            topics = cursor.getString(cursor.getColumnIndexOrThrow("topics_json"))?.let {
                try { json.decodeFromString<List<TopicAnalysis>>(it) } catch (_: Exception) { null }
            },
            transcriptStatus = ProcessingStatus.valueOf(cursor.getString(cursor.getColumnIndexOrThrow("transcript_status"))),
            biomarkersStatus = ProcessingStatus.valueOf(cursor.getString(cursor.getColumnIndexOrThrow("biomarkers_status"))),
            emotionStatus = ProcessingStatus.valueOf(cursor.getString(cursor.getColumnIndexOrThrow("emotion_status"))),
            topicsStatus = ProcessingStatus.valueOf(cursor.getString(cursor.getColumnIndexOrThrow("topics_status"))),
            appVersion = cursor.getString(cursor.getColumnIndexOrThrow("app_version")) ?: "1.0.0",
            deviceModel = cursor.getString(cursor.getColumnIndexOrThrow("device_model")) ?: "",
            osVersion = cursor.getString(cursor.getColumnIndexOrThrow("os_version")) ?: "",
            createdAt = cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
            updatedAt = cursor.getLong(cursor.getColumnIndexOrThrow("updated_at"))
        )
    }
}
