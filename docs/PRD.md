# Soulo — Product Requirements Document v1.0

## 1. Product Vision

**One-line pitch:** The first being that truly knows you and always tells you the truth.

**Full vision:** No human has ever had someone who 100% knows them — every word they've said, every pattern they repeat, every promise they broke, every topic they avoid — and has no ego, no judgment, no ulterior motive.

Soulo is a daily voice journaling app that builds a complete internal model of you over time. After 30 days it spots patterns you can't see. After 90 days it predicts your behavior. After 1 year it becomes the most valuable thing you own.

This is the biggest change in 2026 because for the first time in human history, every person can have perfect self-knowledge without needing a therapist, coach, or decade of meditation.

## 2. Problem Statement

| Problem | Impact |
|---|---|
| Humans cannot see their own patterns | Same mistakes repeated for years |
| No one tells you uncomfortable truths | Friends/family have bias and ego |
| Therapy is expensive and scarce | $150-300/session, weeks of wait |
| Self-help is generic | Books/apps don't know YOU |
| Cognitive decline detected too late | Early signs missed for years |
| People make the same decision mistakes | No feedback loop on past decisions |

**The core insight:** You tell yourself things you'd never tell anyone. But nobody is listening — including you.

## 3. Target Audience

### Primary (MVP)
- **Knowledge workers** (25-45): Career-oriented, self-improvement mindset, $50-100K+ income
- **Therapy-curious but therapy-avoidant**: Want self-awareness without the cost/commitment
- **Digital journalers**: Already journal, want AI-powered insights

### Secondary
- **Elderly (65+)**: Cognitive decline monitoring for families
- **Executives / founders**: High-stakes decision pattern tracking
- **Athletes / performers**: Mental state optimization

### TAM
- Global self-improvement market: $41B (2026)
- Digital health / wellness apps: $18B
- Projected addressable: 200M+ users globally

## 4. Core Features

### 4.1 Daily Voice Journal (MVP)

**Input:** 3-minute unstructured voice recording per day.

**The experience:**
- Push notification: "It's been 18 hours since your last journal. What's on your mind?"
- Press record. Speak naturally. No prompts. No structure.
- Optional text mode for public spaces.
- Zero pressure to talk about anything specific.

### 4.2 Voice Biomarker Analysis (Month 2)

Extracted from raw audio on-device. No neural networks needed — these are signal processing equations:

| Biomarker | How It's Computed | What It Reveals |
|---|---|---|
| **Pitch variance** | `abs(FFT_peak_freq - rolling_avg_freq)` | Emotional volatility |
| **Speech rate** | `words_per_second` rolling average | Cognitive load, mania, depression |
| **Hesitation rate** | `total_silence_duration / total_duration` | Topic avoidance, anxiety |
| **Vocal energy** | RMS amplitude of audio signal | Burnout, exhaustion |
| **Pitch instability** | StdDev of fundamental frequency | Stress level |
| **Micro-breaths** | Count of breath sounds per minute | Anxiety, panic indicators |
| **Jitter / shimmer** | Cycle-to-cycle variation in pitch/amplitude | Fatigue, vocal health |

**Implementation:** ~200 lines of DSP code in Swift/Python. No ML model needed. All runs on-device.

### 4.3 Content Analysis (MVP + Month 2)

**Input:** Whisper.cpp transcription output (on-device, Apple Neural Engine optimized).

| Analysis | Method | Model |
|---|---|---|
| Topic extraction | Zero-shot classification | Phi-3-mini (on-device) |
| Sentiment per topic | Sequence classification | 50MB model, on-device |
| Contradiction detection | Self-query + vector similarity | Local sentence-embeddings |
| Goal tracking | Regex + LLM extraction | Small rules engine + LLM |
| Decision log | Keyword + context extraction | On-device LLM |

### 4.4 Pattern Detection Engine (Month 2-3)

