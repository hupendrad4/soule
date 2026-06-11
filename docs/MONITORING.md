# Soulo — Monitoring & Analytics Plan

## 1. Philosophy

**Privacy-first analytics.** We collect no PII, no device IDs, no session IDs, no IP addresses. Everything is aggregated server-side with differential privacy.

Our analytics answer three questions:
1. Is the app crashing? → Crash-free rate
2. Are users engaging? → Retention, daily recording rate
3. Are we making money? → MRR, churn

## 2. What We Track (Anonymous)

### Engagement Metrics (Aggregated, No User IDs)

```swift
// Each metric is an integer count bucketed by hour
// No user identifier attached

struct AnalyticsEvent: Codable {
    let timestamp: Date         // Hour bucket (privacy: lossy timestamp)
    let event: EventType
    let value: Int              // Usually 1 (counter)
    let appVersion: String
}

enum EventType: String, Codable {
    // Recording
    case recordingStarted
    case recordingCompleted
    case recordingAbandoned      // Started but <30s
    case recordingDiscarded      // User deleted without processing
    
    // Processing
    case transcriptionCompleted
    case transcriptionFailed
    case biomarkersCompleted
    case biomarkersFailed
    case topicExtractionCompleted
    case topicExtractionFailed
    
    // Patterns
    case patternGenerated
    case patternDismissed
    case patternShared            // User shared an insight
    
    // Subscription
    case paywallViewed
    case subscriptionStarted
    case subscriptionCancelled
    case freeTierExhausted
    
    // Engagement
    case appLaunched
    case day7Retained             // Launched app on day 7
    case day30Retained
    case day90Retained
    case dailyEntryRecorded
    
    // Errors
    case crash
    case errorLowMemory
    case errorDiskFull
    case errorModelDownloadFailed
    case errorPermissionDenied
}
```

### Crash Reporting (Opt-In, Minimal)

```swift
// Only sent with user's explicit permission
struct CrashReport: Codable {
    let timestamp: Date
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let crashType: String          // signal, exception, OOM
    let stackTrace: String         // Symbolicated
    let lastEvents: [String]       // Last 10 actions before crash
}
```

## 3. What We NEVER Track

- ✅ No device ID (IDFV, IDFA)
- ✅ No user ID (no UUID associated with user)
- ✅ No email address
- ✅ No IP address storage
- ✅ No session tracking
- ✅ No behavioral profiling across sessions
- ✅ No location data
- ✅ No content analysis (topics, sentiment, biomarkers — these NEVER leave device)

## 4. Dashboard Metrics (Aggregate)

```sql
-- Server-side aggregate table (one row per day)
CREATE TABLE daily_metrics (
    date TEXT PRIMARY KEY,           -- YYYY-MM-DD
    active_users INTEGER,            -- Opened app (total count)
    entries_recorded INTEGER,        -- Total entries (privacy: count only)
    avg_recording_duration REAL,     -- Average seconds
    completion_rate REAL,            -- Completed / Started
    subscription_starts INTEGER,
    subscription_cancels INTEGER,
    mrr_cents INTEGER,               -- Monthly recurring revenue in cents
    crash_free_rate REAL,            -- % of sessions without crash
    paywall_views INTEGER,
    paywall_conversion REAL
);
```

## 5. Health Dashboards

### Developer Dashboard (In-App, Your Device Only)

```swift
struct HealthDashboard: View {
    var body: some View {
        List {
            Section("Today") {
                MetricRow("Entries today", value: "\(todayCount)")
                MetricRow("Avg duration", value: String(format: "%.1f min", avgDuration))
                MetricRow("Crash-free rate", value: "\(crashFreeRate)%")
            }
            Section("This Week") {
                MetricRow("Streak", value: "\(streak) days")
                MetricRow("Retention (D7)", value: "\(d7Retention)%")
                MetricRow("Model downloads", value: modelDownloadStatus)
            }
            Section("Business") {
                MetricRow("MRR", value: "$\(mrr)")
                MetricRow("Paid users", value: "\(paidUsers)")
                MetricRow("Churn rate", value: "\(churnRate)%")
            }
        }
    }
}
```

## 6. Crash Monitoring

### Severity Tiers

| Severity | Criteria | Response |
|---|---|---|
| **Critical** | Crash rate >0.5% | Rollback release |
| **High** | Crash rate >0.1% or data loss | Patch within 24h |
| **Medium** | Non-fatal error affecting >5% of users | Fix in next release |
| **Low** | Individual crashes, no pattern | Log for next release |

### Common Crash Patterns to Monitor

- OOM during Phi-3 inference (device-specific)
- Database encryption key loss (OS update edge case)
- Audio file corruption (interrupted write)
- Model download corruption (partial download)

## 7. Alert Thresholds

| Alert | Trigger | Action |
|---|---|---|
| Crash rate spike | >0.2% in 1 hour | Investigate immediately |
| Transcription failure rate | >10% of entries | Check model integrity |
| Subscription churn spike | >10% in 1 day | Check paywall / pricing |
| Low D7 retention | <30% | Re-evaluate onboarding |
| Negative rating trend | <3 stars in last 10 reviews | Respond to each review |
