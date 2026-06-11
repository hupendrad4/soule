# Soulo

The first AI that truly knows you.

*Soulo is a private AI voice journal that runs entirely on your iPhone. Record 3 minutes a day. It analyzes your voice and words to detect patterns you can't see — broken promises, avoided topics, declining sentiment, goal abandonment cycles.*

*An Android version is also available in `android/` — built with Kotlin + Jetpack Compose.*

**100% on-device. Your voice never leaves your phone.**

## Project Structure

```
Soulo/
├── android/                # Android app (Kotlin + Jetpack Compose)
├── Soulo/                  # iOS app (SwiftUI)
├── docs/
│   ├── PRD.md                      # Product Requirements Document
│   ├── TECHNICAL_ARCHITECTURE.md   # iOS architecture, services, data flow
│   ├── DATABASE_SCHEMA.md          # Full SQLite schema (17 tables)
│   ├── MODEL_INTEGRATION_GUIDE.md  # Whisper, Phi-3, emotion2vec integration
│   ├── UI_DESIGN.md                # Wireframes, colors, microcopy
│   ├── MILESTONES.md               # 7 milestones, Day 1-90
│   ├── PLAN_OF_ACTION.md           # Week-by-week task checklist
│   ├── BUSINESS_MODEL.md           # Pricing, unit economics, GTM
│   ├── TESTING_STRATEGY.md         # Unit, integration, performance, beta
│   ├── ERROR_HANDLING.md           # Error recovery, graceful degradation
│   ├── PERFORMANCE_BUDGET.md       # Memory, battery, storage, network limits
│   ├── SECURITY_AUDIT.md           # Encryption, data flow, threat model
│   ├── PRIVACY_POLICY.md           # Legal document for App Store
│   ├── APP_STORE_SUBMISSION.md     # Metadata, screenshots, review notes
│   ├── FAQ.md                      # Customer support FAQ
│   ├── CI_CD.md                    # GitHub Actions, TestFlight, release
│   ├── MONITORING.md               # Analytics (privacy-first), crash tracking
│   └── DATA_RECOVERY.md            # Backup, restore, corruption handling
└── README.md
```

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift |
| UI Framework | SwiftUI (iOS 17+) |
| Audio | AVAudioEngine |
| Encryption | CryptoKit + SQLCipher |
| Speech-to-Text | Whisper.cpp (on-device) |
| Text Analysis | Phi-3-mini (on-device) |
| Voice Emotion | emotion2vec (on-device) |
| Database | SQLite + SQLCipher |
| Payments | StoreKit + Stripe |
| Auth | Sign in with Apple |
| Backup | CloudKit (E2EE) |
| CI/CD | GitHub Actions |

## Key Numbers

- **~3,200 lines of custom Swift code** (app + DSP + pattern engine)
- **~105 lines of ML integration code** (4 open-source models)
- **17 database tables** with full migration system
- **2.4GB model download** (one-time, Wi-Fi recommended)
- **3-4% battery** per daily recording cycle
- **$9.99/month** or **$79.99/year**

## Core Architecture

```
┌─────────────┐  ┌──────────────┐  ┌──────────────┐
│  Recording   │──│  Whisper.cpp  │──│  Biomarkers   │
│  Engine      │  │  (STT)       │  │  (DSP)       │
└─────────────┘  └──────────────┘  └──────────────┘
                        │                  │
                        ▼                  ▼
                 ┌──────────────┐  ┌──────────────┐
                 │  Phi-3-mini  │  │  emotion2vec │
                 │  (Topics)    │  │  (Emotion)   │
                 └──────────────┘  └──────────────┘
                        │                  │
                        ▼                  ▼
                 ┌─────────────────────────────┐
                 │       Pattern Engine         │
                 │  (Custom Swift, rules-based) │
                 └─────────────────────────────┘
```

## Getting Started (Building)

```bash
# 1. Clone
git clone https://github.com/yourusername/Soulo.git
cd Soulo

# 2. Open in Xcode
open Soulo.xcodeproj

# 3. Download ML models (run this script)
./Scripts/download_models.sh

# 4. Build & Run (iOS 17+, iPhone 12+)
# Select target → Run
```

## License

Private. All rights reserved.
