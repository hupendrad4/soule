# Soulo — Security Audit Checklist

## 1. Data-at-Rest Security

| Requirement | Status | Implementation |
|---|---|---|
| Database encrypted | ✅ | SQLCipher (AES-256-CBC) |
| Database key derivation | ✅ | PBKDF2 with 100K iterations |
| Database key storage | ✅ | Secure Enclave (iOS keychain, kSecAttrAccessibleWhenUnlockedThisDeviceOnly) |
| Audio file encryption | ✅ | AES-256-GCM per file, random key per file |
| Audio key storage | ✅ | Key wrapped with database key |
| Backup encryption | ✅ | User-provided passphrase + AES-256-GCM |
| Memory scrubbing | ✅ | Sensitive data zeroed after use |
| File protection class | ✅ | NSFileProtectionCompleteUntilFirstUserAuthentication |

## 2. Data-in-Transit Security

| Requirement | Status | Implementation |
|---|---|---|
| No voice data transmitted | ✅ | All processing on-device |
| No transcript data transmitted | ✅ | Never leaves device |
| No biomarker data transmitted | ✅ | Never leaves device |
| Model download | ✅ | HTTPS with certificate pinning (optional) |
| Subscription validation | ✅ | StoreKit (Apple's secure enclave) |
| iCloud backup | ✅ | End-to-end encrypted by Apple (user's key) |
| Analytics (anonymous) | ✅ | Aggregated, no PII, no device ID |

## 3. Application Security

| Requirement | Status | Implementation |
|---|---|---|
| Jailbreak detection | 🟡 Optional | Could add, not critical |
| Screenshot prevention | ✅ | Hides content in app switcher |
| Clipboard monitoring | ✅ | Never reads pasteboard |
| Background snapshot | ✅ | Blurs content in app switcher |
| Debugger detection | ✅ | `ptrace(PT_DENY_ATTACH, 0, 0, 0)` |
| Input validation | ✅ | All text inputs sanitized |
| SQL injection prevention | ✅ | Parameterized queries only |
| Memory corruption | ✅ | Swift (memory safe), no unsafe pointers |
| Third-party SDKs | ✅ | Minimal: StoreKit, Sign in with Apple only |

## 4. Cryptography

| Cipher | Use Case | Key Size | Mode |
|---|---|---|---|
| AES | Database + file encryption | 256-bit | CBC (SQLCipher) / GCM (audio files) |
| PBKDF2 | Key derivation from biometrics | — | 100,000 iterations |
| SHA-256 | Integrity checks | 256-bit | — |
| Secure Enclave | Key storage | 256-bit | Hardware-backed |

## 5. Privacy Verification (Pre-Launch)

- [ ] Network capture: Record 3 entries. Capture all network traffic. Verify no audio/transcript/biomarker data leaves device.
- [ ] File system audit: Search device for any file containing raw transcript text outside encrypted database.
- [ ] Memory dump: Attach debugger, dump app memory. Verify no decrypted data remains after object deallocation.
- [ ] iCloud backup: Enable backup, inspect backup contents. Verify no readable data.
- [ ] Crash log review: Verify crash logs contain no sensitive data.
- [ ] Analytics review: Verify anonymous analytics contain no PII, no device ID, no hashed identifiers.

## 6. Third-Party Audit Scope

```yaml
services:
  stripe:
    data_shared: subscription_status, app_user_id (anonymous UUID)
    encryption: HTTPS + Stripe SDK
    retention: subscription duration + 30 days
    
  sign_in_with_apple:
    data_shared: private_relay_email, user_identifier
    encryption: Apple's secure channel
    retention: managed by Apple
    
  icloud:
    data_shared: encrypted_blob (user-encrypted)
    encryption: User's key, Apple cannot read
    retention: User-managed
```

## 7. Vulnerability Mitigations

| Threat | Mitigation | Severity |
|---|---|---|
| Physical device access | Face ID/Touch ID + encrypted storage | High |
| Malicious app reading files | App sandbox + file protection class | High |
| Network interception | All on-device, no sensitive data transmitted | Critical |
| Side channel (screen recording) | Blur app switcher preview | Medium |
| Brute force database | PBKDF2 + Secure Enclave rate limiting | High |
| Model tampering | Code signature verification at load | Medium |
| Replay attack (subscription) | Receipt validation + StoreKit | High |

## 8. Security-First Architecture Decision Record

### ADR-1: No server-side processing
**Decision:** All ML processing on-device.
**Rationale:** Eliminates the largest security surface area. User trust is the product.
**Trade-off:** Limits to devices with sufficient RAM (iPhone 12+). 2.4GB model download.

### ADR-2: No email/password authentication
**Decision:** Sign in with Apple only.
**Rationale:** No password to leak. Private email relay. Apple handles MFA.
**Trade-off:** Android users need alternative (future).

### ADR-3: Raw audio deleted after transcription (opt-in)
**Decision:** Default: delete audio after processing complete. User can choose to keep.
**Rationale:** Audio is the most sensitive data. Transcribed text is sufficient for analysis.
**Trade-off:** Can't re-transcribe with improved model later.

### ADR-4: No analytics SDK
**Decision:** Custom anonymous analytics, no Firebase/Mixpanel/etc.
**Rationale:** Zero data shared with third parties.
**Trade-off:** No crash-free session tracking, no funnel analysis.
