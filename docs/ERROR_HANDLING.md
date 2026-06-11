# Soulo — Error Handling & Recovery Strategy

## 1. Error Categories

| Category | Examples | Severity |
|---|---|---|
| **Recording** | Mic permission denied, audio encoding failed, disk full | High |
| **Transcription** | Whisper model not loaded, transcription failed, slow | High |
| **Biomarkers** | DSP computation failed, FFT error | Medium |
| **Content AI** | Phi-3 OOM, topic extraction timeout | Medium |
| **Storage** | Database corruption, write failure, encryption error | Critical |
| **Network** | Model download failed, subscription verification failed | Low |
| **Permissions** | Mic denied, notification denied, Face ID denied | Medium |
| **Background** | App killed during processing, background task expired | Medium |

## 2. Error Recovery Flows

### 2.1 Recording Error

```
User taps record
  ↓
AVAudioEngine starts
  ↓
❌ Audio format unsupported
  → Fallback to default format (16kHz, 16-bit, mono AAC)
  → Log warning, continue recording
  
❌ Microphone not available (another app using it)
  → Show alert: "Another app is using your microphone. Close it and try again."
  → Retry button
  
❌ Disk full during recording
  → Pause recording
  → Show alert: "Storage is full. Soulo needs 50MB free space."
  → Offer: Delete oldest entry OR cancel recording
  → If delete: remove oldest entry, resume recording
  
❌ App backgrounded during recording
  → If <30s recorded: discard entry, show "Recording discarded"
  → If >30s recorded: save partial entry, continue processing
```

### 2.2 Transcription Error

```
Recording complete → start transcription
  ↓
❌ Whisper model not loaded
  → Check if download is in progress
  → If downloading: show progress, queue transcription
  → If download failed: show retry, use fallback (server transcription with encryption)

❌ Transcription timeout (>30s for 3-min audio)
  → Show "Transcription is taking longer than expected"
  → Continue in background
  → Notify when complete

❌ Transcription returns empty
  → Could be silence or very quiet audio
  → Show "I couldn't hear anything. Try speaking louder or moving closer."
  → Offer to re-record

❌ Transcription partial (only 50% of expected length)
  → Save partial transcript
  → Flag entry for re-processing
  → Process biomarkers + emotion on partial data
```

### 2.3 Model Download Error

```
First launch → needs to download Phi-3-mini (2.3GB)
  ↓
❌ No internet connection
  → Show "Wi-Fi required for initial setup."
  → Queue download for when connected
  → Offer reduced functionality (recording only, no analysis)

❌ Download interrupted (app backgrounded)
  → Resume download on next foreground
  → Show progress: "42% downloaded. Keeping your phone awake helps."

❌ Download failed (server error)
  → Retry with exponential backoff (3 retries)
  → After 3 failures: show support contact

❌ Storage insufficient for model
  → Show "Soulo needs 3GB free space to download its AI models."
  → Show current storage usage
  → Offer to defer download (reduced functionality mode)
```

### 2.4 Storage/Encryption Error

```
❌ Database encryption key lost (Secure Enclave issue)
  → Cannot recover encrypted data (by design)
  → Show "Your journal data could not be decrypted. This can happen after a OS restore."
  → Offer: Reset app (all data lost) OR restore from backup

❌ Database write failure
  → Retry 3 times with backoff
  → If persistent: show "Could not save your entry. Your entry may be lost."
  → Save entry to temporary file for recovery

❌ Database corruption detected
  → Run integrity check
  → If corrupted: restore from last backup OR export readable data
  → Show "Your journal database was corrupted. We restored what we could."
  → Log full details for debugging

❌ Audio file encryption failure
  → Audio file may be recoverable but unencrypted
  → Encrypt immediately or delete
  → Log security event
```

### 2.5 Pattern Engine Error

```
❌ Pattern scan takes too long (>5s)
  → Run scan in background with priority queue
  → Show cached patterns immediately
  → Update when scan completes

❌ Pattern engine OOM (processing 1000+ entries)
  → Batch process: 100 entries at a time
  → Show "Analyzing your history..." with progress
  → Cache results

❌ Contradiction detection false positive
  → Pattern has confidence score
  → Only surface patterns above 70% confidence
  → User can dismiss patterns → engine learns
```

## 3. Graceful Degradation

| Scenario | Degraded Mode | Recovery |
|---|---|---|
| No AI models downloaded | Record + playback only | Download models when on Wi-Fi |
| Low memory (<500MB free) | Skip topic extraction, biomarkers only | Free memory, retry |
| Low battery (<20%) | Skip background processing | Process next charge |
| iCloud unavailable | No backup | Retry hourly |
| Stripe unavailable | Restore from local receipt | Retry on next launch |
| Old iOS version (<17) | Core features only | Prompt to update |

## 4. User-Facing Error Messages

| Error | Message | Action |
|---|---|---|
| Mic denied | "Microphone access is required for voice journaling. Enable it in Settings." | Open Settings button |
| Model download needed | "Soulo needs to download its AI brain. This happens once. Wi-Fi recommended (2.4GB)." | Download Now / Later |
| Processing timeout | "Analysis is taking a while. Your entry will be ready in a few minutes." | Continue browsing |
| Subscription expired | "Your subscription expired. Your data is safe. Subscribe to continue recording." | See Plans |
| Storage warning | "Your journal is using 80% of available storage. Consider exporting old entries." | Export / Manage |
| Critical error | "Something went wrong. Your data is encrypted and safe. Please restart the app." | Restart App |
| Backup restore | "Restoring from backup... This may take a few minutes." | Progress bar |

## 5. Logging Strategy

```swift
enum LogLevel: String {
    case debug     // Development only, stripped from release
    case info      // Normal operations
    case warning   // Recoverable issues
    case error     // User-facing errors
    case fatal     // App crashes / data loss
}

struct LogEntry: Codable {
    let timestamp: Date
    let level: LogLevel
    let component: String    // recording, transcription, storage, etc.
    let message: String
    let details: [String: String]?  // contextual info
    let appVersion: String
    let deviceModel: String
    let osVersion: String
}

// Log storage
// Stored in encrypted SQLite, max 500 entries
// Oldest entries pruned when limit reached
// User must opt-in to share logs with developer

// Log levels per build
#if DEBUG
let minLogLevel = LogLevel.debug
#else
let minLogLevel = LogLevel.warning  // Only warnings+ in production
#endif
```

## 6. Crash Recovery

```swift
@main
struct SouloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    checkForCrashRecovery()
                }
        }
    }
    
    func checkForCrashRecovery() {
        let lastSessionCrashed = UserDefaults.standard.bool(forKey: "crashed_last_session")
        if lastSessionCrashed {
            // 1. Check database integrity
            Database.shared.runIntegrityCheck()
            
            // 2. Check for partial entries
            let partialEntries = EntryRepository.shared.findPartialEntries()
            if !partialEntries.isEmpty {
                // Attempt to recover
                RecoveryService.shared.attemptRecovery(of: partialEntries)
            }
            
            // 3. Mark session as recovered
            UserDefaults.standard.set(false, forKey: "crashed_last_session")
            
            // 4. Show recovery notification
            showRecoveryNotice(count: partialEntries.count)
        }
    }
}

// AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // Clear model caches
        ModelCache.shared.clear()
        
        // Abort background processing
        ProcessingQueue.shared.pause()
    }
    
    func applicationSignificantTimeChange(_ application: UIApplication) {
        // Timezone change detected — re-index entries
        EntryRepository.shared.reindexTimestamps()
    }
}
```
