# Soulo — Data Recovery & Backup Strategy

## 1. Backup Options

| Method | What's Backed Up | Encryption | Automatic | Restore |
|---|---|---|---|---|
| **iCloud Backup** | Full encrypted database | User's iCloud key (E2EE) | Optional (weekly) | Full restore |
| **Manual Export** | JSON (all data, audio optional) | User's passphrase | No | Import on new device |
| **Auto-backup** | Encrypted blob to iCloud | User-generated passphrase | Weekly | Full restore |

## 2. iCloud Backup Implementation

```swift
class BackupService {
    private let container: CKContainer
    private let database: CKDatabase
    
    init() {
        container = CKContainer(identifier: "iCloud.com.voiceself")
        database = container.privateCloudDatabase  // User's private DB
    }
    
    func performBackup(password: String) async throws {
        // 1. Export database to encrypted blob
        let blob = try DatabaseExporter.exportEncrypted(password: password)
        
        // 2. Save to iCloud private database
        let record = CKRecord(recordType: "Backup")
        record["blob"] = CKAsset(fileURL: blob.url)
        record["version"] = 1
        record["createdAt"] = Date()
        
        try await database.save(record)
        
        // 3. Delete local temp file
        try FileManager.default.removeItem(at: blob.url)
    }
    
    func restoreFromBackup(password: String) async throws {
        // 1. Fetch latest backup from iCloud
        let query = CKQuery(recordType: "Backup", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        query.resultsLimit = 1
        
        let result = try await database.records(matching: query)
        guard let record = result.matchResults.first?.1 else {
            throw BackupError.noBackupFound
        }
        
        let asset = try record.get().object(forKey: "blob") as! CKAsset
        
        // 2. Decrypt and import
        let restored = try DatabaseImporter.importEncrypted(from: asset.fileURL!, password: password)
        
        // 3. Verify integrity
        guard try DatabaseVerifier.verify(restored) else {
            throw BackupError.corruptedBackup
        }
        
        // 4. Replace current database
        try DatabaseManager.shared.replace(with: restored)
    }
}
```

## 3. Database Integrity Verification

```swift
class DatabaseVerifier {
    func verify() -> Bool {
        // Run SQLite integrity check
        let result = Database.shared.execute("PRAGMA integrity_check")
        guard result == "ok" else { return false }
        
        // Verify encryption
        let encrypted = Database.shared.execute("PRAGMA cipher_version")
        guard !encrypted.isEmpty else { return false }
        
        // Verify schema version
        let version = Database.shared.execute("SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1")
        guard version == expectedSchemaVersion else { return false }
        
        // Spot check: verify entries table has expected columns
        let columns = Database.shared.execute("PRAGMA table_info(entries)")
        let expectedColumns = ["id", "timestamp", "duration_ms", "transcript", "biomarkers_json"]
        for col in expectedColumns {
            guard columns.contains(col) else { return false }
        }
        
        return true
    }
    
    func repair() -> Bool {
        // 1. Try to recover what we can
        let recovered = Database.shared.execute("PRAGMA quick_check")
        
        // 2. Export readable data
        let exportPath = try? exportReadableData()
        
        // 3. Delete corrupted database
        Database.shared.close()
        try? FileManager.default.removeItem(at: databasePath)
        
        // 4. Create new database
        DatabaseMigrator.shared.applyMigrations()
        
        // 5. Import recovered data
        if let path = exportPath {
            try? importData(from: path)
        }
        
        return DatabaseVerifier().verify()
    }
}
```

## 4. Recovery Scenarios

### Scenario 1: App Crash During Recording

```
State: Recording in progress, app crashes
Impact: Current recording lost (max 3 min)
Recovery:
  1. App relaunches
  2. Detects incomplete recording file
  3. Checks file integrity
  4. If >=30s audio intact: prompts user to save partial entry
  5. If <30s or corrupted: discards silently
```

### Scenario 2: Database Corruption

