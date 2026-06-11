package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class PatternType {
    brokenPromise, topicAvoidance, sentimentDecline, goalCycle,
    contradiction, cognitiveShift, relationshipPattern, decisionRegret,
    improvement, consistencyWarning, emotionalTrend, reflectionPrompt,
    anxietySpike, sleepPattern

}

@Serializable
data class DetectedPattern(
    val id: String,
    val type: PatternType,
    val title: String,
    val message: String,
    val confidence: Double,
    val firstDetected: Long,
    val lastDetected: Long,
    val occurrenceCount: Int = 1,
    val relatedTopic: String? = null,
    val relatedEmotions: List<EmotionType> = emptyList()
)
