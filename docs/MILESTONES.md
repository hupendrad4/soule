# Soulo — Milestones & Timeline

## Overview

Total estimated time to MVP: **90 days** (3 months)
Total estimated custom code: **~3,200 lines of Swift**
Total ML integration: **~4 open-source models** (~200 lines of glue code)

---

## Milestone 1: Core Recording (Day 14)
**Deliverable:** Working app that records voice, encrypts it, stores it locally, and plays it back.

| Task | Days | Dependencies |
|---|---|---|
| SwiftUI project scaffold | 1 | None |
| AVAudioEngine recording | 2 | None |
| Audio encryption (CryptoKit) | 1 | Recording |
| SQLite schema + storage | 2 | None |
| History view (list + playback) | 2 | Storage |
| Dark/light mode UI | 1 | Scaffold |
| Push notification setup | 2 | None |
| CI/CD to TestFlight | 3 | Apple Developer account |

**Testing criteria:**
- [ ] Record 3 minutes of audio
- [ ] Audio file encrypted at rest (verify by attempting to read raw file)
- [ ] Playback works
- [ ] Entry appears in history within 1 second of recording
- [ ] App handles background/foreground transitions

---

## Milestone 2: Transcription (Day 21)
**Deliverable:** Every recording is automatically transcribed on-device.

| Task | Days | Dependencies |
|---|---|---|
| Whisper.cpp XCFramework build | 2 | None |
| Integration in recording pipeline | 2 | Milestone 1 |
| Progress indicator (recording → transcribing → done) | 1 | Milestone 1 |
| Edit transcript UI | 1 | Integration |
| Search history by text | 1 | Storage |

**Testing criteria:**
- [ ] 3-minute recording transcribed in <10 seconds on iPhone 14+
- [ ] Word Error Rate <10% on clear speech
- [ ] Transcript search returns results
- [ ] User can correct transcription errors

---

## Milestone 3: Voice Biomarkers (Day 28)
**Deliverable:** Every entry analyzed for pitch, speech rate, hesitation, energy, and stress.

| Task | Days | Dependencies |
|---|---|---|
| Audio preprocessing pipeline | 1 | Milestone 1 |
| FFT pitch extraction | 2 | Accelerate framework |
| Silence/hesitation detection | 1 | Preprocessing |
| Speech rate calculation | 1 | Milestone 2 |
| Vocal energy computation | 1 | Preprocessing |
| Micro-breath detection | 1 | Preprocessing |
| Jitter/shimmer computation | 1 | FFT |
| Storage + visualization | 2 | Milestone 1 |

**Testing criteria:**
- [ ] Biomarkers computed for every entry
- [ ] Pitch variance distinguishable between calm (low) and excited (high) speech
- [ ] Hesitation rate correlates with topic transitions
- [ ] Charts render in <500ms
- [ ] 30-day trend view works

---

## Milestone 4: Content Intelligence (Day 42)
**Deliverable:** Topics extracted from every entry with sentiment and emotional state.

| Task | Days | Dependencies |
|---|---|---|
| Phi-3-mini model conversion (.mlpackage) | 3 | None |
| ONNX Runtime iOS integration | 2 | None |
| Topic extraction pipeline | 2 | Milestone 2, Whisper |
| Sentiment analysis per topic | 1 | Topic extraction |
| Entity extraction (people, places) | 1 | Topic extraction |
| emotion2vec integration | 2 | Milestone 1 |
| Topic trend visualization | 2 | Milestone 1 |
| Word cloud / topic heatmap | 1 | Topic extraction |

**Testing criteria:**
- [ ] Topics extracted correctly for 5 test entries
- [ ] Sentiment matches manual rating (±0.2) for 80% of entries
- [ ] Topic trends update daily
- [ ] Emotion detection matches self-report for 70% of entries

---

## Milestone 5: Pattern Engine (Day 56)
**Deliverable:** App detects and surfaces behavioral patterns automatically.

| Task | Days | Dependencies |
|---|---|---|
| Broken promise detector | 3 | Milestone 4 |
| Topic avoidance detector | 2 | Milestone 3, Milestone 4 |
| Sentiment escalation detector | 2 | Milestone 4 |
| Goal abandonment pattern | 2 | Milestone 4 |
| Contradiction detector | 3 | Milestone 4 |
| Decision outcome tracker | 2 | Milestone 4 |
| Pattern storage + ranking | 2 | Milestone 1 |
| Daily insight cards UI | 3 | None |
| Push notification for insights | 1 | Milestone 1 |

**Testing criteria:**
- [ ] Broken promise detected: user says "I'll quit X" then mentions X 3+ times
- [ ] Avoidance detected: energy drops >30% on specific topic
- [ ] Goal cycle detected: start → abandon pattern identified
- [ ] Contradiction detected: "I love my job" vs "I hate going to work"
- [ ] Pattern severity ranking is logical
- [ ] Daily insight generated and delivered

---

## Milestone 6: Longitudinal Model (Day 70)
**Deliverable:** after 30+ days of data, app establishes user baseline and detects shifts.

| Task | Days | Dependencies |
|---|---|---|
| Baseline algorithm (rolling median) | 2 | Milestone 3 |
| 30-day biomarker baselines | 1 | Milestone 3 |
| Cognitive drift detection | 3 | Milestone 3, Baseline |
| Behavior prediction engine | 3 | Milestone 5 |
| Relationship pattern analysis | 2 | Milestone 5 |
| Encrypted cloud backup | 2 | Milestone 1 |
| Export functionality (JSON) | 1 | Milestone 1 |

**Testing criteria:**
- [ ] Baseline established after 30 entries
- [ ] Anomaly detected when speech rate deviates >2σ from baseline
- [ ] Prediction: "You'll abandon this goal in 2 weeks" → accurate 70% of time
- [ ] Backup/restore works end-to-end
- [ ] Export produces readable JSON

---

## Milestone 7: Monetization + Launch (Day 90)
**Deliverable:** Publicly available app with subscription revenue.

| Task | Days | Dependencies |
|---|---|---|
| Stripe SDK integration | 2 | None |
| Free tier (7 entries) | 1 | Milestone 1 |
| Subscription paywall UI | 2 | Milestone 1 |
| Monthly ($9.99) + Annual ($79.99) | 1 | Stripe |
| App Store screenshots + preview | 3 | Milestone 4 |
| Privacy policy | 1 | None |
| Terms of service | 1 | None |
| App Store Review submission | 5 | All above |
| Launch on Product Hunt | 1 | App live |
| Launch on Hacker News | 1 | App live |

**Testing criteria:**
- [ ] Free tier: recording blocked after 7 entries
- [ ] Subscription: purchase → unlock works immediately
- [ ] Subscription: cancel → reverts to free (after period)
- [ ] App Store Review: approved
- [ ] Product Hunt: published
- [ ] First 10 paid users acquired

---

## Post-Launch Milestones

| Milestone | Target Date | Success Metric |
|---|---|---|
| 100 paid users | Month 2 post-launch | Revenue: $1,000/month |
| 1,000 paid users | Month 6 post-launch | Revenue: $10,000/month |
| Android app | Month 6 post-launch | 2x addressable market |
| Family plan | Month 7 post-launch | $14.99/month, elderly monitoring |
| Cognitive decline research partnership | Month 12 post-launch | Academic publication |
| 10,000 paid users | Month 18 post-launch | Revenue: $100,000/month |