```
State: SQLCipher detects corruption on read
Impact: Potential data loss
Recovery:
  1. Automatically: PRAGMA quick_check → repair
  2. If repair fails: restore from latest iCloud backup
  3. If no backup: export readable entries via recovery mode
  4. If export fails: notify user, offer to send debug logs
```

### Scenario 3: Model Download Corruption

```
State: Phi-3-mini model partially downloaded or corrupted
Impact: Topic extraction fails
Recovery:
  1. Verify model hash
  2. If mismatch: delete + re-download
  3. Offer fallback: server-side processing with encryption
```

### Scenario 4: Device Lost/Stolen

```
State: iPhone lost with unbacked-up data
Impact: All entries lost (by design — no server copy)
Recovery: None. This is the cost of privacy-first architecture.
Mitigation: Remind users weekly to enable backup.
```

### Scenario 5: iOS Upgrade Breaks Encryption

```
State: OS upgrade invalidates Secure Enclave key
Impact: Database inaccessible
Recovery:
  1. Prompt for iCloud backup restoration
  2. If no backup: data is permanently lost
```

## 5. Recovery UI Flows

```swift
struct RecoveryView: View {
    let recoveryType: RecoveryType
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: recoveryType.icon)
                .font(.system(size: 60))
            
            Text(recoveryType.title)
                .font(.title)
            
            Text(recoveryType.description)
                .foregroundColor(.secondary)
            
            if recoveryType == .databaseCorrupted {
                Button("Attempt Recovery") {
                    attemptDatabaseRepair()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Restore from Backup") {
                    showBackupRestore()
                }
                
                Button("Contact Support") {
                    openSupport()
                }
            }
            
            if recoveryType == .noBackup {
                Button("Enable Backup Now") {
                    enableBackup()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

enum RecoveryType {
    case crashDuringRecording
    case databaseCorrupted
    case modelCorrupted
    case noBackup
    case deviceTransfer
    
    var icon: String {
        switch self {
        case .crashDuringRecording: return "exclamationmark.triangle"
        case .databaseCorrupted: return "internaldrive"
        case .modelCorrupted: return "cpu"
        case .noBackup: return "icloud.slash"
        case .deviceTransfer: return "arrow.triangle.2.circlepath"
        }
    }
}
```

## 6. Backup Schedule

| Frequency | Trigger | Action |
|---|---|---|
| **First backup** | On setting enable | Immediate full backup |
| **Weekly** | App launch (if charging + Wi-Fi) | Incremental backup |
| **On significant change** | After 5+ new entries | Background backup |
| **Before OS update** | System notification | Prompt to backup |
| **Before app deletion** | System notification | Cannot intercept (iOS limitation) |

## 7. Backup Encryption

```swift
// User sets a passphrase (or uses iCloud keychain)
// Key derivation: PBKDF2-SHA256, 100K iterations
// Encryption: AES-256-GCM
// Auth: HMAC-SHA256

func encryptBackup(data: Data, passphrase: String) throws -> Data {
    // 1. Derive key
    let salt = generateRandomBytes(count: 32)
    let key = try PBKDF2.deriveKey(from: passphrase, salt: salt, iterations: 100_000)
    
    // 2. Encrypt
    let iv = generateRandomBytes(count: 12)  // GCM nonce
    let encrypted = try AES.GCM.seal(data, using: key, nonce: AES.GCM.Nonce(data: iv))
    
    // 3. Package with header
    var header = Data()
    header.append(Data([0x56, 0x53, 0x42, 0x4B]))  // "VSBK" magic bytes
    header.append(Data([0x01]))                       // Version 1
    header.append(salt)                               // 32 bytes
    header.append(iv)                                 // 12 bytes
    header.append(encrypted.ciphertext)
    header.append(encrypted.tag)                      // 16 bytes
    
    return header
}

func decryptBackup(data: Data, passphrase: String) throws -> Data {
    // Parse header, derive key, decrypt
}
```
