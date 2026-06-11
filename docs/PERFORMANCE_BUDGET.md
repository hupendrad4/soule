# Soulo — Performance Budget

## 1. Memory Budget

```
Total device RAM: 4GB (iPhone 12 minimum) / 6GB+ (recommended)
Soulo budget: 400MB max (other apps need room)
```

| Component | Memory | When | Notes |
|---|---|---|---|
| App + SwiftUI | ~30MB | Always | Baseline |
| SQLCipher DB | ~10-50MB | Always | Grows with entry count |
| Whisper.cpp model | ~200MB | During transcription | Released after use |
| Whisper inference | ~150MB additional | During transcription | Processing buffer |
| Phi-3-mini model | ~1.5GB | During topic extraction | Largest consumer |
| Phi-3-mini inference | ~800MB additional | During extraction | KV cache |
| emotion2vec model | ~50MB | During emotion detection | |
| emotion2vec inference | ~100MB additional | During detection | |
| Audio buffer | ~5MB | During recording | 3 min @ 16kHz 16-bit |
| FFT processing | ~20MB | During biomarker extraction | |
| Pattern engine | ~10MB | During scan | |

**Strategy:**
- Load models one at a time, unload after use
- Phi-3-mini is the bottleneck — it determines minimum device requirement
- Fallback to server-side extraction for devices with <4GB RAM

### Out-of-Memory Recovery

```swift
class MemoryManager {
    static let warningThreshold: Float = 0.75  // 75% of device RAM
    static let criticalThreshold: Float = 0.9   // 90% of device RAM
    
    func checkMemory() -> MemoryStatus {
        let used = getAppMemoryUsage()
        let total = ProcessInfo.processInfo.physicalMemory
        
        switch Float(used) / Float(total) {
        case criticalThreshold...:
            MemoryManager.shared.clearModelCaches()
            ProcessingQueue.shared.pause()
            notifyUserLowMemory()
            return .critical
        case warningThreshold...:
            MemoryManager.shared.clearModelCaches()
            return .warning
        default:
            return .normal
        }
    }
    
    func clearModelCaches() {
        WhisperModel.shared.unload()
        Phi3Model.shared.unload()
        EmotionModel.shared.unload()
    }
}
```

## 2. Battery Budget

```
Target: <5% battery drain per day (3 min recording + processing)
```

| Operation | Drain | Frequency |
|---|---|---|
| Recording (3 min) | ~0.5% | 1x/day |
| Whisper transcription | ~0.8% | 1x/day |
| Phi-3 topic extraction | ~1.5% | 1x/day |
| Biomarker DSP | ~0.2% | 1x/day |
| emotion2vec | ~0.3% | 1x/day |
| Pattern scan | ~0.5% | 1x/day |
| Daily notification | ~0.1% | 1x/day |
| **Total** | **~3.9%/day** | |

**Strategy:**
- Process recording immediately (warm cache)
- Run AI models only when battery >30% AND charging
- Defer batch processing to charging state
- Use iOS BackgroundTasks API for idle processing

```swift
func scheduleProcessing() {
    let batteryState = UIDevice.current.batteryState
    let batteryLevel = UIDevice.current.batteryLevel
    
    guard batteryLevel > 0.3 || batteryState == .charging else {
        // Defer until charging
        scheduleBackgroundProcessing()
        return
    }
    
    processNextEntry()
}
```

## 3. Storage Budget

```
Target first year: <500MB total (audio + database)
Entry estimate: ~1.5MB per entry (3 min audio + metadata)
Year 1 at 365 entries: ~550MB
```

| Component | Size per Unit | Notes |
|---|---|---|
| Audio (AAC, 3 min) | ~1.2MB | Compressed, encrypted |
| Transcript | ~5KB | Plain text |
| Biomarkers | ~0.5KB | JSON |
| Topics | ~0.5KB | JSON |
| Indexes | ~0.1KB | |
| **Total per entry** | **~1.2MB** | |

**Strategy:**
- Compress audio to AAC (not WAV) — 90% size reduction
- Delete raw audio after analysis completed (optional: keep only if user chooses)
- Show storage usage in Settings
- Auto-delete oldest entries when storage exceeds 80% of budget (with user consent)

```swift
enum StoragePolicy {
    case keepAll
    case keepAudio(days: Int)      // Delete audio after N days, keep text
    case keepTextOnly              // Delete audio immediately after transcription
    case autoManage                // Keep last 90 days of audio
    
    static let recommended = StoragePolicy.keepAudio(days: 30)
}
```

## 4. Launch Time Budget

| Phase | Budget | Measurement |
|---|---|---|
| Cold start → interactive | <2s | From tap to first frame |
| Warm start → interactive | <0.5s | App in memory |
| Recording start | <0.3s | Tap → waveform visible |
| Recording stop → processing visible | <0.5s | |
| Transcription complete | <15s | For 3-min audio |
| Full analysis complete | <30s | Transcript + biomarkers + topics |

## 5. Network Budget

| Operation | Data | Frequency |
|---|---|---|
| Model download (Phi-3-mini) | 2.3GB | Once (first launch, Wi-Fi only) |
| Model download (Whisper) | 77MB | Once (first launch) |
| Model download (emotion2vec) | 50MB | Once (first launch) |
| iCloud backup | ~5MB/week | Weekly (opt-in, Wi-Fi) |
| Subscription validation | ~10KB | Monthly |
| **Total first month** | **~2.5GB** | |
| **Total ongoing** | **~20MB/month** | |

## 6. Performance Regressions

Test before every release:

```bash
#!/bin/bash
# Performance regression test

echo "=== Cold launch ==="
# Time from tap to first view
xcrun xctrace run --template "Time Profiler" --device "$DEVICE" --app "com.voiceself.app"
# Expect: <2s

echo "=== Recording latency ==="
# Time from tap to waveform visible
# Expect: <300ms

echo "=== Transcription speed ==="
# Process 3-min test audio
# Expect: <15s on iPhone 14+

echo "=== Memory peak ==="
# Record + transcribe + analyze
# Expect: <400MB peak

echo "=== Battery impact ==="
# Run full cycle 10 times, measure battery %
# Expect: <5% per cycle
```

## 7. Device Support Matrix

| Device | RAM | ANE | Whisper | Phi-3 | emotion2vec | Recommendation |
|---|---|---|---|---|---|---|
| iPhone 12 | 4GB | A14 | ✅ | ✅ (slow) | ✅ | Supported |
| iPhone 13 | 4GB | A15 | ✅ | ✅ (slow) | ✅ | Supported |
| iPhone 14 | 6GB | A16 | ✅ | ✅ | ✅ | Recommended |
| iPhone 15 | 6-8GB | A17 | ✅ | ✅ | ✅ | Recommended |
| iPhone 16 | 8GB | A18 | ✅ | ✅ | ✅ | Optimal |
| iPhone SE (3rd) | 4GB | A15 | ✅ | ⚠️ (fallback) | ✅ | Supported with fallback |
| iPad (M1+) | 8GB+ | M1+ | ✅ | ✅ | ✅ | Supported |
| iPad (A14-) | 3-4GB | — | ✅ | ❌ | ✅ | Recording only |
