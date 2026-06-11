# Soulo — ML Model Integration Guide

## Core Principle

**You do NOT train, fine-tune, or build any ML models.**

All models used are:
1. Open source (MIT or permissive license)
2. Pre-trained
3. Already optimized for on-device inference
4. Ready to integrate with <50 lines of code each

---

## Model 1: Whisper.cpp — Speech-to-Text

### What it does
Transcribes voice recordings to text. 77MB model runs 32x faster than real-time on iPhone 15.

### How to integrate

```bash
# Step 1: Download pre-converted model
curl -L -o Models/ggml-tiny.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin
```

```swift
// Step 2: Add whisper.cpp Swift package
// Xcode → File → Add Package Dependencies → https://github.com/ggerganov/whisper.spm

// Step 3: Implement transcription service (30 lines)
import Whisper

class WhisperService {
    private let whisper: Whisper
    
    init() throws {
        let path = Bundle.main.path(forResource: "ggml-tiny.en", ofType: "bin")!
        whisper = try Whisper(modelPath: path)
    }
    
    func transcribe(audioData: Data) -> String {
        // Convert to float samples
        let samples = audioData.withUnsafeBytes { buf in
            Array(UnsafeBufferPointer<Float>(
                start: buf.baseAddress!.assumingMemoryBound(to: Float.self),
                count: buf.count / 4
            ))
        }
        // Transcribe
        let result = try! whisper.transcribe(samples: samples)
        return result.text
    }
}
```

### Cost
- **Download size**: 77MB (bundled in app)
- **RAM usage**: ~200MB during inference
- **Speed**: ~5 seconds for 3-minute audio on iPhone 14+

### Why this model
- Best accuracy-to-size ratio for on-device
- Optimized for Apple Neural Engine via CoreML
- Supports punctuation and capitalization
- Works offline

---

## Model 2: Phi-3-mini — Topic Extraction + Text Generation

### What it does
3.8B parameter LLM that runs on-device. Used for:
- Extracting topics from journal entries
- Classifying sentiment per topic
- Detecting entities (people, places, companies)
- Generating insight phrasing

### How to integrate

```bash
# Step 1: Download quantized model (4-bit)
curl -L -o Models/phi-3-mini-q4.onnx \
  https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/phi-3-mini-4k-instruct-q4.onnx
```

```swift
// Step 2: Integration using ONNX Runtime for iOS (~40 lines)
import ONNXRuntime

class Phi3Service {
    private let ortEnv: ORTEnv
    private let ortSession: ORTSession
    
    init() throws {
        ortEnv = try ORTEnv(loggingLevel: .warning)
        let modelPath = Bundle.main.path(forResource: "phi-3-mini-q4", ofType: "onnx")!
        ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
    }
    
    func extractTopics(from transcript: String) -> [TopicResult] {
        let prompt = """
        Extract topics from this journal entry. 
        Return JSON array with topic name and sentiment (-1 to 1).
        Text: \(transcript)
        """
        // Tokenize, run inference, detokenize
        let response = try! runInference(prompt: prompt, maxTokens: 128)
        return parseTopics(from: response)
    }
    
    func generateInsight(from data: PatternData) -> String {
        let prompt = "Given this pattern data: \(data). Generate a 1-sentence insight."
        let response = try! runInference(prompt: prompt, maxTokens: 64)
        return response
    }
}
```

### Cost
- **Download size**: 2.3GB (download on first launch)
- **RAM usage**: ~1.5GB during inference
- **Speed**: ~3-5 seconds per prompt on iPhone 15
- **Storage**: 2.3GB on device after download

### Why this model
- Smallest model with reliable topic extraction
- MIT license (commercial use allowed)
- ONNX Runtime has mature iOS support
- 4-bit quantization makes it feasible on phone

### Fallback for older devices (iPhone 12/13)
Use Phi-3-mini via server-side inference with encryption:

```swift
// Server fallback for devices without enough RAM
func extractTopicsFallback(transcript: String) async throws -> [TopicResult] {
    // Encrypt transcript with user's key
    let encrypted = try encrypt(transcript, with: userKey)
    
    // Send to server (encrypted payload)
    let response = try await api.post("/analyze", body: encrypted)
    
    // Decrypt response
    return try decrypt(response, with: userKey)
}
```

---

## Model 3: emotion2vec — Voice Emotion Detection

### What it does
Extracts 8 emotions from raw audio: neutral, happy, sad, angry, fearful, disgusted, surprised, contempt.

### How to integrate

```bash
# Step 1: Download model
curl -L -o Models/emotion2vec.onnx \
  https://huggingface.co/facebook/emotion2vec/resolve/main/emotion2vec.onnx
```

```swift
// Step 2: Integration (~20 lines)
class EmotionService {
    private let model: ONNXModel
    
    init() throws {
        let path = Bundle.main.path(forResource: "emotion2vec", ofType: "onnx")!
        model = try ONNXModel(modelPath: path)
    }
    
    func detectEmotion(from audioData: Data) -> EmotionResult {
        // Extract Wav2Vec2 features
        let features = extractFeatures(audioData)  // ~50 lines of DSP
        // Run classifier
        let outputs = try! model.run(input: features)
        // Get highest probability emotion
        let emotions = ["neutral", "happy", "sad", "angry", "fearful", "disgusted", "surprised", "contempt"]
        let maxIdx = outputs.argmax()
        return EmotionResult(
            primary: emotions[maxIdx],
            confidence: outputs[maxIdx],
            allProbabilities: Dictionary(uniqueKeysWithValues: zip(emotions, outputs))
        )
    }
}
```

### Why this model
- Pre-trained on 50K+ hours of emotional speech
- 85%+ accuracy on 8-class emotion classification
- Small (50MB), fast (<1 second inference)

---

## Model 4: Local Embeddings — Contradiction Detection

### What it does
Generates sentence embeddings for semantic similarity. Used to detect when a user contradicts themselves across entries.

### How to integrate

```swift
// Use Apple's built-in NaturalLanguage framework (no download needed)
import NaturalLanguage

class EmbeddingService {
    private let embedding: NLEmbedding
    
    init() {
        embedding = NLEmbedding.sentenceEmbedding(for: .english)!
    }
    
    func findContradictions(in entries: [JournalEntry]) -> [Contradiction] {
        var contradictions: [Contradiction] = []
        
        for i in 0..<entries.count {
            for j in (i+1)..<entries.count {
                let similarity = embedding.distance(
                    between: entries[i].transcript,
                    and: entries[j].transcript
                )
                
                // If entries are about same topic but opposite sentiment
                if similarity > 0.7 &&
                   entries[i].dominantSentiment * entries[j].dominantSentiment < 0 {
                    contradictions.append(Contradiction(
                        entry1: entries[i].id,
                        entry2: entries[j].id,
                        topic: extractCommonTopic(entries[i], entries[j])
                    ))
                }
            }
        }
        return contradictions
    }
}
```

### Why this approach
- Built into iOS (NLEmbedding) — zero download, zero license
- Optimized for Apple Silicon
- ~50MB RAM usage
- No network calls

---

## License Summary

| Model | License | Commercial Use | Need to Attribute |
|---|---|---|---|
| Whisper.cpp | MIT | ✅ Yes | ✅ Include license |
| Phi-3-mini | MIT | ✅ Yes | ✅ Include license |
| emotion2vec | MIT | ✅ Yes | ✅ Include license |
| NLEmbedding | Apple Built-in | ✅ Yes | No attribution needed |

## Total Integration Lines

| Model | Swift/Integration Code | Status |
|---|---|---|
| Whisper.cpp | ~30 lines | Downloaded + linked as package |
| Phi-3-mini | ~40 lines | Downloaded on first launch |
| emotion2vec | ~20 lines | Downloaded on first launch |
| NLEmbedding | ~15 lines | Built into iOS |
| **Total** | **~105 lines** | |

**You write zero ML training code. You write ~100 lines of integration glue code.**
