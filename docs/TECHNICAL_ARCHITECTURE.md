# Soulo — Technical Architecture

## 1. System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         iOS Application                             │
│                                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────────┐   │
│  │ Presentation │  │   Domain    │  │          Data            │   │
│  │    Layer     │──│   Layer     │──│         Layer            │   │
│  │  (SwiftUI)   │  │  (Swift)    │  │   (Swift + Models)      │   │
│  └─────────────┘  └─────────────┘  └──────────────────────────┘   │
│                          │                      │                   │
│                          ▼                      ▼                   │
│                   ┌─────────────┐      ┌──────────────────┐        │
│                   │  ML Layer   │      │  Storage Layer   │        │
│                   │  (Models)   │      │  (SQLite + FS)   │        │
│                   └─────────────┘      └──────────────────┘        │
└─────────────────────────────────────────────────────────────────────┘
```

## 2. Presentation Layer (SwiftUI)

### Components
- `RecordView` — Recording UI with waveform visualization
- `HistoryView` — Chronological list of past entries
- `EntryDetailView` — Single entry with transcript + biomarkers + insights
- `InsightsView` — Pattern feed (daily insights)
- `TrendsView` — Charts and statistics
- `SettingsView` — Subscription, export, privacy controls

### State Management
- `@Observable` classes (iOS 17+)
- `AppState` — global app state (auth, subscription status)
- `JournalState` — recording state, entries list
- `InsightState` — patterns and insights cache

## 3. Domain Layer

### Core Models
```swift
struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let durationSeconds: Int
    let transcript: String
    let biomarkers: VoiceBiomarkers?
    let topics: [TopicAnalysis]?
    let emotionalState: EmotionalState?
    let audioFileURL: URL
}

struct VoiceBiomarkers: Codable {
    let pitchVariance: Double
    let speechRate: Double       // words per second
    let hesitationRate: Double   // silence / total time
    let vocalEnergy: Double      // RMS amplitude
    let pitchInstability: Double
    let microBreathCount: Int
    let jitter: Double
    let shimmer: Double
}

struct TopicAnalysis: Codable {
    let topic: String
    let sentiment: Double        // -1.0 to 1.0
    let frequency: Int
    let energyOnTopic: Double    // vocal energy when discussing
}

struct EmotionalState: Codable {
    let primaryEmotion: String
    let confidence: Double
    let valence: Double          // positive vs negative
    let arousal: Double          // calm vs excited
}

struct DetectedPattern: Identifiable, Codable {
    let id: UUID
    let type: PatternType
    let severity: Int           // 0-100
    let message: String
    let firstDetected: Date
    let lastDetected: Date
    let occurrenceCount: Int
    let evidenceRefs: [UUID]    // entry IDs
}

enum PatternType: String, Codable {
    case brokenPromise
    case topicAvoidance
    case sentimentDecline
    case goalAbandonment
    case contradiction
    case cognitiveShift
    case relationshipPattern
    case decisionRegret
}
```

### Services
```swift
protocol RecordingService {
    func startRecording() async throws
    func stopRecording() async throws -> JournalEntry
    func pauseRecording()
    func resumeRecording()
}

protocol TranscriptionService {
    func transcribe(audioData: Data) async throws -> String
}

protocol BiomarkerService {
    func extractBiomarkers(from audioData: Data) async throws -> VoiceBiomarkers
}

protocol TopicAnalysisService {
    func analyzeTopics(transcript: String, biomarkers: VoiceBiomarkers) async throws -> [TopicAnalysis]
}

protocol PatternDetectionService {
    func detectPatterns(in entries: [JournalEntry]) async throws -> [DetectedPattern]
}

protocol StorageService {
    func saveEntry(_ entry: JournalEntry) async throws
    func loadEntries(from date: Date, to: Date) async throws -> [JournalEntry]
    func loadEntry(id: UUID) async throws -> JournalEntry?
    func deleteEntry(_ entry: JournalEntry) async throws
}
```

## 4. ML Layer — Model Integration

### 4.1 Whisper.cpp (Transcription)
- **Model**: `ggml-tiny.en.bin` (77MB, 32x faster than real-time on iPhone 15)
- **Integration**: Swift package via whisper.cpp XCFramework
- **Usage**: Post-recording, process audio PCM buffer, return text
- **Processing time**: ~5 seconds for 3-minute audio on iPhone 14+

```swift
// Integration code
import Whisper

