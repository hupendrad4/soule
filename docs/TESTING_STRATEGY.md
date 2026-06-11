# Soulo — Testing Strategy

## 1. Test Pyramid

```
         ┌──────────┐
         │   E2E    │  ← Manual + XCUITest (critical flows only)
         │  (5%)    │
        ┌┴──────────┴┐
        │Integration  │  ← Service tests (recording → transcription → storage)
        │   (15%)    │
       ┌┴────────────┴┐
       │   Unit       │  ← DSP, pattern engine, models, utilities
       │   (80%)      │
       └──────────────┘
```

## 2. Unit Tests

### 2.1 Voice Biomarker DSP (~50 tests)

```swift
class BiomarkerDSPTests: XCTestCase {
    func testPitchExtraction_CalmSpeech() {
        let audio = generateTestAudio(pitchHz: 200, variance: 5)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertEqual(biomarkers.pitchVariance, 5, accuracy: 2)
    }
    
    func testPitchExtraction_ExcitedSpeech() {
        let audio = generateTestAudio(pitchHz: 200, variance: 50)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertGreaterThan(biomarkers.pitchVariance, 30)
    }
    
    func testSpeechRate_Normal() {
        let audio = generateTestAudio(wordsPerSecond: 3.5)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertEqual(biomarkers.speechRate, 3.5, accuracy: 0.5)
    }
    
    func testSpeechRate_Fast() {
        let audio = generateTestAudio(wordsPerSecond: 6.0)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertGreaterThan(biomarkers.speechRate, 4.5)
    }
    
    func testHesitationRate_NoSilence() {
        let audio = generateTestAudio(silenceRatio: 0.05)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertLessThan(biomarkers.hesitationRate, 0.1)
    }
    
    func testHesitationRate_WithPauses() {
        let audio = generateTestAudio(silenceRatio: 0.4)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertGreaterThan(biomarkers.hesitationRate, 0.3)
    }
    
    func testVocalEnergy_Loud() {
        let audio = generateTestAudio(amplitude: 0.9)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertGreaterThan(biomarkers.vocalEnergy, 0.7)
    }
    
    func testVocalEnergy_Quiet() {
        let audio = generateTestAudio(amplitude: 0.1)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertLessThan(biomarkers.vocalEnergy, 0.2)
    }
    
    func testMicroBreathDetection() {
        let audio = generateTestAudio(withBreaths: 5)
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertEqual(biomarkers.microBreathCount, 5)
    }
    
    func testEmptyAudio_ReturnsZeroValues() {
        let audio = Data(repeating: 0, count: 16000 * 3 * 2) // 3 seconds silence
        let biomarkers = extractBiomarkers(from: audio)
        XCTAssertEqual(biomarkers.vocalEnergy, 0, accuracy: 0.01)
        XCTAssertEqual(biomarkers.speechRate, 0)
    }
    // +40 more edge cases
}
```

### 2.2 Pattern Engine (~60 tests)

