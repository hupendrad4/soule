package com.soulo.app.services

import com.soulo.app.models.*
import com.soulo.app.utilities.AudioDSP
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID
import kotlin.math.*

object EmotionDetectionService {
    private val onnx = OnnxService()
    private const val NUM_MEL_BINS = 64
    private const val HOP_LENGTH = 160
    private const val WIN_LENGTH = 400
    private const val SAMPLE_RATE = 16000
    private const val MIN_FRAMES = 8

    // Mel filterbank (pre-computed for speed)
    private val melFilterbank: Array<FloatArray> by lazy { createMelFilterbank() }

    suspend fun detect(
        pcm: ShortArray,
        biomarkers: VoiceBiomarkers?
    ): EmotionalState = withContext(Dispatchers.Default) {
        if (onnx.isModelAvailable(OnnxModel.Emotion2Vec)) {
            try {
                onnx.loadModel(OnnxModel.Emotion2Vec)
                val mel = computeMelSpectrogram(pcm)
                if (mel.size >= MIN_FRAMES * NUM_MEL_BINS) {
                    val probs = onnx.runEmotion2vec(mel, mel.size / NUM_MEL_BINS)
                    if (probs != null && probs.isNotEmpty()) {
                        val decoded = onnx.decodeEmotion(probs)
                        val top = decoded.entries.first()
                        val emotionType = mapToEmotionType(top.key)
                        val confidence = top.value.coerceIn(0.0f, 1.0f).toDouble()
                        val valence = estimateValence(decoded, biomarkers)
                        val arousal = estimateArousal(decoded, biomarkers)
                        val secondary = decoded.entries.drop(1).take(3)
                            .map { mapToEmotionType(it.key) }
                            .filter { it != emotionType }

                        return@withContext EmotionalState(
                            id = UUID.randomUUID().toString(),
                            primaryEmotion = emotionType,
                            confidence = confidence,
                            valence = valence,
                            arousal = arousal,
                            secondaryEmotions = secondary,
                            detectedAt = System.currentTimeMillis() / 1000
                        )
                    }
                }
            } catch (_: Exception) {}
        }
        // Heuristic fallback
        heuristicDetect(biomarkers, pcm)
    }

    private fun heuristicDetect(biomarkers: VoiceBiomarkers?, pcm: ShortArray): EmotionalState {
        val b = biomarkers
        return if (b != null) {
            val (primary, valence, arousal) = when {
                b.vocalEnergy > 0.7 && b.speechRate > 4.0 ->
                    Triple(EmotionType.excitement, 0.7, 0.8)
                b.vocalEnergy < 0.3 && b.speechRate < 2.0 ->
                    Triple(EmotionType.sadness, -0.6, 0.3)
                b.pitchInstability > 0.4 && b.speechRate > 4.5 ->
                    Triple(EmotionType.anxiety, -0.4, 0.8)
                b.vocalEnergy > 0.6 && b.hesitationRate < 0.1 ->
                    Triple(EmotionType.joy, 0.7, 0.6)
                b.jitter > 0.3 && b.shimmer > 0.3 ->
                    Triple(EmotionType.frustration, -0.5, 0.7)
                b.speechRate < 1.5 && b.vocalEnergy < 0.2 ->
                    Triple(EmotionType.fatigue, -0.3, 0.2)
                else -> Triple(EmotionType.neutral, 0.0, 0.5)
            }
            EmotionalState(
                id = UUID.randomUUID().toString(),
                primaryEmotion = primary,
                confidence = 0.5,
                valence = valence,
                arousal = arousal,
                detectedAt = System.currentTimeMillis() / 1000
            )
        } else {
            EmotionalState(
                id = UUID.randomUUID().toString(),
                primaryEmotion = EmotionType.neutral,
                confidence = 0.3,
                valence = 0.0,
                arousal = 0.5,
                detectedAt = System.currentTimeMillis() / 1000
            )
        }
    }

    fun computeMelSpectrogram(pcm: ShortArray): FloatArray {
        val frames = (pcm.size - WIN_LENGTH) / HOP_LENGTH + 1
        if (frames < 1) return FloatArray(0)

        val mel = FloatArray(frames * NUM_MEL_BINS)
        val window = hannWindow(WIN_LENGTH)

        for (f in 0 until frames) {
            val offset = f * HOP_LENGTH
            // Apply window + FFT
            val spectrum = computeSpectrum(pcm, offset, window)
            // Mel binning
            for (m in 0 until NUM_MEL_BINS) {
                var sum = 0.0f
                val bin = melFilterbank[m]
                for (k in bin.indices) {
                    if (k < spectrum.size) sum += spectrum[k] * bin[k]
                }
                mel[f * NUM_MEL_BINS + m] = log10(max(sum, 1e-10f))
            }
        }
        return mel
    }

