# Soulo — UI/UX Design

## 1. Design Principles

- **Private**: Dark UI, muted colors, feels like a personal space
- **Honest**: Brutalist typography, no sugar-coating in the interface
- **Calm**: No animations, no gamification, no notifications that feel like social media
- **Minimal**: One action per screen. Record or Read. Nothing else.

## 2. Color System

```swift
// Core palette
let background = Color(hex: "#0D0D0D")      // Near-black
let surface = Color(hex: "#1A1A1A")         // Card background
let surfaceElevated = Color(hex: "#242424")  // Modal background
let primary = Color(hex: "#FFFFFF")          // Text
let secondary = Color(hex: "#808080")        // Subtle text
let accent = Color(hex: "#FF4444")           // Red — for uncomfortable truths
let accentPositive = Color(hex: "#44FF88")   // Green — for progress
let accentWarning = Color(hex: "#FFAA44")    // Amber — for warnings
let border = Color(hex: "#2A2A2A")          // Dividers
```

## 3. Typography

```swift
// System font, monospace for data, sans-serif for narrative
let titleFont = Font.system(size: 28, weight: .bold, design: .default)
let insightFont = Font.system(size: 17, weight: .regular, design: .serif)    // Insights feel like reading a letter
let dataFont = Font.system(size: 15, weight: .regular, design: .monospaced)  // Biomarker values
let bodyFont = Font.system(size: 17, weight: .regular, design: .default)
```

## 4. Screen Designs

### 4.1 Tab Bar
```
┌──────────────────────────────────────┐
│ [Record]  [History]  [Insights]  [Me] │
│    ●         ○          ○         ○   │
│   (icon)   (icon)    (icon)    (icon) │
└──────────────────────────────────────┘
```

### 4.2 Record Screen (Primary Screen)

```
┌──────────────────────────────────────┐
│                        Streak: 🔥 7  │
│                                      │
│                                      │
│          ┌──────────────┐            │
│          │              │            │
│          │    Waveform   │            │
│          │   ▁▃▂▅▇▆▄▃▁▂  │            │
│          │              │            │
│          └──────────────┘            │
│                                      │
│           ⏺ [Tap to Record]          │
│         "What's on your mind?"       │
│                                      │
│         Last entry: 18h ago          │
│                                      │
│    ┌──────────────────────────┐      │
│    │  Yesterday's top insight │      │
│    │ "You mentioned stress    │      │
│    │  3x this week. Up 50%."  │      │
│    └──────────────────────────┘      │
│                                      │
└──────────────────────────────────────┘
```

#### States:
- **Idle**: Large record button in center, gentle pulse animation
- **Recording**: Waveform animating, timer counting up, pause button
- **Processing**: "Transcribing..." → "Analyzing..." → "Finding patterns..."
- **Complete**: "Entry saved" for 2 seconds, then back to idle

### 4.3 Insights Screen (Where the Magic Lives)

