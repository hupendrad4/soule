package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
data class BehaviorPrediction(
    val id: String,
    val type: PredictionType,
    val probability: Double,
    val confidence: Double,
    val description: String,
    val basedOn: List<String>,
    val expiresAt: Long,
    val actionable: Boolean = false,
    val suggestedAction: String? = null
) {
    @Serializable
    enum class PredictionType {
        abandonmentRisk, sentimentDrop, goalCompletion,
        emotionalShift, patternReemergence, crisisRisk
    }
}
