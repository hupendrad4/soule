package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class InsightType {
    pattern, milestone, improvement, warning, decision, emotionTrend, consistency, reflectionPrompt
}

@Serializable
data class DailyInsight(
    val id: String,
    val type: InsightType,
    val title: String,
    val message: String,
    val relevanceScore: Double,
    val relatedPatterns: List<String> = emptyList(),
    val generatedAt: Long,
    val read: Boolean = false
)
