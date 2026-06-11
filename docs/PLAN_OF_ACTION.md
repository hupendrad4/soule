# Soulo — Plan of Action

## Phase 0: Foundation (Days 1-7) ✓ COMPLETED

### Setup ✓
- [x] Initialize SwiftUI iOS project on XcodeGen
- [x] Set up Git repo with main branch protection
- [x] Create development provisioning profile + TestFlight setup
- [x] Set up Apple Developer account + Sign in with Apple

### Week 1 Deliverables ✓
- [x] SwiftUI app shell with tab navigation (Record, History, Insights, Settings)
- [x] Voice recording with AVAudioEngine (start, stop, save to encrypted local file)
- [x] Audio encryption using CryptoKit (AES-GCM)
- [x] SQLite schema for daily entries (17 tables)
- [x] TestFlight build for internal testing
- [x] CI/CD pipeline (GitHub Actions → TestFlight)
- [x] All documentation (PRD, architecture, design, business model, testing, etc.)

## Phase 1: Recording + Transcription (Days 8-14) ✓ COMPLETED

### Week 2 Deliverables ✓
- [x] Whisper.spm package dependency (SPM via project.yml)
- [x] WhisperWrapper.swift — robust Swift wrapper around whisper.cpp C API
- [x] Whisper model download (tiny.en 77MB / base.en 142MB)
- [x] On-device transcription pipeline (record → transcribe → store)
- [x] Text-only Quick Entry (type instead of record)
- [x] Text-only journal view (read past entries in HistoryView)
- [x] Push notification for daily journal reminder (NotificationService)
- [x] 7-day streak tracking in UI (StreakCard, currentStreak)
- [x] Streak notifications at milestones (1/3/7/14/21/30 days)
- [x] Daily reminder time picker in Settings

## Phase 2: Voice Biomarkers (Days 15-21) ✓ COMPLETED

### Week 3 Deliverables ✓
- [x] Audio preprocessing: normalize, trim silence, split into frames
- [x] FFT + autocorrelation hybrid pitch extraction (60-450Hz)
- [x] Silence/hesitation detection algorithm
- [x] Speech rate calculation (voiced frame ratio)
- [x] Vocal energy computation (RMS amplitude via Accelerate vDSP)
- [x] Micro-breath detection (200-800Hz band energy)
- [x] Jitter & shimmer computation (cycle-to-cycle variation)

### Week 4 Deliverables ✓
- [x] All biomarker extraction integrated into post-recording pipeline
- [x] Per-entry biomarker visualization (bar chart in EntryDetailView)
- [x] Trend charts (7-day, 30-day rolling averages in InsightsView)
- [x] Baseline establishment algorithm (rolling median, percentile distribution)
- [x] Anomaly detection (z-score ±2σ deviation from baseline)

## Phase 3: Content Intelligence (Days 22-35) ✓ COMPLETED

### Week 5-6 Deliverables
- [x] ONNXRuntime SPM dependency (onnxruntime-swift v1.20.0)
- [x] Phi-3-mini on-device (Q4 quantized ONNX + BPE tokenizer via merge rules)
- [x] Topic extraction pipeline (Phi-3 → NL tagger fallback)
- [x] Sentiment scoring per topic (Phi-3 classify → heuristic keyword fallback)
- [x] emotion2vec ONNX inference pipeline (MFCC extraction + ORT session)
- [x] Entity extraction (people, places, organizations via NL tagger + Phi-3)
- [x] Topic trend visualization (frequency bar chart + sentiment sparkline in InsightsView)
- [x] TopicTrendService (7d/30d sentiment slope, mention count, trend direction)
- [x] TopicTrendRow + TopicSparkline UI components

## Phase 4: Pattern Engine (Days 36-49) ✓ COMPLETED

### Week 7-8 Deliverables
- [x] Pattern Detection Service (custom Swift rules engine)
- [x] Broken promise detector
- [x] Topic avoidance detector
- [x] Sentiment decline detector
- [x] Goal abandonment detector (individual + cycle detection)
- [x] Contradiction detector
- [x] Cognitive shift detector (speech biomarker baselines)
- [x] Relationship pattern detector
- [x] Decision outcome tracker (DecisionOutcomeService — scan, follow-up, regret detection)
- [x] Decision DB table (v5 migration with StorageService save/load)
- [x] Decision regret pattern detector (wired into PatternDetectionService)
- [x] Daily insight notification system (DailyInsightService — 8 generators, morning push)
- [x] Daily insight settings (toggle + time picker in SettingsView)
- [x] PatternCardView updated for decisionRegret icon/color

