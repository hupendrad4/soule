package com.soulo.app.services

import com.soulo.app.models.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class EmotionDetectionServiceTest {
    @Test
    fun `computeMelSpectrogram returns correct dimensions`() {
        val pcm = ShortArray(16000) { (it % 256 - 128).toShort() }
        val mel = EmotionDetectionService.computeMelSpectrogram(pcm)
        assertTrue("Mel spectrogram should not be empty", mel.isNotEmpty())
        val expectedFrames = (16000 - 400) / 160 + 1
        assertEquals(expectedFrames * 64, mel.size)
    }

    @Test
    fun `heuristic detects excitement from high energy biomarkers`() = runBlocking {
        val bio = VoiceBiomarkers(
            vocalEnergy = 0.85f, avgPitch = 250.0, pitchInstability = 0.2f,
            jitter = 0.1f, speechRate = 5.0f, hesitationRate = 0.05f,
            shimmer = 0.1f, microBreathRate = 0.1f, tremor = 0.05f,
            vocalTension = 0.3f, silenceRatio = 0.05f
        )
        val result = EmotionDetectionService.detect(ShortArray(0), bio)
        assertEquals(EmotionType.excitement, result.primaryEmotion)
    }

    @Test
    fun `heuristic detects sadness from low energy biomarkers`() = runBlocking {
        val bio = VoiceBiomarkers(
            vocalEnergy = 0.2f, avgPitch = 140.0, pitchInstability = 0.1f,
            jitter = 0.1f, speechRate = 1.5f, hesitationRate = 0.3f,
            shimmer = 0.1f, microBreathRate = 0.2f, tremor = 0.1f,
            vocalTension = 0.1f, silenceRatio = 0.3f
        )
        val result = EmotionDetectionService.detect(ShortArray(0), bio)
        assertEquals(EmotionType.sadness, result.primaryEmotion)
    }

    @Test
    fun `defaults to neutral with no biomarkers`() = runBlocking {
        val result = EmotionDetectionService.detect(ShortArray(0), null)
        assertEquals(EmotionType.neutral, result.primaryEmotion)
        assertEquals(0.3, result.confidence, 0.01)
        assertEquals(0.0, result.valence, 0.01)
        assertEquals(0.5, result.arousal, 0.01)
    }

    @Test
    fun `computeValence with happy label returns positive`() {
        val ml = mapOf("happy" to 0.8f, "neutral" to 0.2f)
        val valence = EmotionDetectionService.computeValence(ml, null)
        assertTrue("Valence should be positive for happy", valence > 0.3)
    }

    @Test
    fun `computeValence with sad label returns negative`() {
        val ml = mapOf("sad" to 0.8f, "neutral" to 0.2f)
        val valence = EmotionDetectionService.computeValence(ml, null)
        assertTrue("Valence should be negative for sad", valence < -0.3)
    }

    @Test
    fun `computeArousal with angry label returns high`() {
        val ml = mapOf("angry" to 0.9f)
        val arousal = EmotionDetectionService.computeArousal(ml, null)
        assertTrue("Arousal should be high for angry", arousal > 0.5)
    }
}
