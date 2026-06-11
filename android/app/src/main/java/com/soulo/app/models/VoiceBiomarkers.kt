package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class BiomarkerMetric {
    speechRate, vocalEnergy, pitchInstability, hesitationRate, microBreathCount, jitter, shimmer

}

@Serializable
enum class TrendDirection {
    increasing, decreasing, stable

}

@Serializable
data class BiomarkerTrend(
    val metric: BiomarkerMetric,
    val baseline: Double,
    val current: Double,
    val changePercent: Double,
    val direction: TrendDirection,
    val isAnomalous: Boolean,
    val sampleCount: Int
)

@Serializable
data class VoiceBiomarkers(
    val id: String,
    val speechRate: Double,
    val vocalEnergy: Double,
    val pitchInstability: Double,
    val hesitationRate: Double,
    val microBreathCount: Int,
    val jitter: Double,
    val shimmer: Double,
    val recordedAt: Long
)
