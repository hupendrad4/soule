package com.soulo.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager

class SouloApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        val journalChannel = NotificationChannel(
            "daily_journal",
            "Journal Reminders",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply { description = "Daily journaling reminders" }

        val insightChannel = NotificationChannel(
            "daily_insight",
            "Daily Insights",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply { description = "Personalized daily insights" }

        val processingChannel = NotificationChannel(
            "processing",
            "Processing Status",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Entry processing notifications" }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(journalChannel)
        manager.createNotificationChannel(insightChannel)
        manager.createNotificationChannel(processingChannel)
    }

    companion object {
        lateinit var instance: SouloApplication
            private set
    }
}
