package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class DriftSignificance {
    none, mild, moderate, significant, critical;

    val score: Int get() = when (this) {
        none -> 0; mild -> 25; moderate -> 50; significant -> 75; critical -> 95
    }
}

@Serializable
data class CognitiveDrift(
    val id: String,
    val windowStart: Long,
    val windowEnd: Long,
    val metric: BiomarkerMetric,
    val delta: Double,
    val meanEarly: Double,
    val meanLate: Double,
    val direction: TrendDirection,
    val significance: DriftSignificance,
    val correlation: Map<EmotionType, Double>,
    val detectedAt: Long
) {
    val description: String
        get() {
            val dir = if (direction == TrendDirection.increasing) "increased" else "decreased"
            return "${metric.name} $dir by ${String.format("%.2f", kotlin.math.abs(delta))}"
        }
}

@Serializable
data class DriftReport(
    val id: String,
    val overallSignificance: DriftSignificance,
    val drifts: List<CognitiveDrift>,
    val trendShiftCount: Int,
    val emotionalCorrelation: Map<EmotionType, Double>,
    val gradualVsSudden: DriftType,
    val summary: String,
    val detectedAt: Long
) {
    @Serializable
    enum class DriftType { gradual, sudden, mixed }
}

@Serializable
data class DailyPattern(
    val metric: String,
    val morningAvg: Double, val afternoonAvg: Double,
    val eveningAvg: Double, val nightAvg: Double,
    val morningSampleCount: Int, val afternoonSampleCount: Int,
    val eveningSampleCount: Int, val nightSampleCount: Int,
    val hasSignificantPattern: Boolean
) {
    val peakPeriod: String
        get() = listOf(
            morningAvg to "morning", afternoonAvg to "afternoon",
            eveningAvg to "evening", nightAvg to "night"
        ).maxByOrNull { it.first }?.second ?: "unknown"

    val troughPeriod: String
        get() = listOf(
            morningAvg to "morning", afternoonAvg to "afternoon",
            eveningAvg to "evening", nightAvg to "night"
        ).minByOrNull { it.first }?.second ?: "unknown"
}
