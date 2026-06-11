package com.soulo.app.services

import com.soulo.app.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

class ProcessingPipelineService(private val storage: StorageService) {
    private val transcriptionService = TranscriptionService()
    private val biomarkerService = BiomarkerService()
    private val onnx = OnnxService()

    sealed class Stage(val name: String) {
        data object Transcribe : Stage("transcribe")
        data object Biomarkers : Stage("biomarkers")
        data object Emotion : Stage("emotion")
        data object Topics : Stage("topics")
        data object Patterns : Stage("patterns")
        data object Decisions : Stage("decisions")
        data object Encrypt : Stage("encrypt")
        data object Save : Stage("save")
    }

    data class Progress(
        val stage: Stage,
        val progress: Float = 0f,
        val failed: Boolean = false,
        val error: String? = null
    )

    private var onProgress: ((Progress) -> Unit)? = null

    fun setOnProgress(listener: (Progress) -> Unit) {
        onProgress = listener
    }

    suspend fun process(entry: JournalEntry): JournalEntry = withContext(Dispatchers.Default) {
        var current = entry
        ErrorRecoveryService.saveRecoveryState(
            ErrorRecoveryService.RecoveryState("start", entry.audioFile, 0, 0)
        )

        // Stage 1: Transcribe
        onProgress?.invoke(Progress(Stage.Transcribe, 0.1f))
        if (current.transcriptStatus != ProcessingStatus.completed) {
            current = transcribeWithRetry(current)
        }

        // Stage 2: Biomarkers
        onProgress?.invoke(Progress(Stage.Biomarkers, 0.25f))
        if (current.biomarkersStatus != ProcessingStatus.completed) {
            current = analyzeBiomarkersWithRetry(current)
        }

        // Stage 3: Emotion (emotion2vec ONNX + heuristic fallback)
        onProgress?.invoke(Progress(Stage.Emotion, 0.45f))
        if (current.emotionStatus != ProcessingStatus.completed) {
            current = detectEmotion(current)
        }

        // Stage 4: Topics (Phi-3-mini ONNX + keyword fallback)
        onProgress?.invoke(Progress(Stage.Topics, 0.6f))
        if (current.topicsStatus != ProcessingStatus.completed) {
            current = analyzeTopics(current)
        }

        // Stage 5: Patterns
        onProgress?.invoke(Progress(Stage.Patterns, 0.75f))
        current = detectPatterns(current)

        // Stage 6: Decisions
        onProgress?.invoke(Progress(Stage.Decisions, 0.85f))
        current = detectDecisions(current)

        // Stage 7: Encrypt (AES-GCM via EncryptedFile)
        onProgress?.invoke(Progress(Stage.Encrypt, 0.95f))
        current = encrypt(current)

        // Stage 8: Save
        onProgress?.invoke(Progress(Stage.Save, 1.0f))
        saveToStorage(current)

        // Clean recovery state on success
        ErrorRecoveryService.clearRecoveryState()
        ErrorRecoveryService.cleanupOldBackups()

        onProgress?.invoke(Progress(Stage.Save, 1.0f))
        current
    }

    private suspend fun transcribeWithRetry(entry: JournalEntry, attempts: Int = 3): JournalEntry {
        for (i in 0 until attempts) {
            try {
                val audioFile = entry.audioFile?.let { File(it) }
                if (audioFile == null || !audioFile.exists()) {
                    return entry.copy(transcriptStatus = ProcessingStatus.completed)
                }
                val pcmData = readPcmFromWav(audioFile)
                val text = transcriptionService.transcribe(audioFile, pcmData)
                return entry.copy(
                    transcript = text.ifEmpty { null },
                    transcriptStatus = ProcessingStatus.completed
                )
            } catch (e: Exception) {
                ErrorRecoveryService.saveRecoveryState(
                    ErrorRecoveryService.RecoveryState("transcription", entry.audioFile, i * 33, 0, i + 1)
                )
                if (i == attempts - 1) {
                    return entry.copy(transcriptStatus = ProcessingStatus.failed)
                }
                delay(1000L * (i + 1))
            }
        }
        return entry.copy(transcriptStatus = ProcessingStatus.failed)
    }

