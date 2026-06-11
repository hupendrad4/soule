package com.soulo.app.utilities

import kotlin.math.*

object AudioDSP {
    private const val SAMPLE_RATE = 16000
    private const val MIN_PITCH = 60.0
    private const val MAX_PITCH = 450.0
    private const val SILENCE_THRESHOLD = 0.02
    private const val MIN_SILENCE_MS = 200
    private const val MIN_VOICED_FRAMES = 3
    private const val BREATH_LOW = 200.0
    private const val BREATH_HIGH = 800.0

    data class BiomarkerResult(
        val speechRate: Double,
        val vocalEnergy: Double,
        val pitchInstability: Double,
        val hesitationRate: Double,
        val microBreathCount: Int,
        val jitter: Double,
        val shimmer: Double
    )

    fun compute(pcm: ShortArray): BiomarkerResult {
        val normalized = normalize(pcm)
        val frames = splitFrames(normalized, 512, 256) // 32ms frames, 16ms hop

        val voiced = mutableListOf<FloatArray>()
        val silenceFrames = mutableListOf<FloatArray>()
        val pitches = mutableListOf<Double>()
        val energies = mutableListOf<Double>()

        for (frame in frames) {
            val energy = computeEnergy(frame)
            energies.add(energy)
            if (energy < SILENCE_THRESHOLD) {
                silenceFrames.add(frame)
            } else {
                voiced.add(frame)
                val pitch = detectPitch(frame)
                if (pitch != null) pitches.add(pitch)
            }
        }

        val totalVoiced = voiced.size.toDouble()
        val totalFrames = frames.size.toDouble()

        // Speech rate: voiced ratio heuristic
        val speechRate = (totalVoiced / totalFrames) * 4.0 // scale to ~wps

        // Vocal energy: RMS of all voiced frames
        val vocalEnergy = if (voiced.isNotEmpty()) {
            sqrt(voiced.sumOf { frame ->
                frame.sumOf { (it.toDouble() * it.toDouble()) } / frame.size
            } / voiced.size)
        } else 0.0

        // Pitch instability: coefficient of variation
        val pitchInstability = if (pitches.size >= MIN_VOICED_FRAMES) {
            val mean = pitches.average()
            if (mean > 0) {
                val variance = pitches.map { (it - mean) * (it - mean) }.average()
                sqrt(variance) / mean
            } else 0.0
        } else 0.0

        // Hesitation rate: proportion of silence
        val hesitationRate = totalFrames.let { if (it > 0) silenceFrames.size / it else 0.0 }

        // Micro-breaths: detect energy dips in 200-800Hz band
        val microBreathCount = detectMicroBreaths(frames)

        // Jitter: pitch period variability
        val jitter = if (pitches.size >= 3) {
            val periods = pitches.map { SAMPLE_RATE / it }
            val diffs = periods.zipWithNext().map { abs(it.first - it.second) }
            val meanPeriod = periods.average()
            if (meanPeriod > 0) diffs.average() / meanPeriod else 0.0
        } else 0.0

        // Shimmer: amplitude variability
        val shimmer = if (energies.size >= 3) {
            val diffs = energies.zipWithNext().map { abs(it.first - it.second) }
            val meanEnergy = energies.average()
            if (meanEnergy > 0) diffs.average() / meanEnergy else 0.0
        } else 0.0

        return BiomarkerResult(
            speechRate = speechRate.coerceIn(0.0, 10.0),
            vocalEnergy = vocalEnergy.coerceIn(0.0, 1.0),
            pitchInstability = pitchInstability.coerceIn(0.0, 1.0),
            hesitationRate = hesitationRate.coerceIn(0.0, 1.0),
            microBreathCount = microBreathCount,
            jitter = jitter.coerceIn(0.0, 1.0),
            shimmer = shimmer.coerceIn(0.0, 1.0)
        )
    }

    fun normalize(pcm: ShortArray): FloatArray {
        val max = pcm.maxOf { abs(it.toInt()) }.coerceAtLeast(1)
        val scale = 1.0f / max
        return FloatArray(pcm.size) { pcm[it] * scale }
    }

    fun splitFrames(signal: FloatArray, frameSize: Int, hopSize: Int): List<FloatArray> {
        val frames = mutableListOf<FloatArray>()
        var start = 0
        while (start + frameSize <= signal.size) {
            frames.add(signal.sliceArray(start until start + frameSize))
            start += hopSize
        }
        return frames
    }

    fun computeEnergy(frame: FloatArray): Double {
        return sqrt(frame.sumOf { (it * it).toDouble() } / frame.size)
    }