```swift
class PatternEngineTests: XCTestCase {
    func testBrokenPromise_Detected() {
        let entries = [
            makeEntry(day: 0, text: "I'm going to quit smoking", sentiment: 0.8),
            makeEntry(day: 3, text: "I had a cigarette today", sentiment: -0.2),
            makeEntry(day: 7, text: "I bought another pack", sentiment: -0.5),
            makeEntry(day: 14, text: "I really need to quit smoking", sentiment: 0.3),
        ]
        let patterns = detectPatterns(in: entries)
        XCTAssertTrue(patterns.contains { $0.type == .brokenPromise })
    }
    
    func testBrokenPromise_NotDetected_WhenKept() {
        let entries = [
            makeEntry(day: 0, text: "I'm going to quit smoking", sentiment: 0.8),
            makeEntry(day: 30, text: "It's been 30 days without smoking", sentiment: 0.9),
        ]
        let patterns = detectPatterns(in: entries)
        XCTAssertFalse(patterns.contains { $0.type == .brokenPromise })
    }
    
    func testTopicAvoidance_Detected() {
        let entries = [
            makeEntry(day: 0, text: "Work is going well", energy: 0.8),
            makeEntry(day: 1, text: "I need to talk about work...", energy: 0.3),
            makeEntry(day: 2, text: "Anyway, let me talk about my vacation", energy: 0.7),
        ]
        let patterns = detectPatterns(in: entries)
        XCTAssertTrue(patterns.contains { $0.type == .topicAvoidance })
    }
    
    func testSentimentDecline_Detected() {
        let entries = (0..=7).map { day in
            makeEntry(day: day, text: "About my relationship...", sentiment: 0.8 - Double(day) * 0.1)
        }
        let patterns = detectPatterns(in: entries)
        XCTAssertTrue(patterns.contains { $0.type == .sentimentDecline })
    }
    
    func testGoalAbandonment_Cycle() {
        let entries = [
            makeEntry(day: 0, text: "Starting my new project!", sentiment: 0.9),
            makeEntry(day: 10, text: "Project is slow", sentiment: 0.3),
            makeEntry(day: 21, text: "I should start a new project", sentiment: 0.8),
            makeEntry(day: 31, text: "This project is also slow", sentiment: 0.2),
        ]
        let patterns = detectPatterns(in: entries)
        XCTAssertTrue(patterns.contains { $0.type == .goalAbandonment })
    }
    
    func testContradiction_Detected() {
        let entries = [
            makeEntry(day: 0, text: "I absolutely love my job", sentiment: 0.9),
            makeEntry(day: 1, text: "I hate going to work", sentiment: -0.8),
        ]
        let patterns = detectPatterns(in: entries)
        XCTAssertTrue(patterns.contains { $0.type == .contradiction })
    }
    
    func testSeverityScaling_Correct() {
        // 10 mentions = higher severity than 2 mentions
        // ...
    }
    
    func testPatternDeduplication() {
        // Same pattern shouldn't be created twice
    }
    // +50 more edge cases
}
```

### 2.3 Storage Layer (~30 tests)

```swift
class StorageTests: XCTestCase {
    func testSaveAndLoadEntry() throws { ... }
    func testDeleteEntry() throws { ... }
    func testLoadEntriesByDateRange() throws { ... }
    func testEncryptedDatabase_UnreadableWithoutKey() throws { ... }
    func testConcurrentWrites() throws { ... }
    func testLargeDataset_Performance() throws { ... }
    func testMigration_FromV1toV5() throws { ... }
    // +20 more
}
```

### 2.4 Audio Pipeline (~20 tests)

```swift
class AudioPipelineTests: XCTestCase {
    func testEncryptionRoundTrip() { ... }
    func testFormatConversion_16kHz16bitMono() { ... }
    func testSilenceTrimming() { ... }
    func testNormalization_PeakLevel() { ... }
    func testFileCleanup_OnDelete() { ... }
    func testInterruptedRecording_Recovery() { ... }
    // +15 more
}
```

## 3. Integration Tests

### 3.1 Recording → Transcription → Storage Flow

```swift
class RecordingIntegrationTests: XCTestCase {
    func testFullRecordingPipeline() async throws {
        // 1. Start recording service
        let service = RecordingService()
        
        // 2. Feed test audio data
        let testAudio = loadTestAudioFile("sample_journal_3min.wav")
        try await service.processExternalAudio(testAudio)
        
        // 3. Wait for transcription (up to 30 seconds)
        let entry = try await service.currentEntry
            .filter { $0.transcriptStatus == .done }
            .timeout(30)
            .firstValue
        
        // 4. Verify transcription is non-empty
        XCTAssertFalse(entry.transcript.isEmpty)
        XCTAssertTrue(entry.transcript.contains("work"))
        
        // 5. Verify biomarkers extracted
        XCTAssertNotNil(entry.biomarkers)
        XCTAssertGreaterThan(entry.biomarkers!.speechRate, 0)
        
        // 6. Verify topics extracted
        XCTAssertFalse(entry.topics.isEmpty)
        
        // 7. Verify stored in database
        let loaded = try await storage.loadEntry(id: entry.id)
        XCTAssertNotNil(loaded)
    }
}
```

