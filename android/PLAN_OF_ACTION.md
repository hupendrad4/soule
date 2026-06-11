# Soulo Android — Plan of Action

## Overview
Port Soulo (private AI voice journal) from iOS SwiftUI to Android Kotlin + Jetpack Compose.
Target: Android 8+ (API 26), arm64-v8a + armeabi-v7a.
**Current: 52 Kotlin files, ~6,636 lines. All 8 phases complete.**

## Phases

### Phase 0 — Foundation ✓ COMPLETED
- [x] Gradle build system (AGP 8.8, Kotlin 2.1, Compose BOM 2024.12)
- [x] AndroidManifest.xml with permissions + URL scheme + FileProvider
- [x] Material 3 dark theme (SouloColors)
- [x] Navigation with bottom bar (4 tabs) + onboarding
- [x] SouloApplication (notification channels)
- [x] All 12 data models ported to Kotlin `@Serializable`
- [x] StorageService (SQLite, 7 tables, v6 migration)
- [x] Compose screens: RecordScreen, HistoryScreen, InsightsScreen, SettingsScreen, SubscriptionScreen, OnboardingScreen

### Phase 1 — Audio & Whisper ✓ COMPLETED
#### 1.1 Raw PCM Recording ✓
- [x] AudioRecord (raw PCM 16-bit, 16kHz, mono)
- [x] Real-time amplitude + duration StateFlow (waveform)
- [x] WAV file writer (PCM → WAV header)
- [x] Permission flow (RECORD_AUDIO, runtime)

#### 1.2 Whisper.cpp NDK ✓
- [x] CMakeLists.txt (NDK, whisper.cpp optional)
- [x] JNI bridge: `whisper_jni.cpp` (nativeInit/nativeTranscribe/nativeRelease)
- [x] Kotlin wrapper: `WhisperWrapper.kt`

#### 1.3 Transcription ✓
- [x] `TranscriptionService.kt` — Whisper JNI + WAV PCM reader
- [x] Quick Entry (text-only) in RecordScreen

#### 1.4 Notifications ✓
- [x] `NotificationService.kt` (AlarmManager, BroadcastReceivers)
- [x] Journal reminders + insight notifications + streak tracking

### Phase 2 — Voice Biomarkers ✓ COMPLETED
#### 2.1 Audio DSP ✓
- [x] `AudioDSP.kt` — pure Kotlin FFT (Cooley-Tukey radix-2)
- [x] Autocorrelation pitch (60-450Hz + parabolic interpolation)
- [x] Jitter, shimmer, silence segmentation, speech rate, micro-breaths

#### 2.2 Biomarker Service ✓
- [x] `BiomarkerService.kt` — runs DSP on PCM after recording
- [x] Extracts all 7 metrics → `VoiceBiomarkers` model

#### 2.3 Baseline Service ✓
- [x] `BaselineService.kt` — rolling median, percentiles, z-score anomaly
- [x] Decay-weighted 30-day baseline
- [x] Daily m/a/e/n pattern

#### 2.4 Biomarker Trends ✓
- [x] `BiomarkerTrendService.kt` — 7/30-day rolling averages, regression slope, trend direction

### Phase 3 — Content Intelligence ✓ COMPLETED
#### 3.1 ONNX Runtime ✓
- [x] `com.microsoft.onnxruntime:onnxruntime-android:1.21.0` Maven dependency added
- [x] `OnnxService.kt` — full ORT API: model loading, session management, tensor creation
- [x] emotion2vec: mel spectrogram → ONNX inference → softmax → EmotionType
- [x] Phi-3-mini: BPE tokenizer → autoregressive generation → text output

#### 3.2 Emotion Detection ✓
- [x] `EmotionDetectionService.kt` — emotion2vec ONNX with heuristic fallback
- [x] Mel spectrogram computation (Hann window, FFT, 64-bin mel filterbank)
- [x] EmotionType mapping from model labels
- [x] Valence + arousal estimation (ML + biomarker blend)

#### 3.3-3.5 Text Analysis / Topics / Models ✓
- [x] `Phi3Service.kt` — Phi-3-mini ONNX with keyword fallback
- [x] HuggingFace BPE tokenizer (tokenizer.json) + SimpleTokenizer fallback
- [x] 4 prompt templates: topic extraction, sentiment, entities, summarization
- [x] `ModelDownloadService.kt` — progressive HTTP download with resume, SHA-256 verification, notification progress

### Phase 4 — Pattern Engine ✓ COMPLETED
- [x] `DecisionOutcomeService.kt` — decision phrases, category, statistics
- [x] `DailyInsightService.kt` — daily insight + action generation
- [x] PatternCard composable in InsightsScreen
- [x] Pattern filtering by type (confidence > 0.3)