    fun detectPitch(frame: FloatArray): Double? {
        val n = nextPowerOf2(frame.size)
        val spectrum = FloatArray(n * 2) // real + imag interleaved
        for (i in frame.indices) spectrum[i * 2] = frame[i]

        // Simple FFT
        fft(spectrum, n, false)

        val minIdx = (SAMPLE_RATE.toDouble() / MAX_PITCH).toInt().coerceIn(1, n / 2)
        val maxIdx = (SAMPLE_RATE.toDouble() / MIN_PITCH).toInt().coerceIn(1, n / 2)

        // Autocorrelation via IFFT of power spectrum
        for (i in 0 until n) {
            val real = spectrum[i * 2]
            val imag = spectrum[i * 2 + 1]
            spectrum[i * 2] = real * real + imag * imag // power
            spectrum[i * 2 + 1] = 0.0f
        }
        fft(spectrum, n, true)

        // Find peak in autocorrelation
        var maxVal = 0.0
        var maxLag = 0
        for (i in minIdx..maxIdx) {
            val v = abs(spectrum[i * 2].toDouble())
            if (v > maxVal) {
                maxVal = v
                maxLag = i
            }
        }
        if (maxLag == 0) return null

        // Parabolic interpolation for accuracy
        val y1 = abs(spectrum[(maxLag - 1).coerceAtLeast(0) * 2].toDouble())
        val y2 = maxVal
        val y3 = abs(spectrum[(maxLag + 1).coerceAtMost(n / 2) * 2].toDouble())
        val denom = y1 - 2 * y2 + y3
        if (abs(denom) < 1e-10) return null
        val correction = 0.5 * (y1 - y3) / denom
        val refinedLag = maxLag + correction
        if (refinedLag <= 0) return null
        return SAMPLE_RATE.toDouble() / refinedLag
    }

    fun detectMicroBreaths(frames: List<FloatArray>): Int {
        if (frames.size < 5) return 0
        var breathCount = 0
        val windowSize = 5
        for (i in windowSize until frames.size - windowSize) {
            val localEnergy = (0 until windowSize).map {
                computeEnergy(frames[i + it])
            }
            val localMin = localEnergy.minOrNull() ?: continue
            val localMax = localEnergy.maxOrNull() ?: continue
            val prevAvg = (0 until windowSize).map {
                val idx = i - windowSize + it
                if (idx >= 0) computeEnergy(frames[idx]) else 0.0
            }.average()

            // Breath: sudden dip then recovery
            if (localMin < prevAvg * 0.5 && localMax > localMin * 2.0) {
                // Verify band energy in 200-800Hz
                val bandEnergy = computeBandEnergy(frames[i], BREATH_LOW, BREATH_HIGH)
                if (bandEnergy > 0.01) breathCount++
            }
        }
        return breathCount
    }

    private fun computeBandEnergy(frame: FloatArray, lowHz: Double, highHz: Double): Double {
        val n = nextPowerOf2(frame.size)
        val spectrum = FloatArray(n * 2)
        for (i in frame.indices) spectrum[i * 2] = frame[i]
        fft(spectrum, n, false)

        val lowBin = (lowHz * n / SAMPLE_RATE).toInt().coerceIn(0, n / 2)
        val highBin = (highHz * n / SAMPLE_RATE).toInt().coerceIn(0, n / 2)
        var energy = 0.0
        for (i in lowBin..highBin) {
            val real = spectrum[i * 2].toDouble()
            val imag = spectrum[i * 2 + 1].toDouble()
            energy += real * real + imag * imag
        }
        return energy / frame.size
    }

    // Cooley-Tukey radix-2 FFT in-place
    private fun fft(data: FloatArray, n: Int, inverse: Boolean) {
        var i = 0
        for (j in 1 until n) {
            var bit = n shr 1
            while (bit and i != 0) {
                i = i xor bit
                bit = bit shr 1
            }
            i = i xor bit
            if (j < i) {
                // Swap real
                val tmpR = data[j * 2]
                data[j * 2] = data[i * 2]
                data[i * 2] = tmpR
                // Swap imag
                val tmpI = data[j * 2 + 1]
                data[j * 2 + 1] = data[i * 2 + 1]
                data[i * 2 + 1] = tmpI
            }
        }

        var len = 2
        while (len <= n) {
            val halfLen = len / 2
            val angle = if (inverse) PI / halfLen else -PI / halfLen
            val wReal = cos(angle)
            val wImag = sin(angle)

            for (k in 0 until n step len) {
                var wr = 1.0
                var wi = 0.0
                for (j in 0 until halfLen) {
                    val idx1 = (k + j) * 2
                    val idx2 = (k + j + halfLen) * 2
                    val tr = wr * data[idx2] - wi * data[idx2 + 1]
                    val ti = wr * data[idx2 + 1] + wi * data[idx2]
                    data[idx2] = data[idx1] - tr.toFloat()
                    data[idx2 + 1] = data[idx1 + 1] - ti.toFloat()
                    data[idx1] = (data[idx1] + tr).toFloat()
                    data[idx1 + 1] = (data[idx1 + 1] + ti).toFloat()
                    val t = wr * wReal - wi * wImag
                    wi = wr * wImag + wi * wReal
                    wr = t
                }
            }
            len *= 2
        }

        if (inverse) {
            for (i in 0 until n * 2) data[i] /= n
        }
    }

    fun nextPowerOf2(n: Int): Int {
        var v = n
        v--
        v = v or (v shr 1)
        v = v or (v shr 2)
        v = v or (v shr 4)
        v = v or (v shr 8)
        v = v or (v shr 16)
        return v + 1
    }
}
