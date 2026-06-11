package com.soulo.app.services

import com.soulo.app.models.*
import org.junit.Assert.*
import org.junit.Test

class PatternDetectionServiceTest {
    private fun makeEntry(
        id: String = "test_$idCounter",
        timestamp: Long = System.currentTimeMillis() / 1000,
        emotion: EmotionalState? = null,
        biomarkers: VoiceBiomarkers? = null,
        transcript: String? = null
    ): JournalEntry {
        idCounter++
        return JournalEntry(
            id = id,
            timestamp = timestamp,
            durationMs = 180000,
            transcript = transcript,
            biomarkers = biomarkers,
            emotion = emotion,
            transcriptStatus = ProcessingStatus.completed,
            biomarkersStatus = ProcessingStatus.completed,
            emotionStatus = ProcessingStatus.completed,
            topicsStatus = ProcessingStatus.completed
        )
    }

    companion object {
        var idCounter = 0
    }

    @Test
    fun `empty entries returns no patterns`() {
        val result = PatternDetectionService.detectPatterns(emptyList(), emptyList())
        assertTrue(result.isEmpty())
    }

    @Test
    fun `single entry returns no patterns`() {
        val entry = makeEntry(emotion = EmotionalState(
            id = "e1", primaryEmotion = EmotionType.joy, confidence = 0.8,
            valence = 0.7, arousal = 0.5, detectedAt = 1000
        ))
        val result = PatternDetectionService.detectPatterns(listOf(entry), emptyList())
        assertTrue(result.isEmpty())
    }

    @Test
    fun `detects sentiment decline`() {
        val entries = (0..9).map { i ->
            makeEntry(
                id = "sent_$i",
                timestamp = 1000L + i * 86400,
                emotion = EmotionalState(
                    id = "e$i", primaryEmotion = if (i < 3) EmotionType.joy else EmotionType.sadness,
                    confidence = 0.7, valence = 1.0 - i * 0.2, arousal = 0.5, detectedAt = 1000L + i * 86400
                )
            )
        }

        val existing = listOf(
            DetectedPattern("p1", "Previous", "Prev", PatternType.sentimentDecline, 0.5, emptyList(), 1000)
        )
        val result = PatternDetectionService.detectPatterns(entries, existing)
        assertTrue(result.any { it.type == PatternType.sentimentDecline })
    }

    @Test
    fun `anxiety spike detection`() {
        val entries = listOf(
            makeEntry(id = "calm", biomarkers = VoiceBiomarkers(0.3, 150.0, 0.1, 0.1, 2.5, 0.05, 0.15, 0.1, 0.1, 0.2, 0.0)),
            makeEntry(id = "anxious1", biomarkers = VoiceBiomarkers(0.8, 280.0, 0.5, 0.3, 5.0, 0.3, 0.5, 0.4, 0.2, 0.1, 0.0)),
            makeEntry(id = "anxious2", biomarkers = VoiceBiomarkers(0.85, 300.0, 0.55, 0.35, 5.5, 0.35, 0.55, 0.45, 0.25, 0.15, 0.0)),
            makeEntry(id = "anxious3", biomarkers = VoiceBiomarkers(0.75, 270.0, 0.45, 0.28, 4.8, 0.28, 0.48, 0.38, 0.18, 0.12, 0.0))
        )

        val result = PatternDetectionService.detectPatterns(entries, emptyList())
        assertTrue(result.any { it.type == PatternType.anxietySpike })
    }

    @Test
    fun `habit consistency detection`() {
        val entries = (0..6).map { i ->
            makeEntry(
                id = "habit_$i",
                timestamp = 1000L + i * 86400,
                emotion = EmotionalState("e$i", EmotionType.neutral, 0.5, 0.0, 0.5, detectedAt = 1000L + i * 86400)
            )
        }

        val result = PatternDetectionService.detectPatterns(entries, emptyList())
        assertTrue(result.any { it.type == PatternType.consistencyWarning || it.type == PatternType.habitFormation })
    }
}