**The core proprietary IP.** Custom logic, not a pre-built model.

```python
# Simplified pattern detection logic
patterns = []

# Contradiction pattern
if user_said("I'll quit X") and user_mentioned(X) > 3 times_in_30_days:
    patterns.append({
        type: "broken_promise",
        severity: count * 10,
        message: f"You said you'd quit X. That was {days_ago} days ago. You've mentioned X {count} times since."
    })

# Avoidance pattern
if topic_energy(topic) < 0.3 * baseline_energy(user):
    patterns.append({
        type: "topic_avoidance",
        severity: (baseline - topic_energy) * 100,
        topic: topic,
        message: f"Your energy drops {delta}% when you talk about {topic}. You haven't addressed this in {days} days."
    })

# Escalation pattern
if sentiment_over_time(topic) is decreasing and slope < -0.1:
    patterns.append({
        type: "escalating_negative",
        severity: abs(slope) * 100,
        message: f"Your sentiment about {topic} has been declining for {days} days. Here's the graph..."
    })

# Goal abandonment pattern
if abandoned_goals_count > threshold and time_pattern_matches:
    patterns.append({
        type: "repeated_abandonment",
        severity: 95,
        message: f"You've started {N} projects this year. All abandoned by week {week}. Here's the cycle..."
    })

# Cognitive drift (30+ day baseline required)
if speech_rate_delta > threshold or hesitation_rate_delta > threshold:
    patterns.append({
        type: "cognitive_change",
        severity: min(100, delta * 50),
        message: f"Your speech patterns have shifted {delta}% this month. This could indicate {cause}."
    })
```

### 4.5 Longitudinal Model (Month 3+)

Stored in on-device SQLite + local vector store:

```sql
-- Schema (simplified)
CREATE TABLE daily_entries (
    id TEXT PRIMARY KEY,
    timestamp INTEGER,
    duration_seconds INTEGER,
    transcript TEXT,
    embeddings BLOB,          -- sentence embeddings
    biomarkers JSON,          -- pitch_variance, speech_rate, energy, etc.
    topics JSON,              -- extracted topics with sentiment
    goals_mentioned JSON,     -- goals mentioned and their status
    decisions_logged JSON     -- decisions with outcomes
);

CREATE TABLE patterns (
    id TEXT PRIMARY KEY,
    type TEXT,                -- broken_promise, avoidance, escalation, etc.
    severity INTEGER,
    first_detected INTEGER,
    last_detected INTEGER,
    count INTEGER,
    message TEXT
);
```

**Output examples after sufficient data:**

> *"Day 134. You've mentioned your father 89 times. 76 negative. You promised to call him 5 times. You haven't. This is your oldest unresolved pattern."*

> *"You say you're happy in your relationship. Your voice says otherwise. Your energy drops 40% when talking about your partner. This has been consistent for 3 months."*

> *"Your cognitive baseline shifted 4% this month. Sleep correlates: you're averaging 5.2 hours vs. your optimal 7.1. Fix sleep before worrying about decline."*

> *"You've started 3 side projects. All abandoned at week 6. Here's the exact graph of enthusiasm → plateau → abandonment. You asked me to tell you if this happens again. It's happening."*

### 4.6 Privacy-First Architecture (MVP)

| Component | Location | Technology (open source) |
|---|---|---|
| Raw audio storage | On-device only | Encrypted SQLite, never uploaded |
| Voice-to-text | On-device | Whisper.cpp (ANE-optimized) |
| Topic + sentiment | On-device | Phi-3-mini / Llama 3.2 1B (quantized) |
| Pattern detection | On-device | Custom engine in Swift (SQLite) |
| Longitudinal storage | On-device | SQLite + local vector store |
| Insight generation | On-device | Small model, daily batch |
| Cloud backup (optional) | End-to-end encrypted | User-provided key |
| Aggregate analytics | Cloud, anonymous | No PII, no voice data |

