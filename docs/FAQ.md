# Soulo — Customer Support FAQ

## General

### What is Soulo?
Soulo is a private AI journal that analyzes your voice and words to detect patterns in your life. It runs entirely on your phone. Nothing you say ever leaves your device.

### How is this different from a regular journal?
A regular journal stores your words. Soulo analyzes them. It detects patterns you can't see because you're living them: broken promises, avoided topics, declining sentiment, goal abandonment cycles.

### How is this different from therapy?
Therapy is $150-300/hour with a human who sees you 1 hour/week. Soulo is $10/month with an AI that sees you every day, remembers everything you've said, and has zero bias or ego. They're complementary — not replacements.

## Privacy & Security

### Does Soulo upload my recordings anywhere?
No. All processing happens on your device. Your voice never leaves your phone. We have no servers to upload to.

### Can Soulo staff read my journal?
No. We cannot access your data because we don't collect it. Your journal exists only in an encrypted database on your phone.

### What if Apple or the government demands my data?
We have nothing to give them. Your data is encrypted with a key derived from your Face ID/Touch ID on your device. We don't have a copy.

### What happens if I lose my phone?
If you enabled iCloud backup (Settings → Backup), your encrypted journal is stored in your personal iCloud with end-to-end encryption. Restore it on a new phone using your Apple ID + passphrase.

If you didn't enable backup, your data is gone. This is the cost of true privacy.

## Technical

### Why does Soulo need to download 2.4GB on first launch?
The AI models that analyze your voice and text run on your phone. The biggest one (Phi-3-mini, 2.3GB) is what extracts topics and generates insights. This is a one-time download. Wi-Fi recommended.

### Can I use Soulo without the AI models?
Yes. You can record and playback without any models downloaded. Transcription, biomarkers, and analysis require the models.

### Why is transcription slow sometimes?
Whisper.cpp runs on your phone's Neural Engine. On an iPhone 14+, 3 minutes of audio takes ~5 seconds. On an iPhone 12, ~15 seconds. If your phone is processing other tasks, it may be slower.

### Will Soulo drain my battery?
A full cycle (record + transcribe + analyze) uses ~3-4% battery. We recommend recording when you have >30% battery.

### Does Soulo work offline?
Yes. Everything works offline. Internet is only needed for: initial model download, subscription verification, and optional iCloud backup.

## Subscription

### How much does Soulo cost?
- Monthly: $9.99
- Annual: $79.99 ($6.67/month)
- Family: $14.99/month (up to 5 users)

### Is there a free trial?
Yes. Free tier gives you 7 entries to try before subscribing.

### What happens if I cancel my subscription?
Your data remains on your device, encrypted and accessible. You can still view past entries. You cannot record new entries until you resubscribe.

### Can I share a subscription with my family?
The Family plan covers up to 5 users. Great for checking in on elderly parents.

## Features

### How long should my journal entries be?
3 minutes is ideal. Long enough to express yourself, short enough to do daily. You can record as little as 30 seconds or as long as 10 minutes.

### What if I don't know what to say?
Don't overthink it. Talk about your day. What happened, how you felt, what's on your mind. The analysis works better with natural speech than with structured answers.

### How long until Soulo knows me?
After 7 days: basic topics and sentiment trends visible.
After 30 days: patterns start emerging.
After 90 days: the model knows you well enough to predict behavior.
After 1 year: it's the most comprehensive record of your inner life in existence.

### The insights are uncomfortable. Is that normal?
Yes. That's the point. Soulo tells you what you need to hear, not what you want to hear. If an insight feels wrong, you can dismiss it. If it keeps coming back, it's probably right.

### Can I delete a specific entry?
Yes. Swipe left on any entry in History → Delete. The entry is permanently removed, including the audio file.

### Can I export my data?
Yes. Settings → Export. You get a JSON file with all your entries, transcripts, biomarkers, and patterns. Audio export is optional.

## Troubleshooting

### Recording doesn't start
- Check microphone permissions: Settings → Soulo → Microphone → Enable
- Restart the app
- Restart your phone

### Transcription fails
- Check if models are downloaded: Settings → Storage → AI Models
- Free up storage space (>500MB recommended)
- Try re-recording in a quieter environment

### App crashes
- Update to the latest version
- Restart your phone
- If persistent, contact support with the crash log (Settings → Share Debug Log)

### How do I contact support?
Email: support@voiceself.app
Response time: within 24 hours
