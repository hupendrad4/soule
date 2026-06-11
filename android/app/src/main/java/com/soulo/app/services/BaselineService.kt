package com.soulo.app.services

import com.soulo.app.models.BiomarkerMetric
import com.soulo.app.models.VoiceBiomarkers

object BaselineService {
    private const val MIN_SAMPLES = 5
    private const val STABILITY_THRESHOLD = 0.15
    private const val ANOMALY_Z_SCORE = 2.0

    data class MetricBaseline(
        val metric: BiomarkerMetric,
        val median: Double,
        val p25: Double,
        val p75: Double,
        val mean: Double,
        val stdDev: Double,
        val sampleCount: Int,
        val isStable: Boolean
    )

    data class Anomaly(
        val metric: BiomarkerMetric,
        val value: Double,
        val zScore: Double,
        val direction: com.soulo.app.models.TrendDirection
    )

    fun computeBaseline(entries: List<VoiceBiomarkers>): Map<BiomarkerMetric, MetricBaseline> {
        val baselines = mutableMapOf<BiomarkerMetric, MetricBaseline>()

        for (metric in BiomarkerMetric.entries) {
            val values = entries.mapNotNull { extractMetric(it, metric) }
            if (values.size < MIN_SAMPLES) continue

            val sorted = values.sorted()
            val median = percentile(sorted, 0.5)
            val p25 = percentile(sorted, 0.25)
            val p75 = percentile(sorted, 0.75)
            val mean = values.average()
            val variance = values.map { (it - mean) * (it - mean) }.average()
            val stdDev = sqrt(variance.coerceAtLeast(0.0))
            val isStable = stdDev / (abs(mean).coerceAtLeast(0.001)) < STABILITY_THRESHOLD

            baselines[metric] = MetricBaseline(
                metric = metric, median = median, p25 = p25, p75 = p75,
                mean = mean, stdDev = stdDev, sampleCount = values.size,
                isStable = isStable
            )
        }
        return baselines
    }

    fun detectAnomalies(
        entry: VoiceBiomarkers,
        baselines: Map<BiomarkerMetric, MetricBaseline>
    ): List<Anomaly> {
        val anomalies = mutableListOf<Anomaly>()

        for ((metric, baseline) in baselines) {
            val value = extractMetric(entry, metric) ?: continue
            if (baseline.stdDev <= 0) continue
            val zScore = (value - baseline.mean) / baseline.stdDev
            if (abs(zScore) > ANOMALY_Z_SCORE) {
                anomalies.add(
                    Anomaly(
                        metric = metric,
                        value = value,
                        zScore = zScore,
                        direction = if (zScore > 0)
                            com.soulo.app.models.TrendDirection.increasing
                        else
                            com.soulo.app.models.TrendDirection.decreasing
                    )
                )
            }
        }
        return anomalies
    }

    fun computeDecayWeightedBaseline(
        entries: List<VoiceBiomarkers>,
        maxAgeDays: Int = 30
    ): Map<BiomarkerMetric, Double> {
        val now = System.currentTimeMillis() / 1000
        val decayBase = 0.95
        val baselines = mutableMapOf<BiomarkerMetric, MutableList<Pair<Double, Double>>>()

        for (entry in entries) {
            val ageDays = (now - entry.recordedAt) / 86400.0
            if (ageDays > maxAgeDays) continue
            val weight = decayBase.pow(ageDays)

            for (metric in BiomarkerMetric.entries) {
                val value = extractMetric(entry, metric) ?: continue
                baselines.getOrPut(metric) { mutableListOf() }
                    .add(weight to value)
            }
        }

        return baselines.mapValues { (_, values) ->
            val totalWeight = values.sumOf { it.first }
            if (totalWeight > 0)
                values.sumOf { it.first * it.second } / totalWeight
            else 0.0
        }
    }

    fun computeDailyPattern(entries: List<VoiceBiomarkers>): List<com.soulo.app.models.DailyPattern> {
        val patterns = mutableListOf<com.soulo.app.models.DailyPattern>()

        for (metric in BiomarkerMetric.entries) {
            val values = entries.mapNotNull { entry ->
                val v = extractMetric(entry, metric) ?: return@mapNotNull null
                val hour = java.text.SimpleDateFormat("HH", java.util.Locale.US)
                    .format(java.util.Date(entry.recordedAt * 1000)).toIntOrNull() ?: return@mapNotNull null
                Triple(hour, v, entry.recordedAt)
            }
            if (values.isEmpty()) continue

            val morning = values.filter { it.first in 6..11 }.map { it.second }
            val afternoon = values.filter { it.first in 12..17 }.map { it.second }
            val evening = values.filter { it.first in 18..23 }.map { it.second }
            val night = values.filter { it.first in 0..5 }.map { it.second }

            patterns.add(
                com.soulo.app.models.DailyPattern(
                    metric = metric.name,
                    morningAvg = morning.averageOrZero(),
                    afternoonAvg = afternoon.averageOrZero(),
                    eveningAvg = evening.averageOrZero(),
                    nightAvg = night.averageOrZero(),
                    morningSampleCount = morning.size,
                    afternoonSampleCount = afternoon.size,
                    eveningSampleCount = evening.size,
                    nightSampleCount = night.size,
                    hasSignificantPattern = listOf(morning, afternoon, evening, night)
                        .map { it.averageOrZero() }.let { avgs ->
                            val mean = avgs.average()
                            avgs.any { abs(it - mean) > mean * 0.2 }
                        }
                )
            )
        }
        return patterns
    }

    fun assessMaturity(baselines: Map<BiomarkerMetric, MetricBaseline>): Boolean {
        if (baselines.size < 3) return false
        val stableCount = baselines.values.count { it.isStable }
        return stableCount >= baselines.size / 2
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

    private fun percentile(sorted: List<Double>, p: Double): Double {
        if (sorted.isEmpty()) return 0.0
        val idx = (sorted.size - 1) * p
        val lo = idx.toInt()
        val hi = (lo + 1).coerceAtMost(sorted.size - 1)
        val frac = idx - lo
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }

    private fun sqrt(v: Double): Double = kotlin.math.sqrt(v)
    private fun abs(v: Double): Double = kotlin.math.abs(v)
    private fun Double.pow(exp: Double): Double = kotlin.math.pow(this, exp)

    private fun List<Double>.averageOrZero(): Double = if (isEmpty()) 0.0 else average()
}