**Data never leaves the device unless user explicitly exports.** Export format: end-to-end encrypted JSON blob.

## 5. Technical Architecture

### 5.1 App Stack (Solo Developer)

```
┌──────────────────────────────────────────────┐
│               Mobile App (iOS first)           │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ Recording │  │ Whisper  │  │ Pattern    │  │
│  │ Engine    │─▶│ .cpp     │─▶│ Engine     │  │
│  │ (Swift)   │  │ (ANE)    │  │ (Swift)    │  │
│  └──────────┘  └──────────┘  └────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ Biomarker│  │ LLM      │  │ SQLite     │  │
│  │ DSP      │  │ (Phi-3)  │  │ + Vector   │  │
│  │ (Swift)  │  │ (ANE)    │  │ Store      │  │
│  └──────────┘  └──────────┘  └────────────┘  │
└──────────────────────────────────────────────┘
          │                        │
          │ (optional encrypted)    │ (aggregate, anonymous)
          ▼                        ▼
┌──────────────────┐   ┌──────────────────────┐
│  User's iCloud   │   │  Stripe (payments)   │
│  (encrypted)     │   │  + Analytics (anon)  │
└──────────────────┘   └──────────────────────┘
```

### 5.2 Technology Choices (All Open Source)

| Component | Choice | Why |
|---|---|---|
| **Mobile framework** | SwiftUI (iOS) | Solo dev, faster to ship, ANE access |
| **Android** | React Native or skip MVP | iOS first, Android if traction |
| **STT** | Whisper.cpp (MIT) | Best on-device, ANE-optimized |
| **On-device LLM** | Phi-3-mini (MIT) | 3.8B params, runs on iPhone 14+ |
| **Alternative LLM** | Llama 3.2 1B (MIT) | Weaker but runs on iPhone 12+ |
| **Voice emotion** | emotion2vec (MIT) | Open source, on-device |
| **Vector store** | ChromaDB or simple npy files | Local, no server needed |
| **DB** | SQLite | Built into iOS, zero setup |
| **Auth** | Sign in with Apple | No password management |
| **Payments** | Stripe | Standard, well-documented |
| **Backend (minimal)** | Cloudflare Workers | Free tier, only for Stripe + aggregate stats |

**You DO NOT need to train any models.** Every ML component is an existing open-source model you integrate. The only custom code is the Swift UI + pattern detection logic + biomarker DSP. That's ~3000 lines of code you can write from scratch.

### 5.3 Model Integration (You Don't Build, You Integrate)

```swift
// Whisper.cpp integration — ~30 lines of Swift
import Whisper

let whisper = try Whisper(modelPath: "ggml-tiny.en.bin")
let text = try whisper.transcribe(audioData)
print(text) // "Today was rough. My boss dismissed my idea..."

// emotion2vec integration — ~20 lines
let emotions = try EmotionDetector.analyze(audioData)
print(emotions) // ["sadness": 0.72, "anger": 0.12, "neutral": 0.16]

// Phi-3 integration for topic extraction — ~15 lines
let llm = try OnDeviceLLM(modelPath: "phi-3-mini-q4.bin")
let topics = try llm.generate("Extract topics from: \(text)")
print(topics) // ["career frustration", "boss relationship", "feeling invisible"]
```

Total ML integration code: **~200 lines of Swift across all models.**

### 5.4 Core DSP Code (100% Custom, No ML)