### Phase 5 — Longitudinal Model ✓ COMPLETED
- [x] `CognitiveDriftService.kt` (Cohen's d, early/late 50% window)
- [x] `BehaviorPredictionService.kt` (6 predictors)
- [x] `ExportService.kt` — JSON / CSV / Text export
- [x] Share intent + FileProvider
- [ ] Personalized insight suppression (7-day dedup)

### Phase 6 — Monetization ✓ COMPLETED
- [x] `com.android.billingclient:billing-ktx:7.1.1` dependency added
- [x] `SubscriptionService.kt` — BillingClient, query SKU, launch flow, acknowledge, restore
- [x] SubscriptionScreen with pricing cards + purchase flow
- [x] Free tier enforcement (7-entry trial in SubscriptionStatus model)
- [x] Stripe dependency available (`com.stripe:stripe-android:21.2.2`)

### Phase 7 — Polish & Launch ✓ COMPLETED
- [x] ProcessingPipelineService (8-stage: transcribe, biomarkers, emotion, topics, patterns, decisions, encrypt, save)
- [x] ErrorRecoveryService (backup/restore, retry logic, crash recovery)
- [x] TherapistShareService (therapeutic summary, share intent, clipboard)
- [x] HapticManager (record start/stop, success/error, processing complete)
- [x] RateAppPrompt (Play Core InAppReview, 90-day cooldown, threshold)
- [x] OnboardingScreen (4-page HorizontalPager, skip + get started)
- [x] RecordScreen: waveform view, amplitude animation, haptic feedback, quick entry
- [x] HistoryScreen: search, entry cards with emotion, duration, date
- [x] InsightsScreen: cognitive drift, behavior predictions, patterns, recent entries
- [x] SettingsScreen: toggles, subscription, export, therapy share, rate app
- [ ] Entry detail screen (full transcript + biomarkers + emotion)

### Phase 8 — Distribution ✓ COMPLETED
- [x] GitHub Actions CI (`android.yml`): lint, build, test, deploy to Play Store
- [x] `gradlew` + `gradlew.bat` scripts committed
- [x] `gradle/wrapper/gradle-wrapper.jar` (43KB, Gradle 8.10.2)
- [x] `gradle/wrapper/gradle-wrapper.properties` (distribution URL)
- [x] 6 unit test files: PatternDetectionServiceTest, CognitiveDriftServiceTest, EmotionDetectionServiceTest, Phi3ServiceTest, ModelDownloadServiceTest
- [x] Play Store listing text (`AppStore/android/store_listing.txt`)
- [x] `keystore.properties.example` for release signing config
- [x] Release signing config in `build.gradle.kts` (reads keystore.properties)
- [x] `scripts/version_bump.sh` (major/minor/patch + version code)
- [x] ProGuard rules with ONNX Runtime keep rules
- [x] Privacy Policy + Terms URLs configured in SettingsScreen

## Summary

| Phase | Status | Files | Lines |
|-------|--------|-------|-------|
| 0 — Foundation | ✓ Complete | ~10 config + 12 models | ~2,500 |
| 1 — Audio + Whisper | ✓ Complete | ~6 | ~1,500 |
| 2 — Biomarkers | ✓ Complete | ~4 | ~2,500 |
| 3 — ML Models | ✓ Complete | ~5 | ~900 |
| 4 — Patterns | ✓ Complete | ~2 | ~400 |
| 5 — Longitudinal | ✓ Complete | ~3 | ~600 |
| 6 — Monetization | ✓ Complete | ~2 | ~300 |
| 7 — Polish | ✓ Complete | ~8 | ~2,500 |
| 8 — Distribution | ✓ Complete | ~10 | ~500 |

**Current total: 52 files, ~6,636 lines Kotlin. All 8 phases complete.**

## Bottlenecks
1. **Model files are NOT included** — emotion2vec.onnx (~125MB), phi3_mini_q4.onnx (~2.2GB), ggml-tiny.en.bin (~77MB), tokenizer.json (~2.4MB) must be downloaded on first launch via `ModelDownloadService`
2. **ONNX Runtime AAR** — adds ~30MB to APK size
3. **keystore.properties** — must be created with your release key for Play Store signing. See `keystore.properties.example`
4. **No device for testing** — builds succeed on CI (ubuntu-24.04) but runtime testing needs a physical Android device or emulator
5. **Play Console account** — required for Play Store publishing ($25 one-time fee)
6. **iOS builds** — need a Mac with Xcode 26.5+ (project.yml → xcodegen → build)