### 3.2 Pattern Engine Over Real Data

```swift
func testPatternEngine_WithSynthetic30DayData() async throws {
    let generator = SyntheticUserDataGenerator()
    let entries = generator.generate30Days(userType: .procrastinator)
    let patterns = try await patternService.detectPatterns(in: entries)
    
    XCTAssertTrue(patterns.contains { $0.type == .goalAbandonment })
    XCTAssertTrue(patterns.contains { $0.type == .brokenPromise })
    XCTAssertGreaterThan(patterns.count, 3)
}
```

## 4. UI Tests (XCUITest)

### 4.1 Critical Paths

```swift
class SouloUITests: XCTestCase {
    func testFirstLaunch_Onboarding() {
        // Verify onboarding screens appear in order
        // Verify "Start Recording" button exists
        // Verify privacy screen
    }
    
    func testRecordingFlow() {
        // Tap record → verify waveform animates
        // Wait 3 seconds → tap stop → verify processing indicator
        // Wait for completion → verify entry appears in history
    }
    
    func testInsightCards_Display() {
        // Seed database with 30 entries
        // Navigate to Insights tab
        // Verify insight cards visible
        // Verify severity indicators
    }
    
    func testPaywall_After7Entries() {
        // Seed 7 entries
        // Try to record 8th → paywall appears
        // Verify subscription options
    }
    
    func testSubscription_PurchaseFlow() {
        // Tap subscribe → App Store sheet appears
        // Complete purchase → verify unlock
    }
}
```

## 5. Performance Tests

| Test | Metric | Pass Criteria |
|---|---|---|
| Recording → Transcribed | Latency | <15s for 3-min audio on iPhone 14+ |
| Biomarker extraction | Latency | <3s for 3-min audio |
| Topic extraction | Latency | <5s for 3-min transcript |
| Pattern scan (30 entries) | Latency | <2s |
| App cold start | Time | <2s |
| Memory during recording | RAM | <150MB |
| Memory during inference | RAM | <500MB (all models) |
| Battery per recording | Drain | <1% per 3-min recording |
| Storage per entry | Size | <2MB per entry (audio + data) |
| 10,000 entries | DB size | <500MB |

## 6. Beta Testing Plan

### Phase 1: Internal (Week 6)
- **Testers**: You + 3 friends
- **Focus**: Crash reporting, basic functionality
- **Duration**: 1 week

### Phase 2: Closed Beta (Week 8)
- **Testers**: 50 users (invite via TestFlight link on Twitter/Reddit)
- **Focus**: Pattern accuracy, insight quality, battery drain
- **Duration**: 2 weeks
- **Incentive**: 3 months free

### Phase 3: Public Beta (Week 10)
- **Testers**: Unlimited (TestFlight open)
- **Focus**: Scale, edge cases, localization
- **Duration**: 2 weeks

## 7. Test Data Generation

```swift
class SyntheticUserDataGenerator {
    func generate30Days(userType: UserType) -> [JournalEntry] {
        switch userType {
        case .procrastinator:
            return generateProcrastinatorData()
        case .anxious:
            return generateAnxiousData()
        case .healthy:
            return generateHealthyData()
        case .declining:
            return generateDecliningData()
        }
    }
    
    private func generateProcrastinatorData() -> [JournalEntry] {
        // Generates 30 entries with:
        // - Repeated mentions of quitting bad habit
        // - Declining sentiment over time
        // - Topic avoidance around career
        // - Goal abandonment pattern
    }
}
```

## 8. Test Automation

```yaml
# GitHub Actions workflow
name: Test
on: [pull_request, push]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild test -scheme Soulo -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
      - run: swiftlint
```
