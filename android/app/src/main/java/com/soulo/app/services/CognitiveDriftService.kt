package com.soulo.app.services

import com.soulo.app.models.*
import kotlin.math.abs
import kotlin.math.sqrt

object CognitiveDriftService {
    private const val MIN_ENTRIES = 6
    private const val COHENS_D_THRESHOLD = 0.5

    fun detectDrift(
        entries: List<JournalEntry>,
        baseline: Map<BiomarkerMetric, Double>
    ): DriftReport? {
        val sorted = entries
            .filter { it.biomarkers != null && it.emotion != null }
            .sortedBy { it.timestamp }
        if (sorted.size < MIN_ENTRIES) return null

        val mid = sorted.size / 2
        val early = sorted.take(mid)
        val late = sorted.drop(mid)

        val drifts = mutableListOf<CognitiveDrift>()

        for ((metric, keyPath) in metricExtractors) {
            val earlyVals = early.mapNotNull { keyPath(it.biomarkers) }
            val lateVals = late.mapNotNull { keyPath(it.biomarkers) }
            if (earlyVals.size < 2 || lateVals.size < 2) continue

            val earlyMean = earlyVals.average()
            val lateMean = lateVals.average()
            val delta = lateMean - earlyMean

            val pooledStd = pooledStdDev(earlyVals, lateVals)
            val effectSize = if (pooledStd > 0) delta / pooledStd else 0.0

            val direction = when {
                effectSize > 0 -> TrendDirection.increasing
                effectSize < 0 -> TrendDirection.decreasing
                else -> TrendDirection.stable
            }

            val significance = when {
                abs(effectSize) < 0.2 -> DriftSignificance.none
                abs(effectSize) < 0.5 -> DriftSignificance.mild
                abs(effectSize) < 0.8 -> DriftSignificance.moderate
                abs(effectSize) < 1.2 -> DriftSignificance.significant
                else -> DriftSignificance.critical
            }

            val emotionCorr = correlateWithEmotion(early, late, metric)

            drifts.add(
                CognitiveDrift(
                    id = "cd_$metric",
                    windowStart = early.first().timestamp,
                    windowEnd = late.last().timestamp,
                    metric = metric,
                    delta = delta,
                    meanEarly = earlyMean,
                    meanLate = lateMean,
                    direction = direction,
                    significance = significance,
                    correlation = emotionCorr,
                    detectedAt = System.currentTimeMillis() / 1000
                )
            )
        }

        val significantDrifts = drifts.filter {
            it.significance >= DriftSignificance.moderate
        }
        if (significantDrifts.isEmpty()) return null

        val overallSig = significantDrifts.maxByOrNull { it.significance.score }?.significance
            ?: DriftSignificance.none

        val trendShiftCount = drifts.count {
            val baselineVal = baseline[it.metric] ?: it.meanEarly
            (it.meanLate - baselineVal) / (baselineVal.coerceAtLeast(0.001)) > 0.3
        }

        val emotionalCorr = mutableMapOf<EmotionType, Double>()
        var totalCorr = 0.0
        for (d in drifts) {
            for ((emotion, corr) in d.correlation) {
                emotionalCorr[emotion] = (emotionalCorr[emotion] ?: 0.0) + abs(corr)
                totalCorr += abs(corr)
            }
        }
        if (totalCorr > 0) {
            for ((emotion, value) in emotionalCorr) {
                emotionalCorr[emotion] = value / totalCorr
            }
        }

        val gradualCount = drifts.count {
            abs(it.meanLate - it.meanEarly) < COHENS_D_THRESHOLD
        }
        val driftType = when {
            gradualCount > drifts.size / 2 -> DriftReport.DriftType.gradual
            significantDrifts.size > drifts.size / 2 -> DriftReport.DriftType.sudden
            else -> DriftReport.DriftType.mixed
        }

        val summary = buildString {
            append("Detected ${significantDrifts.size} significant drift(s)")
            if (overallSig >= DriftSignificance.significant) {
                append(". Notable changes: ")
                append(significantDrifts.take(3).joinToString(", ") { it.description })
            }
        }

        return DriftReport(
            id = "drift_${sorted.last().id}",
            overallSignificance = overallSig,
            drifts = drifts,
            trendShiftCount = trendShiftCount,
            emotionalCorrelation = emotionalCorr,
            gradualVsSudden = driftType,
            summary = summary,
            detectedAt = System.currentTimeMillis() / 1000
        )
    }

    private fun pooledStdDev(a: List<Double>, b: List<Double>): Double {
        val meanA = a.average()
        val meanB = b.average()
        val varA = a.map { (it - meanA) * (it - meanA) }.average()
        val varB = b.map { (it - meanB) * (it - meanB) }.average()
        val n1 = a.size.toDouble()
        val n2 = b.size.toDouble()
        return sqrt(((n1 - 1) * varA + (n2 - 1) * varB) / (n1 + n2 - 2))
    }

    private fun correlateWithEmotion(
        early: List<JournalEntry>,
        late: List<JournalEntry>,
        metric: BiomarkerMetric
    ): Map<EmotionType, Double> {
        val correlations = mutableMapOf<EmotionType, Double>()
        val extractor = metricExtractors[metric] ?: return correlations
        val allEntries = early + late
        val lateValences = late.mapNotNull { it.emotion?.valence }

        for (emotion in EmotionType.entries) {
            val lateEmotionVals = late
                .filter { it.emotion?.primaryEmotion == emotion }
                .mapNotNull { extractor(it.biomarkers) }
            if (lateEmotionVals.size < 2) continue
            val lateBaseline = late.mapNotNull { extractor(it.biomarkers) }.average()
            if (lateBaseline == 0.0) continue
            val deviation = (lateEmotionVals.average() - lateBaseline) / lateBaseline
            correlations[emotion] = deviation.coerceIn(-1.0, 1.0)
        }

        return correlations
    }

    private val metricExtractors: Map<BiomarkerMetric, (VoiceBiomarkers?) -> Double?> = mapOf(
        BiomarkerMetric.speechRate to { it?.speechRate },
        BiomarkerMetric.vocalEnergy to { it?.vocalEnergy },
        BiomarkerMetric.pitchInstability to { it?.pitchInstability },
        BiomarkerMetric.hesitationRate to { it?.hesitationRate },
        BiomarkerMetric.microBreathCount to { it?.microBreathCount?.toDouble() },
        BiomarkerMetric.jitter to { it?.jitter },
        BiomarkerMetric.shimmer to { it?.shimmer }
    )
}
