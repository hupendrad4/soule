package com.soulo.app.utilities

import android.app.Activity
import android.content.Context
import com.google.android.play.core.review.ReviewManagerFactory
import com.soulo.app.SouloApplication

object RateAppPrompt {
    private const val PREFS_NAME = "rate_prompt_prefs"
    private const val LAST_PROMPT_KEY = "last_prompt_time"
    private const val ENTRY_COUNT_KEY = "rate_entry_count"
    private const val COOLDOWN_DAYS = 90
    private const val MIN_ENTRIES = 5
    private const val MIN_STREAK = 2

    private val prefs = SouloApplication.instance
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun recordEntry() {
        val count = prefs.getInt(ENTRY_COUNT_KEY, 0) + 1
        prefs.edit().putInt(ENTRY_COUNT_KEY, count).apply()
    }

    fun shouldPrompt(currentStreak: Int = 0, hasPositiveSentiment: Boolean = false): Boolean {
        val entryCount = prefs.getInt(ENTRY_COUNT_KEY, 0)
        if (entryCount < MIN_ENTRIES) return false

        val lastPrompt = prefs.getLong(LAST_PROMPT_KEY, 0)
        val daysSinceLastPrompt = (System.currentTimeMillis() - lastPrompt) / 86400000
        if (daysSinceLastPrompt < COOLDOWN_DAYS) return false

        // Check thresholds: 5, 10, 20, 50, 100 entries
        val thresholds = listOf(5, 10, 20, 50, 100)
        val passedThreshold = thresholds.any { entryCount >= it && entryCount < it + 3 }

        return passedThreshold && currentStreak >= MIN_STREAK
    }

    fun launchReview(activity: Activity, onComplete: (Boolean) -> Unit = {}) {
        val manager = ReviewManagerFactory.create(activity)
        val request = manager.requestReviewFlow()
        request.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val reviewInfo = task.result
                val flow = manager.launchReviewFlow(activity, reviewInfo)
                flow.addOnCompleteListener {
                    prefs.edit().putLong(LAST_PROMPT_KEY, System.currentTimeMillis()).apply()
                    onComplete(true)
                }
            } else {
                onComplete(false)
            }
        }
    }
}
