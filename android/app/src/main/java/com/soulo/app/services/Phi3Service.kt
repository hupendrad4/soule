package com.soulo.app.services

import com.soulo.app.SouloApplication
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import kotlin.math.max
import kotlin.math.min

object Phi3Service {
    private const val MAX_GEN_TOKENS = 32
    private const val VOCAB_SIZE = 32064

    // Special tokens
    private const val BOS = 1
    private const val EOS = 2
    private const val PAD = 0

    private val onnx = OnnxService()
    private var tokenizer: BPETokenizer? = null

    data class Phi3Result(val text: String, val success: Boolean, val wasFallback: Boolean)

    private val modelDir: File
        get() = File(SouloApplication.instance.filesDir, "models")

    fun initTokenizer(): Boolean {
        val file = File(modelDir, "tokenizer.json")
        if (!file.exists()) {
            // Fallback: create simple char-level tokenizer
            tokenizer = SimpleTokenizer()
            return false
        }
        return try {
            tokenizer = HuggingFaceTokenizer(file)
            true
        } catch (_: Exception) {
            tokenizer = SimpleTokenizer()
            false
        }
    }

    suspend fun analyzeTopics(transcript: String): Phi3Result = withContext(Dispatchers.Default) {
        val prompt = "<|user|>\nExtract topics and sentiment from: '$transcript'\n<|assistant|>\n"
        generate(prompt)
    }

    suspend fun analyzeSentiment(transcript: String): Phi3Result = withContext(Dispatchers.Default) {
        val prompt = "<|user|>\nRate the emotional sentiment from -1.0 to 1.0: '$transcript'\n<|assistant|>\n"
        generate(prompt)
    }

    suspend fun extractEntities(transcript: String): Phi3Result = withContext(Dispatchers.Default) {
        val prompt = "<|user|>\nExtract named entities (people, places, dates): '$transcript'\n<|assistant|>\n"
        generate(prompt)
    }

    suspend fun summarize(transcript: String): Phi3Result = withContext(Dispatchers.Default) {
        val prompt = "<|user|>\nSummarize in 1 sentence: '$transcript'\n<|assistant|>\n"
        generate(prompt)
    }

    private suspend fun generate(prompt: String): Phi3Result = withContext(Dispatchers.Default) {
        if (!onnx.isModelAvailable(OnnxModel.Phi3Mini)) {
            return@withContext Phi3Result("", success = false, wasFallback = true)
        }
        return@withContext try {
            onnx.loadModel(OnnxModel.Phi3Mini)
            val tok = tokenizer ?: run { initTokenizer(); tokenizer }
            if (tok == null) return@withContext Phi3Result("", success = false, wasFallback = true)

            var tokens = tok.encode(prompt)
            val generated = mutableListOf<Long>()

            for (i in 0 until MAX_GEN_TOKENS) {
                if (tokens.size > 1024) {
                    tokens = tokens.takeLast(1024).toMutableList()
                }

                val inputIds = tokens.toLongArray()
                val nextTokenIds = onnx.runPhi3(inputIds) ?: break
                if (nextTokenIds.isEmpty()) break

                val nextId = nextTokenIds[0]
                if (nextId == EOS.toLong()) break

                generated.add(nextId)
                tokens.add(nextId)
            }

            val text = tok.decode(generated.toLongArray())
            Phi3Result(text = text.trim(), success = text.isNotBlank(), wasFallback = false)
        } catch (e: Exception) {
            Phi3Result("", success = false, wasFallback = true)
        }
    }

    // Keyword-based fallback (always available)
    fun fallbackTopics(transcript: String): List<Pair<String, Double>> {
        val lower = transcript.lowercase()
        val keywords = listOf(
            "work" to "work", "job" to "work", "career" to "work",
            "relationship" to "relationships", "partner" to "relationships", "girlfriend" to "relationships", "boyfriend" to "relationships",
            "health" to "health", "exercise" to "health", "doctor" to "health", "sick" to "health",
            "family" to "family", "mother" to "family", "father" to "family", "parent" to "family", "child" to "family",
            "money" to "finance", "finance" to "finance", "budget" to "finance", "spend" to "finance",
            "friend" to "social", "social" to "social", "party" to "social",
            "anxiety" to "mental health", "stress" to "mental health", "depress" to "mental health", "therapy" to "mental health",
            "grateful" to "gratitude", "thankful" to "gratitude", "appreciate" to "gratitude",
            "travel" to "travel", "trip" to "travel", "vacation" to "travel",
            "goal" to "goals", "plan" to "goals", "future" to "goals",
            "hobby" to "hobbies", "music" to "hobbies", "read" to "hobbies"
        )
        val topicMap = mutableMapOf<String, MutableList<Double>>()
        for ((word, topic) in keywords) {
            if (lower.contains(word)) {
                topicMap.getOrPut(topic) { mutableListOf() }.add(estimateSentiment(lower))
            }
        }
        return topicMap.mapValues { (_, sentiments) -> sentiments.average() }
            .entries
            .sortedByDescending { it.value }
            .map { it.key to it.value }
    }

