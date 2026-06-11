package com.soulo.app.services

import com.soulo.app.models.*
import com.soulo.app.services.StorageService
import java.util.*

data class DailyInsight(
    val date: String,
    val entryCount: Int,
    val primaryEmotion: String,
    val sentimentScore: Double,
    val notablePhrases: List<String>,
    val patternsToday: List<String>,
    val streak: Int,
    val recommendations: List<String>,
    val hasDecisions: Boolean,
    val decisionQuality: Double?
)

data class RecommendedAction(
    val title: String,
    val description: String,
    val priority: Int,
    val actionType: String
)

object DailyInsightService {
    fun generateDailyInsight(
        todayEntries: List<JournalEntry>,
        allEntries: List<JournalEntry>,
        streak: Int,
        patterns: List<DetectedPattern> = emptyList()
    ): DailyInsight {
        val sorted = todayEntries.sortedBy { it.timestamp }
        val dateFmt = java.text.SimpleDateFormat("EEEE, MMM d", java.util.Locale.US)

        // Primary emotion
        val emotionCounts = mutableMapOf<String, Int>()
        todayEntries.forEach { entry ->
            entry.emotion?.let { e ->
                emotionCounts[e.primaryEmotion.name] = (emotionCounts[e.primaryEmotion.name] ?: 0) + 1
            }
        }
        val primaryEmotion = emotionCounts.maxByOrNull { it.value }?.key ?: "Neutral"

        // Sentiment
        val valences = todayEntries.mapNotNull { it.emotion?.valence }
        val avgValence = if (valences.isNotEmpty()) valences.average() else 0.0

        // Notable phrases from quick entries
        val notablePhrases = sorted
            .filter { it.isQuickEntry && !it.transcript.isNullOrBlank() }
            .map { it.transcript!!.take(100) }
            .take(3)

        // Patterns today
        val patternsToday = patterns.map { it.message }.take(5)

        // Recommendations
        val recommendations = generateActions(
            emotion = primaryEmotion,
            avgValence = avgValence,
            streak = streak,
            patterns = patterns
        )

        // Decision quality
        val todayDecisions = StorageService.instance.loadDecisions()
            .filter { d ->
                val cal = Calendar.getInstance()
                cal.timeInMillis = d.madeAt * 1000
                val today = Calendar.getInstance()
                cal.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    cal.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
            }
        val decisionQuality = if (todayDecisions.isNotEmpty()) {
            val kept = todayDecisions.count { it.status == DecisionStatus.kept }
            kept.toDouble() / todayDecisions.size
        } else null

        return DailyInsight(
            date = dateFmt.format(Date()),
            entryCount = todayEntries.size,
            primaryEmotion = primaryEmotion,
            sentimentScore = avgValence,
            notablePhrases = notablePhrases,
            patternsToday = patternsToday,
            streak = streak,
            recommendations = recommendations.map { it.title },
            hasDecisions = todayDecisions.isNotEmpty(),
            decisionQuality = decisionQuality
        )
    }

    fun generateActions(
        emotion: String,
        avgValence: Double,
        streak: Int,
        patterns: List<DetectedPattern>
    ): List<RecommendedAction> {
        val actions = mutableListOf<RecommendedAction>()

        when {
            avgValence < -0.3 -> actions.add(
                RecommendedAction("Try a grounding exercise",
                    "Take 5 slow breaths. Notice 5 things you can see, 4 you can touch, 3 you can hear.",
                    1, "grounding")
            )
            avgValence > 0.5 -> actions.add(
                RecommendedAction("Capture this feeling",
                    "Write down what went well today. Revisit this entry on a tough day.",
                    1, "capture")
            )
        }

        when {
            streak >= 30 -> actions.add(
                RecommendedAction("Review your journey",
                    "You hit 30 days! Take a moment to reflect on how far you have come.",
                    1, "milestone")
            )
            streak == 7 -> actions.add(
                RecommendedAction("One week streak!",
                    "Seven days of self-reflection is impressive. Check your insights for patterns.",
                    1, "milestone")
            )
            streak == 0 -> actions.add(
                RecommendedAction("Start a new streak",
                    "Even one entry today builds momentum. Every journal matters.",
                    2, "motivation")
            )
        }

        val hasAnxietyPattern = patterns.any { it.type == PatternType.anxietySpike }
        if (hasAnxietyPattern) {
            actions.add(
                RecommendedAction("Anxiety pattern detected",
                    "Your entries suggest recurring anxiety. Consider scheduling a check-in.",
                    1, "alert")
            )
        }

        val sleepPattern = patterns.any { it.type == PatternType.sleepPattern }
        if (sleepPattern) {
            actions.add(
                RecommendedAction("Sleep consistency matters",
                    "Irregular sleep times may affect your mood. Try a consistent bedtime.",
                    2, "habit")
            )
        }

        actions.sortedBy { it.priority }
        return actions
    }
}
