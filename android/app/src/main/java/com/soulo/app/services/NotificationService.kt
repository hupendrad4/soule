package com.soulo.app.services

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.soulo.app.MainActivity
import com.soulo.app.SouloApplication
import java.util.Calendar

class NotificationService {
    companion object {
        private const val JOURNAL_CHANNEL_ID = "daily_journal"
        private const val INSIGHT_CHANNEL_ID = "daily_insight"
        private const val JOURNAL_REQUEST_CODE = 1001
        private const val INSIGHT_REQUEST_CODE = 1002
        private const val PREFS_NAME = "notification_prefs"
        private const val STREAK_KEY = "current_streak"

        private val prompts = listOf(
            "How was your day?",
            "What's on your mind?",
            "What are you grateful for today?",
            "Describe a moment that mattered today.",
            "What challenged you today?",
            "How are you feeling right now?",
            "What did you learn about yourself today?",
            "What would you tell your future self?",
            "What's one thing you'd do differently?",
            "What made you smile today?"
        )

        fun randomPrompt(): String = prompts.random()
    }

    private val context = SouloApplication.instance
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // --- Streak ---

    fun getCurrentStreak(): Int = prefs.getInt(STREAK_KEY, 0)

    fun incrementStreak() {
        val streak = getCurrentStreak() + 1
        prefs.edit().putInt(STREAK_KEY, streak).apply()
    }

    fun resetStreak() {
        prefs.edit().putInt(STREAK_KEY, 0).apply()
    }

    // --- Daily Journal Reminder ---

    fun scheduleJournalReminder(hour: Int = 20, minute: Int = 0) {
        cancelReminder(JOURNAL_REQUEST_CODE)

        val intent = Intent(context, JournalReminderReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context, JOURNAL_REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            if (before(Calendar.getInstance())) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setRepeating(
            AlarmManager.RTC_WAKEUP,
            calendar.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pendingIntent
        )
    }

    fun cancelJournalReminder() {
        cancelReminder(JOURNAL_REQUEST_CODE)
    }

    // --- Daily Insight ---

    fun scheduleInsightNotification(hour: Int = 7, minute: Int = 30) {
        cancelReminder(INSIGHT_REQUEST_CODE)

        val intent = Intent(context, InsightReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context, INSIGHT_REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            if (before(Calendar.getInstance())) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setRepeating(
            AlarmManager.RTC_WAKEUP,
            calendar.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pendingIntent
        )
    }

    fun cancelInsightNotification() {
        cancelReminder(INSIGHT_REQUEST_CODE)
    }

    private fun cancelReminder(requestCode: Int) {
        val intent = Intent(context, JournalReminderReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
    }

    // --- Show Notification ---

    fun showNotification(channelId: String, title: String, message: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(
                System.currentTimeMillis().toInt(), notification
            )
        } catch (_: SecurityException) {}
    }
}

class JournalReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationService = NotificationService()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Permission check handled by SouloApplication's manifest
        }
        notificationService.showNotification(
            "daily_journal",
            "Soulo",
            NotificationService.randomPrompt()
        )
    }
}

class InsightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationService = NotificationService()
        notificationService.showNotification(
            "daily_insight",
            "Daily Insight",
            "Your morning insight is ready. Open Soulo to see it."
        )
    }
}