    fun fallbackSentiment(transcript: String): Double {
        val lower = transcript.lowercase()
        val positive = listOf("good", "great", "happy", "love", "wonderful", "amazing",
            "thankful", "grateful", "excellent", "fantastic", "beautiful", "best", "nice")
        val negative = listOf("bad", "terrible", "hate", "awful", "horrible", "stress",
            "anxious", "depress", "sad", "angry", "worst", "ugly", "painful", "hurt")
        var score = 0.0
        for (w in positive) { if (lower.contains(w)) score += 0.15 }
        for (w in negative) { if (lower.contains(w)) score -= 0.15 }
        return score.coerceIn(-1.0, 1.0)
    }

    private fun estimateSentiment(text: String): Double {
        val positive = listOf("good", "great", "happy", "love", "wonderful", "amazing", "thankful", "grateful", "excellent")
        val negative = listOf("bad", "terrible", "hate", "awful", "horrible", "stress", "anxious", "depress", "sad", "angry")
        var score = 0.0
        for (w in positive) { if (text.contains(w)) score += 0.2 }
        for (w in negative) { if (text.contains(w)) score -= 0.2 }
        return score.coerceIn(-1.0, 1.0)
    }

    // ---------- Tokenizer ----------
    private interface BPETokenizer {
        fun encode(text: String): MutableList<Long>
        fun decode(ids: LongArray): String
    }

    private class HuggingFaceTokenizer(file: File) : BPETokenizer {
        private val json = JSONObject(file.readText(StandardCharsets.UTF_8))
        private val model = json.getJSONObject("model")
        private val vocab: Map<String, Long> = model.getJSONObject("vocab")
            .keys().asSequence().map { it to model.getJSONObject("vocab").getLong(it) }.toMap()
        private val merges: List<Pair<String, String>> = model.getJSONArray("merges")
            .let { arr -> (0 until arr.length()).map { arr.getString(it).split(" ").let { s -> s[0] to s[1] } } }
        private val addedTokens: Map<String, Long> = json.optJSONObject("added_tokens")?.let {
            it.keys().asSequence().map { k -> k to it.getLong(k) }.toMap()
        } ?: emptyMap()

        override fun encode(text: String): MutableList<Long> {
            val pre = text.replace(Regex("\\s+"), " ")
                .let { " $it" }
            val chars = pre.toList().map { it.toString() }
            val words = mutableListOf<String>()
            var current = StringBuilder()
            for (c in pre) {
                if (c == ' ' && current.isNotEmpty()) {
                    words.add(current.toString()); current = StringBuilder()
                }
                current.append(c)
            }
            if (current.isNotEmpty()) words.add(current.toString())

            val tokens = mutableListOf<Long>()
            for (word in words) {
                var bpeChars = word.toList().map { it.toString() }
                var merged = true
                while (merged) {
                    merged = false
                    var bestPair: Pair<String, String>? = null
                    var bestRank = Int.MAX_VALUE
                    for (i in 0 until bpeChars.size - 1) {
                        val pair = bpeChars[i] to bpeChars[i + 1]
                        val pairKey = "${pair.first} ${pair.second}"
                        val rank = merges.indexOfFirst { it.first == pair.first && it.second == pair.second }
                        if (rank >= 0 && rank < bestRank) {
                            bestRank = rank
                            bestPair = pair
                        }
                    }
                    if (bestPair != null) {
                        val newChars = mutableListOf<String>()
                        var i = 0
                        while (i < bpeChars.size) {
                            if (i < bpeChars.size - 1 && bpeChars[i] == bestPair.first && bpeChars[i + 1] == bestPair.second) {
                                newChars.add(bestPair.first + bestPair.second)
                                i += 2
                            } else {
                                newChars.add(bpeChars[i])
                                i++
                            }
                        }
                        bpeChars = newChars
                        merged = true
                    }
                }
                for (chunk in bpeChars) {
                    val id = vocab[chunk] ?: addedTokens[chunk]
                    if (id != null) tokens.add(id)
                }
            }
            return tokens.toMutableList()
        }

        override fun decode(ids: LongArray): String {
            val idToToken = vocab.entries.associate { it.value to it.key }
            val decoder = mutableMapOf<Long, String>()
            decoder.putAll(idToToken)
            decoder.putAll(addedTokens.entries.associate { it.value to it.key })
            return ids.toList().map { decoder[it] }.filterNotNull()
                .joinToString("")
                .replace(" ", " ")
                .trim()
                .replace("</s>", "")
                .replace("<s>", "")
                .replace("<|user|>", "")
                .replace("<|assistant|>", "")
                .replace("<|end|>", "")
                .replace("<|system|>", "")
                .trim()
        }
    }

    private class SimpleTokenizer : BPETokenizer {
        private val vocab: Map<String, Long> = buildMap {
            put("<|pad|>", 0); put("<s>", 1); put("</s>", 2); put("<unk>", 3)
            for (i in 32..126) put(i.toChar().toString(), i.toLong() - 32 + 4)
            put(" ", 99); put("  ", 100)
        }
        private val revVocab = vocab.entries.associate { it.value to it.key }

        override fun encode(text: String): MutableList<Long> {
            val tokens = mutableListOf<Long>()
            tokens.add(BOS.toLong())
            var i = 0
            while (i < text.length) {
                val c = text[i].toString()
                val id = vocab[c] ?: vocab["<unk>"] ?: 3
                tokens.add(id)
                i++
            }
            return tokens
        }

        override fun decode(ids: LongArray): String {
            return ids.toList().map { revVocab[it] }.filterNotNull()
                .joinToString("")
                .replace("<s>", "").replace("</s>", "")
                .trim()
        }
    }
}
