package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class BackupFrequency { daily, weekly, monthly, never }

@Serializable
data class Settings(
    val dailyReminderEnabled: Boolean = true,
    val reminderHour: Int = 20,
    val reminderMinute: Int = 0,
    val dailyInsightEnabled: Boolean = true,
    val insightHour: Int = 7,
    val insightMinute: Int = 30,
    val keepRawAudio: Boolean = false,
    val backupEnabled: Boolean = false,
    val backupFrequency: BackupFrequency = BackupFrequency.weekly,
    val faceIdEnabled: Boolean = true,
    val hapticFeedback: Boolean = true,
    val modelDownloaded: Boolean = false,
    val hasCompletedOnboarding: Boolean = false
)