## Phase 5: Longitudinal Model (Days 50-70) ✓ COMPLETED

### Month 3 Deliverables
- [x] 30-day finalized baseline (decay-weighted, stability score, daily pattern detection, maturity check)
- [x] Cognitive drift detection (Cohen's d effect size, early-vs-late window comparison, gradual/sudden/mixed classification, emotion correlation)
- [x] Behavior prediction model (6 predictors: journal frequency, sentiment trajectory, goal completion, next emotion, abandonment risk, emotional crisis risk)
- [x] Relationship pattern analysis (entity-sentiment correlation, volatility detection — in PatternDetectionService.detectRelationshipPatterns)
- [x] Personalized insight delivery (engagement tracking per type, streak-phase adaptive sensitivity, ranking with personalization boost)
- [x] End-to-end encrypted cloud backup (CloudKit + AES-GCM + PBKDF2, v2 payload with decisions, auto-scheduling, metadata, restore with fallback)
- [x] Export functionality (JSON, CSV, Text — includes decisions, statistics summary, all biomarkers and emotion data)
- [x] Baseline cache + predictions cache DB tables (migration v6)

## Phase 6: Monetization + Launch (Days 71-90) ✓ COMPLETED

### Month 4 Deliverables
- [x] StoreKit subscription integration (Product purchase, restore, entitlement check, transaction listener)
- [x] Free tier (7 entries only, tracked in SubscriptionService.canRecord)
- [x] Monthly subscription ($9.99 StoreKit + Stripe web)
- [x] Annual subscription ($79.99 StoreKit + Stripe web)
- [x] Subscription management UI (SubscriptionView with pricing cards, restore, web fallback)
- [x] Stripe subscription integration (StripeService.swift — checkout session, customer portal, webhook handler, backend Cloud Function template)
- [x] Custom URL scheme (voiceself:// for Stripe callback in AppDelegate)
- [x] App Store listing metadata (AppStore/metadata.json — description, keywords, screenshots, categories)
- [x] Privacy policy (docs/PRIVACY_POLICY.md — on-device processing, encryption, iCloud, Stripe)
- [x] Terms of service (docs/TERMS_OF_SERVICE.md — subscriptions, liability, medical disclaimer)
- [ ] Launch on Product Hunt (marketing activity — requires post-launch execution)
- [ ] Launch on Hacker News (marketing activity — requires post-launch execution)
- [ ] TikTok/IG content strategy (marketing activity — requires post-launch execution)

## Phase 7: Market Readiness & Post-Launch ✓ COMPLETED

### Month 5+ Deliverables
- [x] **Processing Pipeline Coordinator** (ProcessingPipelineService — full processing chain: transcribe → biomarkers → ML emotion → topics → patterns → decisions → encrypt → save; retry support for failed stages)
- [x] **Error Recovery Service** (ErrorRecoveryService — retries failed entries, recovers stuck processing, database integrity check, model verification)
- [x] **Therapist Sharing** (TherapistShareService — generates therapeutic summary with emotion distribution, topics, patterns, cognitive drift, behavioral notes, recommendations)
- [x] **Haptic Feedback** (HapticManager — record start/stop haptics, success/error/warning feedback, processing complete)
- [x] **Rate App Prompt** (RateAppPrompt — prompts after 5+ entries with streak/positive sentiment signal, 90-day cooldown)
- [x] **Family Plan** (Stripe + StoreKit family sharing support in SubscriptionView, SubscriptionPlan.family, project.yml family sharing entitlement)
- [x] **Enhanced Onboarding** (5-page flow with microphone permission, notification permission, model download progress, free trial explanation)
- [x] **Enhanced Entry Detail** (therapist share menu, copy-to-clipboard)
- [x] **Enhanced History** (pull-to-refresh, swipe-to-delete, processing status indicators)
- [x] **Launch Screen Configuration** (project.yml UILaunchScreen)
- [x] **App Store Metadata** (AppStore/metadata.json with 20 keywords, 3 languages, screenshot templates, review notes)
- [x] **Privacy Policy + Terms of Service** (docs/PRIVACY_POLICY.md, docs/TERMS_OF_SERVICE.md)
- [x] **Stripe Backend** (backend/StripeWebhook.js — checkout, verify, customer portal, webhook handler)

### Remaining (Separate Projects — Not Built Here)
- [ ] Android app (React Native) — separate codebase
- [ ] Web dashboard — separate web app
- [ ] API for researchers — requires backend infrastructure
- [ ] Product Hunt launch — marketing activity
- [ ] Hacker News launch — marketing activity
- [ ] TikTok/IG content strategy — marketing activity