    private suspend fun analyzeBiomarkersWithRetry(entry: JournalEntry, attempts: Int = 3): JournalEntry {
        for (i in 0 until attempts) {
            try {
                val audioFile = entry.audioFile?.let { File(it) }
                if (audioFile == null || !audioFile.exists()) {
                    return entry.copy(biomarkersStatus = ProcessingStatus.completed)
                }
                val pcmData = readPcmFromWav(audioFile)
                val biomarkers = biomarkerService.analyze(audioFile, pcmData)
                return entry.copy(
                    biomarkers = biomarkers,
                    biomarkersStatus = ProcessingStatus.completed
                )
            } catch (e: Exception) {
                ErrorRecoveryService.saveRecoveryState(
                    ErrorRecoveryService.RecoveryState("biomarkers", entry.audioFile, 100, 0, i + 1)
                )
                if (i == attempts - 1) {
                    return entry.copy(biomarkersStatus = ProcessingStatus.failed)
                }
                delay(1000L * (i + 1))
            }
        }
        return entry.copy(biomarkersStatus = ProcessingStatus.failed)
    }

    private suspend fun detectEmotion(entry: JournalEntry): JournalEntry {
        val emotion: EmotionalState
        try {
            ErrorRecoveryService.saveRecoveryState(
                ErrorRecoveryService.RecoveryState("emotion", entry.audioFile, 100, 0)
            )
            // Try emotion2vec ONNX first
            if (onnx.isModelAvailable(OnnxModel.Emotion2Vec)) {
                val pcmData = entry.audioFile?.let { File(it) }?.let { readPcmFromWav(it) }
                if (pcmData != null) {
                    onnx.loadModel(OnnxModel.Emotion2Vec)
                    val mel = EmotionDetectionService.computeMelSpectrogram(pcmData)
                    val probs = onnx.runEmotion2vec(mel, mel.size / 64)
                    if (probs != null && probs.isNotEmpty()) {
                        val decoded = onnx.decodeEmotion(probs)
                        val top = decoded.entries.first()
                        val valence = EmotionDetectionService.computeValence(decoded, entry.biomarkers)
                        val arousal = EmotionDetectionService.computeArousal(decoded, entry.biomarkers)
                        emotion = EmotionalState(
                            id = UUID.randomUUID().toString(),
                            primaryEmotion = mapToEmotionType(top.key),
                            confidence = top.value.toDouble().coerceIn(0.0, 1.0),
                            valence = valence,
                            arousal = arousal,
                            secondaryEmotions = decoded.entries.drop(1).take(3).map { mapToEmotionType(it.key) },
                            detectedAt = System.currentTimeMillis() / 1000
                        )
                        return entry.copy(emotion = emotion, emotionStatus = ProcessingStatus.completed)
                    }
                }
            }
            // Heuristic fallback
            emotion = if (entry.biomarkers != null) {
                heuristicEmotion(entry.biomarkers)
            } else {
                EmotionalState(
                    id = UUID.randomUUID().toString(),
                    primaryEmotion = EmotionType.neutral,
                    confidence = 0.3,
                    valence = 0.0,
                    arousal = 0.5,
                    detectedAt = System.currentTimeMillis() / 1000
                )
            }
        } catch (e: Exception) {
            return entry.copy(emotionStatus = ProcessingStatus.failed)
        }
        return entry.copy(emotion = emotion, emotionStatus = ProcessingStatus.completed)
    }

    private suspend fun analyzeTopics(entry: JournalEntry): JournalEntry {
        val text = entry.transcript ?: return entry.copy(topicsStatus = ProcessingStatus.completed)
        if (text.isBlank()) return entry.copy(topicsStatus = ProcessingStatus.completed)

        try {
            // Try Phi-3-mini ONNX first
            if (onnx.isModelAvailable(OnnxModel.Phi3Mini)) {
                val result = Phi3Service.analyzeTopics(text)
                if (result.success) {
                    // Parse Phi-3 output as topic, sentiment pairs
                    val topics = parsePhi3Topics(result.text, text)
                    if (topics.isNotEmpty()) {
                        return entry.copy(topics = topics, topicsStatus = ProcessingStatus.completed)
                    }
                }
            }
        } catch (_: Exception) {}

        // Keyword fallback
        val topics = extractTopics(text)
        return entry.copy(topics = topics, topicsStatus = ProcessingStatus.completed)
    }

