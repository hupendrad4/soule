import Foundation
import Accelerate

enum AudioDSP {
    static let sampleRate: Float = 16000
    static let fftSize = 1024
    static let hopLength = 512
    static let frameLength = 256
    static let energyThreshold: Float = 0.015

    // MARK: - Preprocessing

    static func normalize(_ samples: inout [Float]) {
        guard let peak = samples.max(), peak > 0 else { return }
        let scale = 1.0 / peak
        vDSP_vsmul(samples, 1, [scale], &samples, 1, vDSP_Length(samples.count))
    }

    static func trimSilence(_ samples: [Float]) -> [Float] {
        let frameLen = frameLength
        let threshold: Float = 0.008
        var startFrame = 0
        var endFrame = samples.count / frameLen

        for i in 0..<endFrame {
            let start = i * frameLen
            let frame = Array(samples[start..<min(start + frameLen, samples.count)])
            let rms = sqrt(frame.map { $0 * $0 }.reduce(0, +) / Float(frame.count))
            if rms > threshold { startFrame = i; break }
        }

        for i in (0..<endFrame).reversed() {
            let start = i * frameLen
            let frame = Array(samples[start..<min(start + frameLen, samples.count)])
            let rms = sqrt(frame.map { $0 * $0 }.reduce(0, +) / Float(frame.count))
            if rms > threshold { endFrame = i + 1; break }
        }

        let start = max(0, startFrame * frameLen - frameLen / 2)
        let end = min(samples.count, endFrame * frameLen + frameLen / 2)
        return Array(samples[start..<end])
    }

    static func splitIntoFrames(_ samples: [Float], frameLen: Int = fftSize, hop: Int = hopLength) -> [[Float]] {
        var frames: [[Float]] = []
        var start = 0
        while start + frameLen <= samples.count {
            frames.append(Array(samples[start..<start + frameLen]))
            start += hop
        }
        return frames
    }

    // MARK: - Main Extraction

    static func extractBiomarkers(from samples: [Float]) -> VoiceBiomarkers {
        var normalized = samples
        normalize(&normalized)
        let trimmed = trimSilence(normalized)
        guard trimmed.count > fftSize else {
            return VoiceBiomarkers(speechRate: 0, hesitationRate: 0, vocalEnergy: 0, pitchInstability: 0, microBreathCount: 0, jitter: 0, shimmer: 0)
        }

        let energy = computeRMS(trimmed)
        let pitchData = extractPitch(trimmed)
        let silenceData = detectSilences(trimmed)
        let rate = estimateSpeechRate(trimmed)
        let breaths = detectMicroBreaths(trimmed)

        return VoiceBiomarkers(
            speechRate: rate,
            hesitationRate: silenceData.ratio,
            vocalEnergy: Double(energy),
            pitchInstability: pitchData.instability,
            microBreathCount: breaths,
            jitter: pitchData.jitter,
            shimmer: pitchData.shimmer
        )
    }

    // MARK: - Vocal Energy

    static func computeRMS(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    static func frameEnergies(_ samples: [Float], frameLen: Int = frameLength) -> [Float] {
        var energies: [Float] = []
        for start in stride(from: 0, to: samples.count - frameLen, by: frameLen) {
            let frame = Array(samples[start..<start + frameLen])
            let energy = sqrt(frame.map { $0 * $0 }.reduce(0, +) / Float(frameLen))
            energies.append(energy)
        }
        return energies
    }

    // MARK: - Pitch Tracking (Autocorrelation + FFT hybrid)

    static func extractPitch(_ samples: [Float]) -> (instability: Double, jitter: Double, shimmer: Double) {
        let frames = splitIntoFrames(samples, frameLen: fftSize, hop: hopLength)
        guard frames.count > 2 else { return (0, 0, 0) }

        var pitches: [Float] = []
        var peakMags: [Float] = []

        let minFreq: Float = 60
        let maxFreq: Float = 450
        let minLag = Int(sampleRate / maxFreq)
        let maxLag = Int(sampleRate / minFreq)

        let halfFFT = fftSize / 2
        var fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFTDirection.FORWARD)

        for frame in frames.prefix(300) {
            // FFT-based spectral pitch
            var real = frame
            var imag = [Float](repeating: 0, count: fftSize)

            if let setup = fftSetup {
                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        vDSP_DFT_Execute(setup, rp.baseAddress!, ip.baseAddress!, rp.baseAddress!, ip.baseAddress!)
                    }
                }
            }

            var mags = [Float](repeating: 0, count: halfFFT)
            vDSP_ztoc(real, 2, imag, 2, &mags, 1, vDSP_Length(halfFFT))

            let fftPitch: Float? = {
                let peakIdx = mags.enumerated().dropFirst().max { $0.element < $1.element }?.offset ?? 0
                let freq = Float(peakIdx) * sampleRate / Float(fftSize)
                guard freq > minFreq && freq < maxFreq, mags[peakIdx] > 0.03 else { return nil }
                return freq
            }()

            var finalPitch: Float = 0
            var finalMag: Float = 0

            // Autocorrelation refinement
            var corr = [Float](repeating: 0, count: maxLag - minLag + 1)
            vDSP_conv(frame, 1, frame, 1, &corr, 1, vDSP_Length(corr.count), vDSP_Length(frame.count))
            let corrPeakIdx = corr.enumerated().dropFirst().max { $0.element < $1.element }?.offset ?? 0
            let corrLag = minLag + corrPeakIdx
            let corrFreq = corrLag > 0 ? sampleRate / Float(corrLag) : 0
            let corrMag = corrPeakIdx < corr.count ? corr[corrPeakIdx] : 0

