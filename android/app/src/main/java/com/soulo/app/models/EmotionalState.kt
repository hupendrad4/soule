package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class EmotionType {
    joy, sadness, anger, fear, surprise, disgust, neutral, anxiety, excitement, contentment, frustration, hope, gratitude, loneliness, confusion, shame, fatigue
}

@Serializable
data class EmotionalState(
    val id: String,
    val primaryEmotion: EmotionType,
    val secondaryEmotions: List<EmotionType>? = null,
    val confidence: Double,
    val valence: Double,
    val arousal: Double,
    val detectedAt: Long
)