    private fun heuristicEmotion(b: VoiceBiomarkers): EmotionalState {
        val (primary, valence, arousal) = when {
            b.vocalEnergy > 0.7 && b.speechRate > 4.0 ->
                Triple(EmotionType.excitement, 0.7, 0.8)
            b.vocalEnergy < 0.3 && b.speechRate < 2.0 ->
                Triple(EmotionType.sadness, -0.6, 0.3)
            b.pitchInstability > 0.4 && b.speechRate > 4.5 ->
                Triple(EmotionType.anxiety, -0.4, 0.8)
            b.vocalEnergy > 0.6 && b.hesitationRate < 0.1 ->
                Triple(EmotionType.joy, 0.7, 0.6)
            b.jitter > 0.3 && b.shimmer > 0.3 ->
                Triple(EmotionType.frustration, -0.5, 0.7)
            b.speechRate < 1.5 && b.vocalEnergy < 0.2 ->
                Triple(EmotionType.fatigue, -0.3, 0.2)
            else -> Triple(EmotionType.neutral, 0.0, 0.5)
        }
        return EmotionalState(
            id = UUID.randomUUID().toString(),
            primaryEmotion = primary,
            confidence = 0.5,
            valence = valence,
            arousal = arousal,
            detectedAt = System.currentTimeMillis() / 1000
        )
    }

    private fun mapToEmotionType(label: String): EmotionType = when (label.lowercase().trim()) {
        "happy", "joy" -> EmotionType.joy
        "sad", "sadness" -> EmotionType.sadness
        "angry", "anger" -> EmotionType.anger
        "fearful", "fear", "anxious", "anxiety" -> EmotionType.anxiety
        "disgusted", "disgust" -> EmotionType.disgust
        "surprised", "surprise" -> EmotionType.surprise
        "frustrated", "frustration" -> EmotionType.frustration
        "fatigue", "tired", "fatigued" -> EmotionType.fatigue
        "excitement", "excited" -> EmotionType.excitement
        else -> EmotionType.neutral
    }

    private fun parsePhi3Topics(output: String, originalText: String): List<TopicAnalysis> {
        val topics = mutableListOf<TopicAnalysis>()
        val lines = output.split("\n").filter { it.contains(":") }
        for (line in lines) {
            val parts = line.split(":", limit = 2)
            if (parts.size == 2) {
                val topicName = parts[0].trim().lowercase().replace(" ", "_")
                val sentiment = Phi3Service.fallbackSentiment(parts[1])
                topics.add(
                    TopicAnalysis(
                        id = UUID.randomUUID().toString(),
                        topic = topicName,
                        sentiment = sentiment,
                        confidence = 0.6,
                        detectedAt = System.currentTimeMillis() / 1000
                    )
                )
            }
        }
        return topics
    }

    private fun detectPatterns(entry: JournalEntry): JournalEntry {
        val allEntries = storage.loadEntries(limit = 100)
        val existingPatterns = storage.loadPatterns()
        val updated = allEntries + entry
        val patterns = PatternDetectionService.detectPatterns(updated, existingPatterns)
        storage.savePatterns(patterns)
        return entry
    }

    private fun detectDecisions(entry: JournalEntry): JournalEntry {
        val text = entry.transcript ?: return entry
        val decisions = mutableListOf<JournalDecision>()
        val now = System.currentTimeMillis() / 1000

        val decisionPhrases = listOf("i will", "i'm going to", "i need to", "i should", "i promise", "i swear")
        val lower = text.lowercase()

        for (phrase in decisionPhrases) {
            if (lower.contains(phrase)) {
                decisions.add(
                    JournalDecision(
                        id = UUID.randomUUID().toString(),
                        decisionText = truncateAfter(text, phrase, 60),
                        category = classifyCategory(text),
                        madeAt = entry.timestamp,
                        status = DecisionStatus.pending,
                        daysSinceDecision = 0
                    )
                )
            }
        }

        val regretPhrases = listOf("i regret", "i shouldn't have", "i wish i hadn't", "big mistake", "wrong choice")
        for (phrase in regretPhrases) {
            if (lower.contains(phrase)) {
                decisions.add(
                    JournalDecision(
                        id = UUID.randomUUID().toString(),
                        decisionText = truncateAfter(text, phrase, 60),
                        category = classifyCategory(text),
                        madeAt = entry.timestamp,
                        status = DecisionStatus.regretted,
                        daysSinceDecision = 0,
                        regretScore = 0.8
                    )
                )
            }
        }

        if (decisions.isNotEmpty()) {
            val existing = storage.loadDecisions().toMutableList()
            existing.addAll(decisions)
            storage.saveDecisions(existing)
        }

        return entry
    }

