# Soulo — App Store Submission Guide

## 1. App Information

| Field | Value |
|---|---|
| **App Name** | Soulo |
| **Subtitle** | Your private AI journal |
| **Category** | Health & Fitness |
| **Secondary Category** | Productivity |
| **Age Rating** | 12+ (infrequent medical/treatment context) |
| **Price** | Free (in-app purchases) |
| **In-App Purchases** | Soulo Monthly ($9.99), Soulo Annual ($79.99), Soulo Family ($14.99) |

## 2. Metadata

### App Description (1700 chars max)

```
Soulo is the first AI that truly knows you.

Not a chatbot. Not a generic journal. A private AI that builds a complete model of you over time — your patterns, your contradictions, your promises to yourself, the topics you avoid.

HOW IT WORKS
Record 3 minutes a day. Speak naturally. No prompts. No structure. No judgment.

Your voice is analyzed on-device for biomarkers: stress, energy, speech rate, hesitation patterns. Your words are analyzed for topics, sentiment, contradictions. Over days, patterns emerge that you cannot see because you are inside them.

WHAT YOU GET
• Pattern Detection: "You've mentioned quitting 12 times. You haven't. Here's the cycle."
• Voice Biomarkers: Stress, energy, cognitive load — extracted from your voice, not self-reports
• Topic Tracking: What you talk about, how you feel about it, how it changes over time
• Daily Insights: One truth every day. Sometimes hard to hear. Always accurate.
• Cognitive Baseline: Your speech patterns as a personalized health signal

PRIVACY FIRST
• All processing on-device. Your voice never leaves your phone.
• Encrypted at rest with AES-256. Protected by Face ID.
• No account needed. Sign in with Apple uses private relay.
• No analytics SDKs. No data brokers. No tracking.
```

### Keywords (100 chars max)

```
journal,diary,mental health,wellness,self improvement,therapy,coaching,mood tracker,cognitive health,stress,anxiety,voice journal,AI journal,emotional intelligence,mindfulness,habits,goals,patterns,self awareness,personal growth
```

### Promotional Text (170 chars max)

```
The AI that knows you better than you know yourself. 3 minutes a day. 100% private. On-device.
```

### Support URL
```
https://voiceself.app/support
```

### Marketing URL
```
https://voiceself.app
```

### Privacy Policy URL
```
https://voiceself.app/privacy
```

## 3. Screenshots

### iPhone (6.7" — required)

| # | Screen | Copy |
|---|---|---|
| 1 | Record view (waveform animating) | "3 minutes a day. Just talk." |
| 2 | Insight card (pattern detected) | "It spots patterns you can't see." |
| 3 | Biomarker charts (stress trend) | "Your voice reveals your stress." |
| 4 | History view (entries list) | "Everything stored safely on your phone." |

### iPhone (5.5" — required)
Same screens, scaled.

### iPad (12.9") — optional
Same screens + landscape variant.

### App Preview (30-second video, optional)
Show: Person recording → waveform → processing → insight card appears
Narration: "3 minutes a day. Just talk. Soulo listens. Really listens."

## 4. Build Configuration

### Versioning

```
Version: 1.0.0  (major.minor.patch)
Build:   CI build number (auto-increment)

Major: Breaking changes or new pattern types
Minor: New features (new biomarker, new chart type)
Patch: Bug fixes, performance improvements
```

### Required Entitlements

- com.apple.developer.healthkit (Health integration, future)
- com.apple.developer.usernotifications (Daily reminders)
- com.apple.developer.networking.wifi-info (Offline detection)

### Info.plist Keys

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Soulo needs microphone access to record your daily journal entries. Recordings are processed on-device and never uploaded.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Soulo transcribes your journal entries to analyze topics and patterns. All transcription happens on your device.</string>
<key>NSFaceIDUsageDescription</key>
<string>Soulo uses Face ID to protect your private journal entries.</string>
<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>arm64</string>
    <string>microphone</string>
</array>
<key>FirebaseAnalyticsEnabled</key>
<false/>
```

## 5. App Store Review Notes

### Review Account
Provide a demo account with pre-seeded data:
- 7 days of journal entries
- At least 3 detected patterns
- Show insight cards populated

### Notes for Reviewer
```
This app processes all voice data on-device. No data is uploaded to any server.
The initial model download (~2.4GB) occurs on first launch via Wi-Fi.
Demo account has 7 pre-seeded entries to demonstrate pattern detection.
No login required. Sign in with Apple is optional (for subscription restore only).
```

### Potential Rejection Risks

| Risk | Mitigation |
|---|---|
| **Medical claims** | Do NOT claim to diagnose anything. "Cognitive baseline" is framed as speech pattern tracking, not medical diagnosis. Use "wellness" not "health" in marketing. |
| **Privacy concern** | All on-device processing with encryption is App Store best practice. Highlight in review notes. |
| **Model download size** | 2.4GB initial download requires Wi-Fi. Show alert before download. Allow deferral. |
| **Subscription clarity** | Clearly state renewal terms. 7-day free trial with confirmation. |

## 6. App Store Connect Checklist

- [ ] App name and subtitle set
- [ ] Primary and secondary category
- [ ] Age rating questionnaire completed
- [ ] Privacy policy URL
- [ ] Support URL
- [ ] Marketing URL (optional)
- [ ] All screenshot sizes uploaded
- [ ] App Preview video (optional)
- [ ] Version number set
- [ ] Build uploaded via Xcode/CI
- [ ] Export compliance (no encryption export restrictions — using standard AES)
- [ ] Content rights (all original content)
- [ ] Advertising identifier (None — IDFA not used)
- [ ] In-app purchases configured
- [ ] Review notes added
- [ ] Demo account details (if needed)
- [ ] Price tier selected
- [ ] Availability date set (or manual release)

## 7. Post-Submission Monitoring

| Metric | Tool | Alert |
|---|---|---|
| Crash rate | Xcode Organizer / Crashlytics (opt-in) | >0.1% crash rate |
| Rejection reason | App Store Connect | Any rejection |
| User reviews | App Store Connect | Negative trends |
| Subscription revenue | Stripe Dashboard | 20%+ drop |