    private fun computeSpectrum(pcm: ShortArray, offset: Int, window: FloatArray): FloatArray {
        val n = window.size
        val real = FloatArray(n)
        val imag = FloatArray(n)

        for (i in 0 until n) {
            val idx = offset + i
            real[i] = if (idx < pcm.size) (pcm[idx].toFloat() / 32768f) * window[i] else 0f
            imag[i] = 0f
        }

        // Radix-2 FFT (in-place, Cooley-Tukey)
        val bits = (31 - Integer.numberOfLeadingZeros(n))
        for (i in 0 until n) {
            val j = Integer.reverse(i) ushr (32 - bits)
            if (j > i) {
                var tmp = real[i]; real[i] = real[j]; real[j] = tmp
                tmp = imag[i]; imag[i] = imag[j]; imag[j] = tmp
            }
        }

        var len = 2
        while (len <= n) {
            val halfLen = len shr 1
            val angleStep = -2.0 * PI / len
            for (i in 0 until n step len) {
                for (j in 0 until halfLen) {
                    val wRe = cos(angleStep * j).toFloat()
                    val wIm = sin(angleStep * j).toFloat()
                    val uRe = real[i + j]
                    val uIm = imag[i + j]
                    val vRe = real[i + j + halfLen] * wRe - imag[i + j + halfLen] * wIm
                    val vIm = real[i + j + halfLen] * wIm + imag[i + j + halfLen] * wRe
                    real[i + j] = uRe + vRe
                    imag[i + j] = uIm + vIm
                    real[i + j + halfLen] = uRe - vRe
                    imag[i + j + halfLen] = uIm - vIm
                }
            }
            len = len shl 1
        }

        // Power spectrum (magnitude squared)
        val halfN = n / 2
        return FloatArray(halfN) { real[it] * real[it] + imag[it] * imag[it] }
    }

    private fun hannWindow(size: Int): FloatArray {
        return FloatArray(size) { i ->
            (0.5 * (1.0 - cos(2.0 * PI * i / (size - 1)))).toFloat()
        }
    }

    private fun createMelFilterbank(): Array<FloatArray> {
        val nfft = WIN_LENGTH
        val halfN = nfft / 2
        val lowFreq = 80.0
        val highFreq = 7800.0
        val melLow = 2595.0 * log10(1.0 + lowFreq / 700.0)
        val melHigh = 2595.0 * log10(1.0 + highFreq / 700.0)
        val melPoints = DoubleArray(NUM_MEL_BINS + 2) {
            melLow + (melHigh - melLow) * it / (NUM_MEL_BINS + 1)
        }
        val freqPoints = melPoints.map { 700.0 * (10.0.pow(it / 2595.0) - 1.0) }
        val fftBins = freqPoints.map { it * halfN / (SAMPLE_RATE / 2.0) }

        val filterbank = Array(NUM_MEL_BINS) { FloatArray(halfN) }
        for (m in 0 until NUM_MEL_BINS) {
            val fLeft = fftBins[m]
            val fCenter = fftBins[m + 1]
            val fRight = fftBins[m + 2]
            for (k in 0 until halfN) {
                val weight = when {
                    k < fLeft || k > fRight -> 0.0
                    k <= fCenter -> (k - fLeft) / (fCenter - fLeft)
                    else -> (fRight - k) / (fRight - fCenter)
                }
                filterbank[m][k] = weight.toFloat()
            }
        }
        return filterbank
    }

    private fun mapToEmotionType(label: String): EmotionType {
        return when (label.lowercase().trim()) {
            "happy", "joy" -> EmotionType.joy
            "sad", "sadness" -> EmotionType.sadness
            "angry", "anger" -> EmotionType.anger
            "fearful", "fear", "anxious", "anxiety" -> EmotionType.anxiety
            "disgusted", "disgust" -> EmotionType.disgust
            "surprised", "surprise" -> EmotionType.surprise
            "frustrated", "frustration" -> EmotionType.frustration
            "fatigue", "tired", "fatigued" -> EmotionType.fatigue
            "excitement", "excited" -> EmotionType.excitement
            else -> EmotionType.neutral
        }
    }

    fun computeValence(ml: Map<String, Float>, bio: VoiceBiomarkers?): Double {
        return estimateValence(ml, bio)
    }

    fun computeArousal(ml: Map<String, Float>, bio: VoiceBiomarkers?): Double {
        return estimateArousal(ml, bio)
    }

    private fun estimateValence(ml: Map<String, Float>, bio: VoiceBiomarkers?): Double {
        val mlValence = ml.entries.sumOf { (label, prob) ->
            val v = when (label) {
                "happy", "surprised" -> 0.7; "sad", "fearful" -> -0.6
                "angry", "disgusted" -> -0.5; "neutral" -> 0.0; else -> 0.0
            }
            (v * prob).toDouble()
        }
        val bioValence = when {
            bio == null -> 0.0
            bio.vocalEnergy > 0.6 && bio.speechRate > 3.5 -> 0.3
            bio.vocalEnergy < 0.3 && bio.speechRate < 2.0 -> -0.3
            else -> 0.0
        }
        return (mlValence + bioValence).coerceIn(-1.0, 1.0)
    }

    private fun estimateArousal(ml: Map<String, Float>, bio: VoiceBiomarkers?): Double {
        val mlArousal = ml.entries.sumOf { (label, prob) ->
            val a = when (label) {
                "happy", "angry", "fearful", "surprised" -> 0.7
                "sad", "disgusted" -> 0.3; "neutral" -> 0.5; else -> 0.5
            }
            (a * prob).toDouble()
        }
        val bioArousal = when {
            bio == null -> 0.0
            bio.speechRate > 4.0 -> 0.2
            bio.speechRate < 2.0 -> -0.2
            else -> 0.0
        }
        return (mlArousal + bioArousal).coerceIn(0.0, 1.0)
    }
}