            if corrFreq > minFreq && corrFreq < maxFreq && corrMag > 0.1 {
                finalPitch = corrFreq
                finalMag = corrMag
            } else if let fp = fftPitch {
                finalPitch = fp
                finalMag = mags.first { $0 > 0 } ?? 0
            }

            if finalPitch > 0 && finalMag > 0 {
                pitches.append(finalPitch)
                peakMags.append(finalMag)
            }
        }

        if let setup = fftSetup { vDSP_DFT_DestroySetup(setup) }
        guard pitches.count > 2 else { return (0, 0, 0) }

        let mean = pitches.reduce(0, +) / Float(pitches.count)
        let variance = pitches.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(pitches.count)

        let deltas = pitches.enumerated().dropFirst().map { abs($0.element - pitches[$0.offset - 1]) }
        let instability = deltas.reduce(0, +) / Float(deltas.count)

        let jitter = deltas.enumerated().map { $0.element / max(pitches[$0.offset], 0.001) }.reduce(0, +) / Float(deltas.count)

        let shimmer: Float = {
            guard peakMags.count > 2 else { return 0 }
            let deltas = peakMags.enumerated().dropFirst().map { abs($0.element - peakMags[$0.offset - 1]) / max(peakMags[$0.offset - 1], 0.001) }
            return deltas.reduce(0, +) / Float(deltas.count)
        }()

        return (Double(instability), Double(jitter), Double(shimmer))
    }

    // MARK: - Silence & Hesitation

    static func detectSilences(_ samples: [Float]) -> (ratio: Double, count: Int, totalDuration: Double) {
        let energies = frameEnergies(samples)
        let threshold: Float = 0.012

        var silentFrames = 0
        var currentSilence = false
        var silenceSegments = 0

        for energy in energies {
            if energy < threshold {
                silentFrames += 1
                if !currentSilence { silenceSegments += 1; currentSilence = true }
            } else {
                currentSilence = false
            }
        }

        let ratio = energies.isEmpty ? 0 : Double(silentFrames) / Double(energies.count)
        let totalDuration = Double(silentFrames * frameLength) / Double(sampleRate)
        return (ratio, silenceSegments, totalDuration)
    }

    static func detectHesitations(_ samples: [Float]) -> [(start: TimeInterval, duration: TimeInterval)] {
        let energies = frameEnergies(samples)
        let threshold: Float = 0.008
        let minHesitationFrames = 5

        var hesitations: [(TimeInterval, TimeInterval)] = []
        var startFrame: Int?

        for (i, energy) in energies.enumerated() {
            if energy < threshold {
                if startFrame == nil { startFrame = i }
            } else {
                if let s = startFrame {
                    let frameCount = i - s
                    if frameCount >= minHesitationFrames {
                        let startTime = TimeInterval(s * frameLength) / TimeInterval(sampleRate)
                        let duration = TimeInterval(frameCount * frameLength) / TimeInterval(sampleRate)
                        hesitations.append((startTime, duration))
                    }
                }
                startFrame = nil
            }
        }

        if let s = startFrame {
            let frameCount = energies.count - s
            if frameCount >= minHesitationFrames {
                let startTime = TimeInterval(s * frameLength) / TimeInterval(sampleRate)
                let duration = TimeInterval(frameCount * frameLength) / TimeInterval(sampleRate)
                hesitations.append((startTime, duration))
            }
        }

        return hesitations
    }

    // MARK: - Speech Rate

    static func estimateSpeechRate(_ samples: [Float]) -> Double {
        let energies = frameEnergies(samples)
        let threshold: Float = 0.015
        let voicedFrames = energies.filter { $0 > threshold }.count
        let duration = Double(samples.count) / Double(sampleRate)
        guard duration > 0.5 else { return 0 }

        let voicedRatio = Double(voicedFrames) / Double(max(energies.count, 1))
        let rate = voicedRatio * 4.5
        return min(max(rate, 0.5), 7.0)
    }

    // MARK: - Energy Profile (for charts)

    static func energyProfile(_ samples: [Float], numBins: Int = 50) -> [Float] {
        let energies = frameEnergies(samples)
        guard !energies.isEmpty else { return [] }
        let binSize = max(1, energies.count / numBins)
        var profile: [Float] = []
        for i in stride(from: 0, to: energies.count, by: binSize) {
            let end = min(i + binSize, energies.count)
            let avg = energies[i..<end].reduce(0, +) / Float(end - i)
            profile.append(avg)
        }
        return profile
    }

    // MARK: - Micro-Breath Detection

    static func detectMicroBreaths(_ samples: [Float]) -> Int {
        let frames = splitIntoFrames(samples, frameLen: 512, hop: 256)
        let breathFreqRange: ClosedRange<Float> = 200...800
        let halfLen = 256
        var breathFrames = 0

        var fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(512), vDSP_DFTDirection.FORWARD)

        for frame in frames {
            guard frame.count == 512 else { continue }
            var real = frame
            var imag = [Float](repeating: 0, count: 512)

            if let setup = fftSetup {
                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        vDSP_DFT_Execute(setup, rp.baseAddress!, ip.baseAddress!, rp.baseAddress!, ip.baseAddress!)
                    }
                }
            }

            var mags = [Float](repeating: 0, count: halfLen)
            vDSP_ztoc(real, 2, imag, 2, &mags, 1, vDSP_Length(halfLen))

            let breathEnergy = mags.enumerated()
                .filter { idx, _ in
                    let freq = Float(idx) * sampleRate / 512
                    return breathFreqRange.contains(freq)
                }
                .map { $0.element }
                .reduce(0, +)

            if breathEnergy > 0.4 { breathFrames += 1 }
        }

        if let setup = fftSetup { vDSP_DFT_DestroySetup(setup) }
        return breathFrames / 3
    }
}
