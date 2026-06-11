# Soulo Privacy Policy

**Last Updated:** June 10, 2026

## Our Commitment to Privacy

Soulo is built on a fundamental belief: your private thoughts should stay private. We designed Soulo so that everything happens on your device. This policy explains what data we collect, how it's used, and your rights.

## 1. Data We Collect

### 1.1 Data That Never Leaves Your Device
The following data is processed entirely on your iPhone and is never transmitted to our servers:

- **Audio recordings** of your journal entries
- **Transcriptions** generated from your recordings
- **Voice biomarkers** computed from your speech (speech rate, pitch, energy, hesitations, jitter, shimmer, micro-breaths)
- **Emotional state analysis** derived from your voice
- **Topic analysis** and entity extraction from your transcripts
- **Behavioral patterns** detected by our pattern engine
- **Subscription status** and purchase history

### 1.2 Data Stored in iCloud (Optional)
If you enable iCloud Backup:

- Your encrypted journal data (entries, patterns, decisions) is stored in your personal iCloud account
- This data is end-to-end encrypted — we cannot read it
- Backups are protected by your iCloud credentials and a passphrase you provide
- You can disable iCloud Backup at any time in Settings

### 1.3 Data That May Be Transmitted
When you use the optional Stripe subscription service:

- A checkout session request is sent to our payment processor (Stripe)
- Stripe receives your email (if provided) and payment information
- Stripe's privacy policy applies to that transaction
- We do not receive or store your payment details

## 2. How We Use Your Data

Since almost all processing happens on-device, we use your data solely to:

- Transcribe your voice recordings
- Analyze speech biomarkers and emotional state
- Detect behavioral patterns
- Generate personalized insights
- Provide subscription management through StoreKit or Stripe

## 3. Data Storage and Security

### 3.1 Local Storage
- All journal data is stored in an encrypted SQLite database
- Audio recordings are encrypted using AES-GCM-256
- Encryption keys are stored in the device Secure Enclave
- Database file is protected with iOS file protection (complete protection until first authentication)

### 3.2 Encryption Standards
- Audio: AES-GCM-256 with per-file random nonces
- Backup: AES-GCM-256 with PBKDF2 key derivation (100,000 iterations)
- Database: SQLCipher (AES-256-CBC)
- Keychain: iOS Secure Enclave

## 4. Third-Party Services

### 4.1 Apple StoreKit
Subscription purchases through the App Store are handled by Apple. Apple's privacy policy applies to payment processing.

### 4.2 Stripe (Optional)
Web-based subscription payments are processed by Stripe. When you choose to subscribe via our website:

- A checkout session is created with Stripe
- Stripe receives your email and payment information
- Stripe's privacy policy (https://stripe.com/privacy) governs that transaction

### 4.3 CloudKit (Optional)
If enabled, encrypted backups are stored in your personal iCloud account. Apple's privacy policy applies.

## 5. Data Retention and Deletion

- All data remains on your device until you delete it
- You can delete individual entries or all data at any time via Settings
- Deleting the app removes all local data
- iCloud backups can be deleted from iCloud settings

## 6. Your Rights

- **Access:** All your data is accessible within the app
- **Export:** Export your data as JSON, CSV, or text anytime
- **Deletion:** Delete individual entries or all data from Settings
- **Portability:** Export formats are standard and machine-readable

## 7. Children's Privacy

Soulo is not intended for users under 13. We do not knowingly collect data from children.

## 8. Changes to This Policy

We will notify you of material changes through the app. Continued use after changes constitutes acceptance.

## 9. Contact

For privacy questions:
- Email: privacy@voiceself.app
- Website: https://voiceself.app/privacy

---

*Soulo — Built for privacy, designed for self-discovery.*