```
┌──────────────────────────────────────┐
│ Back                           Filter │
│                                      │
│  Today's Truth                    ⚠️ │
│ ┌──────────────────────────────────┐ │
│ │ "You've mentioned 'I should call │ │
│ │  mom' 12 times in 30 days.      │ │
│ │  You haven't. This is your most │ │
│ │  repeated unresolved pattern."  │ │
│ │                                  │ │
│ │              — Soulo, Day 34 │ │
│ └──────────────────────────────────┘ │
│                                      │
│  This Week                        🔴 │
│ ┌──────────────────────────────────┐ │
│ │ Topic avoidance detected        │ │
│ │ Your energy drops 40% when you  │ │
│ │ talk about work. You've been    │ │
│ │ avoiding this for 6 days.       │ │
│ │                              ⬆ 60 │ │
│ └──────────────────────────────────┘ │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Broken promise                   │ │
│ │ "I'll start exercising" — day 1  │ │
│ │ "I'll start exercising" — day 14 │ │
│ │ "I'll start exercising" — day 30 │ │
│ │ Pattern: every 14 days          │ │
│ │                              ⬆ 45 │ │
│ └──────────────────────────────────┘ │
│                                      │
│  Trends                          📈 │
│ ┌──────────────────────────────────┐ │
│ │ Stress level                     │ │
│ │ ████████████░░░░ 68%             │ │
│ │ ↑ 15% from last month            │ │
│ │ Highest: Monday mornings         │ │
│ └──────────────────────────────────┘ │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Topics this month                │ │
│ │ Career: ██████████░░ 45% (-5%)   │ │
│ │ Family: ██████░░░░░░ 25% (+8%)   │ │
│ │ Health: ████░░░░░░░░ 15% (same)  │ │
│ │ Money:  ███░░░░░░░░░ 10% (+3%)   │ │
│ │ Other:  ██░░░░░░░░░░ 5% (-1%)    │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

### 4.4 History Screen

```
┌──────────────────────────────────────┐
│ Search "mom"                    🔍   │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Today                          • │ │
│ │ "Work was intense. My boss..."  ▸ │ │
│ │ 3 min   68% stress  2 topics    │ │
│ ├──────────────────────────────────┤ │
│ │ Yesterday                      • │ │
│ │ "I finally called mom. It was.." ▸ │ │
│ │ 4 min   42% stress  3 topics    │ │
│ ├──────────────────────────────────┤ │
│ │ 2 days ago                     • │ │
│ │ "I need to start exercising..."  ▸ │ │
│ │ 2 min   55% stress  1 topic     │ │
│ └──────────────────────────────────┘ │
│                                      │
│  Loading older entries...            │
└──────────────────────────────────────┘
```

### 4.5 Entry Detail View

```
┌──────────────────────────────────────┐
│ ← History               Delete      │
│                                      │
│  June 9, 2026 — 3:42 PM              │
│  3 min 12 sec                        │
│                                      │
│  ▶ [Play recording]                  │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ "Work was intense today. My boss │ │
│ │  dismissed my idea in the        │ │
│ │  meeting. I felt invisible. This │ │
│ │  is the third time this month    │ │
│ │  I've felt this way..."          │ │
│ │                                  │ │
│ │                    [Edit]        │ │
│ └──────────────────────────────────┘ │
│                                      │
│  Voice Analysis                      │
│ ┌──────────────────────────────────┐ │
│ │ Energy    ████████░░ 65%         │ │
│ │ Stress    ██████████ 78% ↑       │ │
│ │ Pitch     ██████░░░░ 55%         │ │
│ │ Speech    ████░░░░░░ 42% slower  │ │
│ └──────────────────────────────────┘ │
│                                      │
│  Emotional State                     │
│  Primary: Frustration (72%)          │
│  Secondary: Sadness (28%)            │
│                                      │
│  Topics                              │
│  Career frustration (negative)       │
│  Boss relationship (negative)        │
│  Feeling invisible (negative)        │
│                                      │
│  Connected Patterns                  │
│  → Sentiment declining over 3 months │
│  → Similar entry on Mar 12, 2026    │
│  → You set a goal about this 42d ago│
└──────────────────────────────────────┘
```

### 4.6 Onboarding Flow

```
Screen 1: "This is Soulo"
  "Talk for 3 minutes a day. 
   We'll listen. Really listen.
   We'll tell you what we find.
   Even if you don't want to hear it."

Screen 2: "Your data stays yours"
  "All processing happens on your phone.
   Your voice never leaves.
   We don't train on your data.
   This is a mirror, not a database."

Screen 3: "The hard truth"
  "Your friends won't tell you.
   Your therapist sees you 1h/week.
   We're here 24/7.
   We remember everything.
   We have no ego.
   We will tell you what you need to hear."

Screen 4: "Ready?"
  [Start your first recording]
  [Skip — I'll start later]
```

## 5. Microcopy Guidelines

| Context | Copy | Tone |
|---|---|---|
| Push notification | "It's been 18 hours. You mentioned 3 things you wanted to process yesterday." | Neutral, factual |
| Empty state | "No entries yet. Your future self is waiting." | Gentle, aspirational |
| Insight with positive trend | "You called mom 4 times this month. Up 300% from last month." | Matter-of-fact |
| Insight with negative trend | "Your stress is up 40%. You've done nothing about it. I'm contractually obligated to point this out." | Brutally honest |
| Recording prompt | "What's on your mind?" | Open, neutral |
| Subscription | "You spend $150/session on therapy. This is $9.99/month. You show up daily. Your therapist doesn't." | Value-driven |
| Deletion confirmation | "This entry will be permanently deleted. Are you sure?" | Neutral |

## 6. Interaction Patterns

- **Pull to refresh**: Triggers new pattern scan (not just data reload)
- **Swipe left on entry**: Delete (with confirmation)
- **Long press on insight**: Share as image card
- **Double tap on recording**: Quick 30-second entry (no full recording flow)
- **Haptic feedback**: On recording start/stop, on insight arrival
- **Dark mode only**: This is a private app. Light mode feels wrong.