class WhisperTranscriptionService: TranscriptionService {
    private let whisper: Whisper
    
    init() throws {
        let modelPath = Bundle.main.path(forResource: "ggml-tiny.en", ofType: "bin")!
        whisper = try Whisper(modelPath: modelPath)
    }
    
    func transcribe(audioData: Data) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Convert PCM data to float samples
                    let samples = audioData.withUnsafeBytes { buf in
                        Array(UnsafeBufferPointer<Float>(
                            start: buf.baseAddress!.assumingMemoryBound(to: Float.self),
                            count: buf.count / MemoryLayout<Float>.size
                        ))
                    }
                    
                    // Transcribe
                    let result = try self.whisper.transcribe(samples: samples)
                    
                    // Re-run with LLM for speaker diarization/cleanup
                    continuation.resume(returning: result.text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

### 4.2 Phi-3-mini (Topic Extraction + Generation)
- **Model**: `Phi-3-mini-4k-instruct-q4.onnx` (~2.3GB, quantized)
- **Integration**: ONNX Runtime for iOS + CoreML conversion
- **Usage**: Extract topics, sentiment, and entities from transcript
- **Processing time**: ~3-5 seconds per 3-minute transcript on iPhone 15

```swift
class Phi3TopicService: TopicAnalysisService {
    private let model: OnnxModel
    
    init() throws {
        let modelPath = Bundle.main.path(forResource: "phi-3-mini-q4", ofType: "ort")!
        model = try OnnxModel(modelPath: modelPath)
    }
    
    func analyzeTopics(transcript: String, biomarkers: VoiceBiomarkers) async throws -> [TopicAnalysis] {
        let prompt = """
        Analyze this journal entry. Extract:
        1. Main topics discussed
        2. Sentiment for each topic (-1 to 1)
        3. Energy level (0-10)
        
        Transcript: \(transcript)
        Biomarkers: energy=\(biomarkers.vocalEnergy), pitchVariance=\(biomarkers.pitchVariance)
        """
        
        let response = try await model.generate(prompt: prompt, maxTokens: 256)
        return parseTopicResponse(response)
    }
}
```

### 4.3 emotion2vec (Voice Emotion)
- **Model**: `emotion2vec.onnx` (~50MB)
- **Integration**: ONNX Runtime for iOS
- **Emotions**: neutral, happy, sad, angry, fearful, disgusted, surprised, contempt
- **Processing time**: ~1 second for 3-minute audio

```swift
class EmotionDetectionService {
    private let model: OnnxModel
    
    func detectEmotion(from audioData: Data) async throws -> EmotionalState {
        // Extract Wav2Vec2 features
        let features = try extractFeatures(audioData)
        
        // Run emotion classifier
        let output = try model.run(input: features)
        
        // Parse output
        return EmotionalState(
            primaryEmotion: output.argmax(),
            confidence: output.max(),
            valence: computeValence(output),
            arousal: computeArousal(output)
        )
    }
}
```

## 5. Data Flow

### Recording Flow
```
User taps record
    → AVAudioEngine starts (format: 16kHz, 16-bit, mono)
    → Audio buffers written to temp file (AES-256 encrypted)
    → Waveform displayed in real-time
    
User taps stop
    → Audio file finalized and encrypted
    → Whisper.cpp transcribes (on background thread)
    → Biomarker DSP runs (on background thread)
    → emotion2vec runs (on background thread)
    → Phi-3-mini extracts topics (on background thread)
    → All results combined into JournalEntry
    → Entry saved to SQLite
    → Pattern engine runs (incremental update)
    → UI updates with insights
```

### Insight Generation Flow
```
User opens Insights tab
    → PatternDetectionService loads recent entries
    → Runs pattern detection algorithms:
        1. Scan for broken promises (keyword + timeline)
        2. Check topic avoidance (energy delta)
        3. Detect sentiment trends (rolling regression)
        4. Identify goal patterns (start vs. abandon cycle)
    → Returns prioritized patterns (by severity)
    → UI displays pattern cards
    
Daily push notification (scheduled)
    → System generates "Pattern of the day"
    → Highest severity pattern from last 24h
    → Delivered as notification + in-app card
```

### Backup / Restore Flow
```
Backup (user-initiated or automatic)
    → User sets encryption passphrase
    → All entries serialized to JSON
    → Encrypted with user's passphrase (AES-GCM)
    → Uploaded to iCloud (user's private storage)
    
Restore
    → Download encrypted blob from iCloud
    → User enters passphrase
    → Decrypt and import to local SQLite
```

## 6. Storage Schema

```sql
-- Core tables
CREATE TABLE entries (
    id TEXT PRIMARY KEY,
    timestamp INTEGER NOT NULL,
    duration_seconds INTEGER NOT NULL,
    transcript TEXT,
    biomarkers_json TEXT,          -- serialized VoiceBiomarkers
    emotional_state_json TEXT,     -- serialized EmotionalState
    created_at INTEGER DEFAULT (unixepoch())
);

CREATE TABLE topics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    topic TEXT NOT NULL,
    sentiment REAL,
    energy REAL
);

CREATE TABLE patterns (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    severity INTEGER NOT NULL,
    message TEXT NOT NULL,
    first_detected INTEGER NOT NULL,
    last_detected INTEGER NOT NULL,
    occurrence_count INTEGER DEFAULT 1,
    created_at INTEGER DEFAULT (unixepoch())
);

CREATE TABLE pattern_evidence (
    pattern_id TEXT NOT NULL REFERENCES patterns(id) ON DELETE CASCADE,
    entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    PRIMARY KEY (pattern_id, entry_id)
);

CREATE TABLE user_baselines (
    metric TEXT PRIMARY KEY,       -- e.g. "speech_rate", "vocal_energy"
    mean REAL NOT NULL,
    stddev REAL NOT NULL,
    sample_count INTEGER NOT NULL,
    last_updated INTEGER NOT NULL
);

-- Performance indexes
CREATE INDEX idx_entries_timestamp ON entries(timestamp);
CREATE INDEX idx_topics_entry_id ON topics(entry_id);
CREATE INDEX idx_topics_topic ON topics(topic);
CREATE INDEX idx_patterns_type ON patterns(type);
CREATE INDEX idx_patterns_severity ON patterns(severity DESC);
```

## 7. Security Architecture

| Layer | Mechanism |
|---|---|
| **Audio at rest** | AES-256-GCM encrypted files |
| **Audio in transit** | Never leaves device (except user-initiated backup) |
| **Database** | SQLCipher (encrypted SQLite), key derived from device biometrics |
| **ML processing** | All on-device, no network calls |
| **Cloud backup** | Zero-knowledge encryption (user holds key) |
| **Authentication** | Sign in with Apple (private email relay) |
| **Payments** | Stripe SDK (direct, no server intermediary) |

## 8. Device Requirements

| Requirement | Minimum | Recommended |
|---|---|---|
| **iOS** | 17.0 | 18.0+ |
| **Device** | iPhone 12 | iPhone 15+ |
| **RAM** | 4GB | 6GB+ |
| **Storage** | 500MB free | 2GB+ (for models + entries) |
| **Neural Engine** | A14 Bionic | A17+ |

## 9. Open Source Components

| Component | License | Size | Purpose |
|---|---|---|---|
| Whisper.cpp | MIT | 77MB | Speech-to-text |
| Phi-3-mini | MIT | 2.3GB | Topic extraction + generation |
| emotion2vec | MIT | 50MB | Voice emotion detection |
| SQLite (with SQLCipher) | Public Domain | — | Local database |
| ONNX Runtime | MIT | — | Model inference engine |
| Accelerate Framework | Apple Built-in | — | FFT, signal processing |
