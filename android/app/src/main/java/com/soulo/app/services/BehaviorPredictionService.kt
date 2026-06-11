package com.soulo.app.services

import com.soulo.app.models.*
import kotlin.math.max

object BehaviorPredictionService {
    private const val MIN_ENTRIES = 5

    fun predict(entries: List<JournalEntry>, patterns: List<DetectedPattern>, decisions: List<JournalDecision>): List<BehaviorPrediction> {
        if (entries.size < MIN_ENTRIES) return emptyList()
        val predictions = mutableListOf<BehaviorPrediction>()
        val now = System.currentTimeMillis() / 1000

        predictAbandonmentRisk(entries, patterns, predictions, now)
        predictSentimentDrop(entries, predictions, now)
        predictGoalCompletion(patterns, predictions, now)
        predictEmotionalShift(entries, predictions, now)
        predictCrisisRisk(entries, patterns, predictions, now)

        return predictions
    }

    private fun predictAbandonmentRisk(
        entries: List<JournalEntry>, patterns: List<DetectedPattern>,
        predictions: MutableList<BehaviorPrediction>, now: Long
    ) {
        val sorted = entries.sortedByDescending { it.timestamp }
        if (sorted.size < 3) return

        val gaps = sorted.zipWithNext().map { (a, b) -> a.timestamp - b.timestamp }
        val avgGap = if (gaps.isNotEmpty()) gaps.average() else 0.0
        val lastGap = gaps.firstOrNull() ?: 0.0
        val gapRatio = if (avgGap > 0) lastGap / avgGap else 1.0
        val hasWarning = patterns.any { it.type == PatternType.consistencyWarning }
        val probability = ((gapRatio - 1.0).coerceAtLeast(0.0) * 0.5 + if (hasWarning) 0.2 else 0.0)
            .coerceIn(0.0, 1.0)

        if (probability > 0.3) {
            predictions.add(
                BehaviorPrediction(
                    id = "abandon_${sorted.first().id}",
                    type = BehaviorPrediction.PredictionType.abandonmentRisk,
                    probability = probability,
                    confidence = 0.6,
                    description = "Journaling frequency has dropped. Gap ratio: ${String.format("%.1f", gapRatio)}x average.",
                    basedOn = listOf("gap analysis", if (hasWarning) "consistency warnings" else "frequency trend"),
                    expiresAt = now + 7 * 86400,
                    actionable = true,
                    suggestedAction = "Try a quick 30-second entry to maintain the habit."
                )
            )
        }
    }

    private fun predictSentimentDrop(
        entries: List<JournalEntry>,
        predictions: MutableList<BehaviorPrediction>, now: Long
    ) {
        val sorted = entries
            .filter { it.emotion != null }
            .sortedBy { it.timestamp }
        if (sorted.size < 4) return

        val recent = sorted.takeLast(3)
        val older = sorted.dropLast(3).takeLast(3)
        val recentAvg = recent.map { it.emotion!!.valence }.average()
        val olderAvg = older.map { it.emotion!!.valence }.average()
        val drop = olderAvg - recentAvg

        if (drop > 0.3) {
            predictions.add(
                BehaviorPrediction(
                    id = "sentiment_${sorted.last().id}",
                    type = BehaviorPrediction.PredictionType.sentimentDrop,
                    probability = drop.coerceIn(0.0, 1.0),
                    confidence = 0.5,
                    description = "Your average emotional valence dropped ${String.format("%.2f", drop)} points.",
                    basedOn = listOf("valence trend analysis"),
                    expiresAt = now + 3 * 86400,
                    actionable = true,
                    suggestedAction = "Consider what changed in the past few entries."
                )
            )
        }
    }

    private fun predictGoalCompletion(
        patterns: List<DetectedPattern>,
        predictions: MutableList<BehaviorPrediction>, now: Long
    ) {
        val goalCycles = patterns.filter { it.type == PatternType.goalCycle }
        for (gc in goalCycles) {
            if (gc.occurrenceCount >= 2) continue
            val prob = max(0.3, 1.0 - (gc.occurrenceCount * 0.2))
            predictions.add(
                BehaviorPrediction(
                    id = "goal_${gc.id}",
                    type = BehaviorPrediction.PredictionType.goalCompletion,
                    probability = prob,
                    confidence = 0.4,
                    description = "Goal cycle detected: ${gc.title}. ${gc.occurrenceCount} attempt(s) made.",
                    basedOn = listOf("goal cycle analysis"),
                    expiresAt = now + 14 * 86400,
                    actionable = true,
                    suggestedAction = "Break the goal into smaller steps and track daily."
                )
            )
        }
    }

    private fun predictEmotionalShift(
        entries: List<JournalEntry>,
        predictions: MutableList<BehaviorPrediction>, now: Long
    ) {
        val sorted = entries
            .filter { it.emotion != null }
            .sortedBy { it.timestamp }
        if (sorted.size < 4) return

        val emotionSequence = sorted.map { it.emotion!!.primaryEmotion }
        val recent = emotionSequence.takeLast(3).toSet()
        val prev = emotionSequence.dropLast(3).takeLast(3).toSet()

        if (recent.size >= 2 && prev.size <= 2 && recent != prev) {
            predictions.add(
                BehaviorPrediction(
                    id = "eshift_${sorted.last().id}",
                    type = BehaviorPrediction.PredictionType.emotionalShift,
                    probability = 0.5,
                    confidence = 0.4,
                    description = "Your emotional range has shifted from ${prev.joinToString("/")} to ${recent.joinToString("/")}.",
                    basedOn = listOf("emotion transition analysis"),
                    expiresAt = now + 5 * 86400
                )
            )
        }
    }

    private fun predictCrisisRisk(
        entries: List<JournalEntry>, patterns: List<DetectedPattern>,
        predictions: MutableList<BehaviorPrediction>, now: Long
    ) {
        val riskIndicators = listOf(
            "can't do this", "giving up", "hopeless", "worthless",
            "don't want to be here", "can't take it", "nobody cares",
            "better off without", "end this", "too much"
        )

        val recent = entries.takeLast(5)
        var riskCount = 0
        val triggers = mutableListOf<String>()

        for (entry in recent) {
            val text = entry.transcript?.lowercase() ?: continue
            for (indicator in riskIndicators) {
                if (text.contains(indicator)) {
                    riskCount++
                    triggers.add(indicator)
                    break
                }
            }
        }

        val hasDecline = patterns.any { it.type == PatternType.sentimentDecline && it.confidence > 0.7 }
        val riskScore = (riskCount.toDouble() / recent.size.toDouble()) * (if (hasDecline) 1.5 else 1.0)

        if (riskScore > 0.3) {
            predictions.add(
                BehaviorPrediction(
                    id = "crisis_${System.currentTimeMillis()}",
                    type = BehaviorPrediction.PredictionType.crisisRisk,
                    probability = riskScore.coerceIn(0.0, 1.0),
                    confidence = 0.7,
                    description = "Risk indicators detected: ${triggers.joinToString(", ")}. Consider professional support.",
                    basedOn = listOf("risk phrase analysis", if (hasDecline) "sentiment decline" else "baseline"),
                    expiresAt = now + 86400,
                    actionable = true,
                    suggestedAction = "Contact a mental health professional or crisis helpline: 988"
                )
            )
        }
    }
}