    private fun encrypt(entry: JournalEntry): JournalEntry {
        return entry // Placeholder; real AES-GCM via EncryptedFile in StorageService
    }

    private fun saveToStorage(entry: JournalEntry) {
        storage.saveEntry(entry)
    }

    private fun extractTopics(text: String): List<TopicAnalysis> {
        val keywords = listOf(
            "work" to "work", "job" to "work", "career" to "work",
            "relationship" to "relationships", "partner" to "relationships",
            "health" to "health", "exercise" to "health", "doctor" to "health",
            "family" to "family", "mother" to "family", "father" to "family",
            "money" to "finance", "finance" to "finance", "budget" to "finance",
            "hobby" to "hobbies", "travel" to "travel", "trip" to "travel",
            "goal" to "goals", "plan" to "goals", "future" to "goals",
            "friend" to "social", "social" to "social", "party" to "social",
            "anxiety" to "mental health", "stress" to "mental health", "depress" to "mental health",
            "grateful" to "gratitude", "thankful" to "gratitude", "appreciate" to "gratitude"
        )
        val lower = text.lowercase()
        val topicMap = mutableMapOf<String, Int>()

        for ((word, topic) in keywords) {
            if (lower.contains(word)) {
                topicMap[topic] = (topicMap[topic] ?: 0) + 1
            }
        }

        return topicMap.map { (topic, count) ->
            TopicAnalysis(
                id = UUID.randomUUID().toString(),
                topic = topic,
                sentiment = estimateSentiment(text, topic),
                confidence = (count.toDouble() / 3.0).coerceAtMost(1.0),
                detectedAt = System.currentTimeMillis() / 1000
            )
        }
    }

    private fun estimateSentiment(text: String, topic: String): Double {
        val positive = listOf("good", "great", "happy", "love", "wonderful", "amazing", "thankful", "grateful", "excellent")
        val negative = listOf("bad", "terrible", "hate", "awful", "horrible", "stress", "anxious", "depress", "sad", "angry")
        val lower = text.lowercase()
        var score = 0.0
        for (word in positive) { if (lower.contains(word)) score += 0.2 }
        for (word in negative) { if (lower.contains(word)) score -= 0.2 }
        return score.coerceIn(-1.0, 1.0)
    }

    private fun classifyCategory(text: String): DecisionCategory? {
        val lower = text.lowercase()
        return when {
            lower.contains("work") || lower.contains("job") || lower.contains("career") -> DecisionCategory.career
            lower.contains("relationship") || lower.contains("partner") || lower.contains("love") -> DecisionCategory.relationship
            lower.contains("health") || lower.contains("doctor") || lower.contains("exercise") -> DecisionCategory.health
            lower.contains("money") || lower.contains("budget") || lower.contains("finance") -> DecisionCategory.finance
            lower.contains("study") || lower.contains("learn") || lower.contains("course") -> DecisionCategory.education
            lower.contains("family") || lower.contains("parent") || lower.contains("child") -> DecisionCategory.family
            else -> DecisionCategory.other
        }
    }

    private fun truncateAfter(text: String, phrase: String, maxLen: Int): String {
        val idx = text.lowercase().indexOf(phrase)
        if (idx < 0) return text.take(maxLen)
        val start = idx
        val end = (idx + maxLen).coerceAtMost(text.length)
        return text.substring(start, end).trim()
    }

    private fun readPcmFromWav(file: File): ShortArray? {
        return try {
            java.io.RandomAccessFile(file, "r").use { raf ->
                val data = ByteArray(raf.length().toInt())
                raf.readFully(data)
                val buffer = java.nio.ByteBuffer.wrap(data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
                var offset = 12
                while (offset < data.size - 8) {
                    val chunkId = String(data, offset, 4)
                    val chunkSize = buffer.getInt(offset + 4)
                    if (chunkId == "data") {
                        val pcmCount = chunkSize / 2
                        val pcm = ShortArray(pcmCount)
                        for (i in 0 until pcmCount) {
                            pcm[i] = buffer.getShort(offset + 8 + i * 2)
                        }
                        return pcm
                    }
                    offset += 8 + chunkSize
                }
                null
            }
        } catch (_: Exception) { null }
    }
}