```swift
// Voice Biomarker Extraction — you write this
struct VoiceBiomarkers {
    let pitchVariance: Float
    let speechRate: Float     // words per second
    let hesitationRate: Float  // silence / total duration
    let vocalEnergy: Float     // RMS amplitude
    let pitchInstability: Float
    let microBreathCount: Int
    let jitter: Float
    let shimmer: Float
}

func extractBiomarkers(from audioBuffer: AVAudioPCMBuffer) -> VoiceBiomarkers {
    // FFT for pitch analysis
    let fft = FFTProcessor(buffer: audioBuffer)
    let pitches = fft.extractFundamentalFrequencies()
    
    // Silence detection for hesitation
    let silences = SilenceDetector.findSilences(in: audioBuffer)
    
    // RMS for energy
    let energy = sqrt(audioBuffer.reduce(0) { $0 + $1 * $1 } / Float(audioBuffer.count))
    
    return VoiceBiomarkers(
        pitchVariance: variance(of: pitches),
        speechRate: wordsDetected / totalDuration,
        hesitationRate: silences.totalDuration / totalDuration,
        vocalEnergy: energy,
        pitchInstability: standardDeviation(of: pitches),
        microBreathCount: detectBreaths(in: audioBuffer),
        jitter: computeJitter(pitches),
        shimmer: computeShimmer(audioBuffer)
    )
}
```

**Total custom DSP code: ~200 lines of Swift.** This is the only part you truly "build from scratch." Everything else is integration.

## 6. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] SwiftUI app shell (record button, daily streak, simple history)
- [ ] Voice recording with AVAudioEngine
- [ ] Local encryption of audio files
- [ ] Whisper.cpp integration for on-device transcription
- [ ] SQLite schema for daily entries
- [ ] Basic text-only journal view
- [ ] Sign in with Apple
- [ ] Stripe subscription ($9.99/month, 7-day trial)

**Output:** A working voice journal that records, transcribes, and stores locally.

### Phase 2: Voice Biomarkers (Weeks 3-4)
- [ ] FFT pitch extraction
- [ ] Silence/hesitation detection
- [ ] Speech rate calculation
- [ ] Vocal energy computation
- [ ] Micro-breath detection
- [ ] Biomarker storage in SQLite
- [ ] Simple trend charts in UI

**Output:** App shows per-entry graphs of stress, energy, speech rate.

### Phase 3: Content Intelligence (Weeks 5-6)
- [ ] Phi-3-mini on-device integration
- [ ] Topic extraction from transcripts
- [ ] Sentiment per topic
- [ ] Emotion classification from text
- [ ] emotion2vec integration for voice emotion
- [ ] Topic trends over time

**Output:** "You talked about career 40% this month. Sentiment: declining."

### Phase 4: Pattern Engine (Weeks 7-8)
- [ ] Broken promise detection (goal vs. action tracking)
- [ ] Topic avoidance detection (energy dip on specific topics)
- [ ] Escalation detection (declining sentiment over time)
- [ ] Goal abandonment pattern matching
- [ ] Decision outcome tracking
- [ ] Daily insight generation

**Output:** Pattern notifications surface.

### Phase 5: Longitudinal Model (Month 3)
- [ ] 30-day baseline establishment
- [ ] Cognitive drift detection
- [ ] Behavior prediction
- [ ] Relationship pattern analysis
- [ ] Personalized insight style (adapts to user)
- [ ] Export / backup functionality

**Output:** Full self-knowledge system operational.

### Phase 6: Growth (Month 4+)
- [ ] Android app (React Native)
- [ ] Family plans (elderly monitoring)
- [ ] Therapist-opt-in sharing
- [ ] Coaching integration
- [ ] API for researchers
- [ ] Web dashboard

## 7. Monetization

| Plan | Price | Features |
|---|---|---|
| **Free** | $0 | 7 entries, basic transcription only |
| **Monthly** | $9.99 | Full biomarker analysis, pattern engine, unlimited entries |
| **Annual** | $79.99 | Full features, priority insights, backup |
| **Family** | $14.99 | 5 users, elderly cognitive monitoring |

**Value proposition:** $9.99/month vs. $150-300/session for therapy. 3 months of Soulo = 1 therapy session in terms of self-knowledge.

