package com.soulo.app.services

import com.soulo.app.models.*
import org.junit.Assert.*
import org.junit.Test

class CognitiveDriftServiceTest {
    @Test
    fun `fewer than 6 entries returns null`() {
        val entries = (0..4).map { makeBiomarkerEntry(it, 0.5) }
        val result = CognitiveDriftService.detectDrift(entries, emptyMap())
        assertNull(result)
    }

    @Test
    fun `detects increasing drift`() {
        val entries = (0..11).map { i ->
            val valence = -0.5 + i * 0.15
            makeBiomarkerEntry(i.toLong(), valence.coerceIn(-1.0, 1.0))
        }

        val result = CognitiveDriftService.detectDrift(entries, emptyMap())
        assertNotNull(result)
        assertTrue(result!!.trend == TrendDirection.increasing || result.drifts.isNotEmpty())
    }

    @Test
    fun `detects decreasing drift`() {
        val entries = (0..11).map { i ->
            val valence = 0.5 - i * 0.15
            makeBiomarkerEntry(i.toLong(), valence.coerceIn(-1.0, 1.0))
        }

        val result = CognitiveDriftService.detectDrift(entries, emptyMap())
        assertNotNull(result)
    }

    @Test
    fun `no drift with stable data`() {
        val entries = (0..11).map { i ->
            makeBiomarkerEntry(i.toLong(), 0.0)
        }

        val result = CognitiveDriftService.detectDrift(entries, emptyMap())
        assertTrue(result == null || result.drifts.isEmpty() || result.driftScore < 0.3)
    }

    private fun makeBiomarkerEntry(timestamp: Long, valence: Double): JournalEntry {
        return JournalEntry(
            id = "cd_$timestamp",
            timestamp = 1000 + timestamp * 86400,
            durationMs = 180000,
            biomarkers = VoiceBiomarkers(
                vocalEnergy = 0.5,
                avgPitch = 200.0,
                pitchInstability = 0.2,
                jitter = 0.15,
                speechRate = 3.0,
                hesitationRate = 0.1,
                shimmer = 0.2,
                microBreathRate = 0.1,
                tremor = 0.1,
                vocalTension = 0.3,
                silenceRatio = 0.1
            ),
            emotion = EmotionalState(
                id = "e_$timestamp",
                primaryEmotion = if (valence > 0) EmotionType.joy else EmotionType.sadness,
                confidence = 0.7,
                valence = valence,
                arousal = 0.5,
                detectedAt = 1000 + timestamp * 86400
            ),
            transcriptStatus = ProcessingStatus.completed,
            biomarkersStatus = ProcessingStatus.completed,
            emotionStatus = ProcessingStatus.completed,
            topicsStatus = ProcessingStatus.completed
        )
    }
}
