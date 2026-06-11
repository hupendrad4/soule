package com.soulo.app.services

import com.soulo.app.models.BiomarkerMetric
import com.soulo.app.models.BiomarkerTrend
import com.soulo.app.models.TrendDirection
import com.soulo.app.models.VoiceBiomarkers

object BiomarkerTrendService {

    fun computeTrends(
        entries: List<VoiceBiomarkers>,
        baselines: Map<BiomarkerMetric, BaselineService.MetricBaseline>
    ): List<BiomarkerTrend> {
        val trends = mutableListOf<BiomarkerTrend>()
        if (entries.size < 3) return trends

        for (metric in BiomarkerMetric.entries) {
            val values = entries.mapNotNull { extractMetric(it, metric) }
            if (values.size < 3) continue

            val current = values.average()
            val recent = values.takeLast(maxOf(values.size / 3, 3)).average()
            val baseline = baselines[metric]

            val direction = computeDirection(values)
            val changePercent = if (baseline != null && baseline.mean != 0.0)
                (current - baseline.mean) / abs(baseline.mean)
            else 0.0

            val isAnomalous = baseline != null && abs(changePercent) > 0.3

            trends.add(
                BiomarkerTrend(
                    metric = metric,
                    baseline = baseline?.mean ?: current,
                    current = recent,
                    changePercent = changePercent,
                    direction = direction,
                    isAnomalous = isAnomalous,
                    sampleCount = values.size
                )
            )
        }
        return trends
    }

    fun computeSlope(values: List<Double>): Double {
        if (values.size < 2) return 0.0
        val n = values.size.toDouble()
        val indices = (1..values.size).map { it.toDouble() }

        val sumX = indices.sum()
        val sumY = values.sum()
        val sumXY = indices.zip(values).sumOf { it.first * it.second }
        val sumX2 = indices.sumOf { it * it }

        val denom = n * sumX2 - sumX * sumX
        if (denom == 0.0) return 0.0
        return (n * sumXY - sumX * sumY) / denom
    }

    fun computeDirection(values: List<Double>): TrendDirection {
        if (values.size < 3) return TrendDirection.stable
        val slope = computeSlope(values)
        val threshold = 0.01 * abs(values.average()).coerceAtLeast(0.001)
        return when {
            slope > threshold -> TrendDirection.increasing
            slope < -threshold -> TrendDirection.decreasing
            else -> TrendDirection.stable
        }
    }

    fun computeRollingAverage(values: List<Double>, window: Int): List<Double> {
        if (values.size < window) return emptyList()
        return (0..values.size - window).map { i ->
            values.subList(i, i + window).average()
        }
    }

    private fun extractMetric(b: VoiceBiomarkers, metric: BiomarkerMetric): Double? = when (metric) {
        BiomarkerMetric.speechRate -> b.speechRate
        BiomarkerMetric.vocalEnergy -> b.vocalEnergy
        BiomarkerMetric.pitchInstability -> b.pitchInstability
        BiomarkerMetric.hesitationRate -> b.hesitationRate
        BiomarkerMetric.microBreathCount -> b.microBreathCount.toDouble()
        BiomarkerMetric.jitter -> b.jitter
        BiomarkerMetric.shimmer -> b.shimmer
    }

    private fun abs(v: Double): Double = kotlin.math.abs(v)
}
