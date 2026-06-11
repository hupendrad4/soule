package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
data class TopicAnalysis(
    val id: String,
    val topic: String,
    val sentiment: Double,
    val confidence: Double,
    val keywords: List<String> = emptyList(),
    val detectedAt: Long
)

@Serializable
data class TopicTrend(
    val topic: String,
    val mentionCount: Int,
    val avgSentiment: Double,
    val sentimentTrend: TrendDirection,
    val firstMentioned: Long,
    val lastMentioned: Long,
    val frequency: Double
)
