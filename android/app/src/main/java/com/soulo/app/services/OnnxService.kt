package com.soulo.app.services

import ai.onnxruntime.*
import com.soulo.app.SouloApplication
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer

sealed class OnnxModel(val modelFile: String, val displayName: String) {
    data object Emotion2Vec : OnnxModel("emotion2vec.onnx", "Emotion Detection")
    data object Phi3Mini : OnnxModel("phi3_mini_q4.onnx", "Text Analysis")
}

class OnnxService {
    companion object {
        private const val VOCAB_SIZE = 32064
        private var ortLoaded = false

        fun initOnce() {
            if (!ortLoaded) {
                try {
                    System.loadLibrary("onnxruntime")
                    ortLoaded = true
                } catch (_: UnsatisfiedLinkError) {}
            }
        }
    }

    private val modelDir: File
        get() = File(SouloApplication.instance.filesDir, "models")

    private val env: OrtEnvironment by lazy {
        initOnce()
        OrtEnvironment.getEnvironment()
    }

    private val sessions = mutableMapOf<String, OrtSession>()

    fun isModelAvailable(model: OnnxModel): Boolean {
        return File(modelDir, model.modelFile).exists()
    }

    @Throws(OrtException::class)
    fun loadModel(model: OnnxModel): OrtSession {
        val file = File(modelDir, model.modelFile)
        if (!file.exists()) throw IllegalStateException("Model not found: ${file.absolutePath}")
        sessions[model.modelFile]?.let { return it }
        val opts = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
            addConfigEntry("session.intra_op.allow_spinning", "1")
            addConfigEntry("session.inter_op.allow_spinning", "1")
            if (model == OnnxModel.Phi3Mini) {
                addConfigEntry("session.intra_op.num_threads", "2")
            }
        }
        val session = env.createSession(file.absolutePath, opts)
        sessions[model.modelFile] = session
        return session
    }

    fun releaseModel(model: OnnxModel) {
        sessions.remove(model.modelFile)?.close()
    }

    fun releaseAll() {
        sessions.values.forEach { it.close() }
        sessions.clear()
    }

    fun getSession(model: OnnxModel): OrtSession? = sessions[model.modelFile]

    // ---------- emotion2vec ----------
    fun runEmotion2vec(melSpectrogram: FloatArray, numFrames: Int, numMelBins: Int = 64): FloatArray? {
        val session = getSession(OnnxModel.Emotion2Vec) ?: return null
        return try {
            val shape = longArrayOf(1, 1, numMelBins.toLong(), numFrames.toLong())
            val tensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(melSpectrogram), shape)
            val output = session.run(mapOf("input" to tensor))
            val result = output.get("output")?.get() as? Array<*> ?: output.first().value as? Array<*>
            result?.firstOrNull()?.let {
                when (it) {
                    is FloatArray -> it
                    is Array<*> -> it.filterIsInstance<Float>().toFloatArray()
                    else -> null
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    // emotion2vec emotion labels in order
    fun emotionLabels(): List<String> = listOf(
        "neutral", "happy", "sad", "angry", "fearful", "disgusted", "surprised"
    )

    fun decodeEmotion(probabilities: FloatArray): Map<String, Float> {
        val labels = emotionLabels()
        val sum = probabilities.sum().coerceAtLeast(1e-8f)
        return labels.mapIndexed { i, label -> label to (probabilities[i] / sum) }
            .sortedByDescending { it.second }
            .take(5)
            .toMap()
    }

    // ---------- Phi-3-mini ----------
    fun runPhi3(inputIds: LongArray, attentionMask: LongArray? = null): LongArray? {
        val session = getSession(OnnxModel.Phi3Mini) ?: return null
        return try {
            val seqLen = inputIds.size.toLong()
            val shape = longArrayOf(1, seqLen)
            val inputTensor = OnnxTensor.createTensor(env, LongBuffer.wrap(inputIds), shape)

            val feeds = mutableMapOf("input_ids" to inputTensor)
            if (attentionMask != null) {
                val maskTensor = OnnxTensor.createTensor(env, LongBuffer.wrap(attentionMask), shape)
                feeds["attention_mask"] = maskTensor
            }
            val output = session.run(feeds)

            // Extract logits from ONNX output (shape: [1, seq_len, vocab_size])
            val logitsTensor = output.first().value
            val vocabSize = VOCAB_SIZE

            val scores = when (logitsTensor) {
                is Array<*> -> {
                    // 3D array: [batch][seq][vocab]
                    val batch = logitsTensor
                    val lastSeq = batch.lastOrNull() as? Array<*>
                    lastSeq?.lastOrNull() as? FloatArray
                }
                is OnnxTensor -> {
                    // Direct tensor — read float buffer
                    val tensor = logitsTensor as OnnxTensor
                    val buffer = tensor.floatBuffer
                    val totalElements = buffer.capacity()
                    val lastSeqStart = totalElements - vocabSize
                    if (lastSeqStart >= 0) {
                        val lastScores = FloatArray(vocabSize)
                        buffer.position(lastSeqStart)
                        buffer.get(lastScores)
                        lastScores
                    } else null
                }
                else -> null
            }

            if (scores != null) {
                val nextTokenId = scores.indices.maxByOrNull { scores[it] }?.toLong()
                if (nextTokenId != null) longArrayOf(nextTokenId) else null
            } else null
        } catch (e: Exception) {
            null
        }
    }

}