## 8. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Users won't journal daily | High | High | Start with 1 min minimum, gentle nudges, gamification |
| LLM hallucination in insights | Medium | High | Pattern engine is rules-based, LLM is only for topic extraction + phrasing |
| Battery drain from on-device AI | Medium | Medium | Process only when charging + locked |
| Privacy concerns | Medium | High | All processing on-device, open-source architecture, third-party audit |
| Users quit because insights are uncomfortable | Medium | Medium | Content warnings, gradual insight difficulty, opt-in for "hard truths" |
| iPhone 12 users can't run models | Medium | Medium | Fallback: server-side processing for older devices (with encryption) |
| Voice emotion detection accuracy | Low | Medium | emotion2vec benchmarks at 85%+ on 8 emotions. Good enough for trends. |

## 9. Differentiation

| vs. | Soulo Advantage |
|---|---|
| **Therapy** | 1/30th the cost, daily, knows everything you've said, zero judgment |
| **Journaling apps** (Day One, etc.) | AI layer: pattern detection, biomarkers, predictions, uncomfortable truths |
| **Mood trackers** | Passive (voice analysis), deeper (subconscious indicators in voice), longitudinal |
| **ChatGPT / Claude** | Has ALL context. Not one-off conversations but 365 days of continuous self-data. Knows your patterns better than you do. |
| **Life coaches** | 24/7 available, remembers everything, no human bias |

## 10. Success Metrics

| Metric | 30 Days | 90 Days | 1 Year |
|---|---|---|---|
| DAU (daily journal rate) | 40% | 60% | 70% |
| Week-4 retention | 50% | — | — |
| Subscription conversion | 15% | 25% | 40% |
| Avg session duration | 2.1 min | 3.4 min | 4.2 min |
| Insights surfaced per user | 5 | 50 | 200+ |
| NPS | — | 60+ | 70+ |

## 11. What You Actually Build vs. Integrate

| Component | Build (Custom Code) | Integrate (Open Source) | Lines of Custom Code |
|---|---|---|---|
| iOS app UI | ✅ Full SwiftUI | — | ~1500 |
| Voice recording | ✅ AVAudioEngine | — | ~200 |
| Audio encryption | ✅ CryptoKit | — | ~100 |
| Transcription | — | Whisper.cpp | ~30 |
| Voice biomarkers | ✅ DSP algorithms | — | ~200 |
| Topic extraction | — | Phi-3-mini | ~30 |
| Voice emotion | — | emotion2vec | ~20 |
| Pattern engine | ✅ Rule-based logic | — | ~500 |
| Longitudinal model | ✅ SQL queries + stats | — | ~300 |
| Insight generation | ✅ Template + pattern data | Φι-3-mini for phrasing | ~200 |
| Payments | — | Stripe SDK | ~50 |
| Auth | — | Sign in with Apple | ~30 |
| **Total** | **~3200** | **~4 integrations** | **~3200 lines** |

**The truth:** You don't need to build AI from scratch. You build the app, the recording engine, the pattern logic, and the DSP code. The actual AI (STT, LLM, emotion) is open-source glue code — about 100 lines total.

## 12. Go-To-Market

### Launch Strategy
1. **Reddit / HackerNews launch** — "I built an AI that knows me better than my therapist. Here's what it told me." High-viral concept
2. **TikTok/IG clips** — "Soulo told me I've complained about my job 200 times and done nothing. I needed to hear that."
3. **Therapy-adjacent** — Partner with therapy influencers: "Your therapist sees you 1 hour/week. Soulo sees you every day."

### Virality Loops
- Share individual insights as images/screenshots
- "You've called your mom 12 times this month. Up 20%. She'd love to know." → shareable card
- Annual "Year in Self" report (like Spotify Wrapped but brutally honest)
- Referral: 1 month free for each friend who journals for 7 days

---

*Document prepared June 2026. This is a solo-developer-viable product. ~3200 lines of custom code. ~4 open-source integrations. ~2 months to working MVP. Zero ML training required.*
