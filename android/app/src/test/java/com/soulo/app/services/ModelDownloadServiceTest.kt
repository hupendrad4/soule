package com.soulo.app.services

import org.junit.Assert.*
import org.junit.Test

class ModelDownloadServiceTest {
    @Test
    fun `model registry has expected entries`() {
        assertTrue(ModelDownloadService.models.isNotEmpty())
        assertEquals(4, ModelDownloadService.models.size)
    }

    @Test
    fun `whisper model has expected properties`() {
        val whisper = ModelDownloadService.models.find { it.fileName == "ggml-tiny.en.bin" }
        assertNotNull("Whisper model should be registered", whisper)
        assertEquals("ggml-tiny.en.bin", whisper!!.fileName)
        assertTrue(whisper.expectedSize > 70_000_000)
    }

    @Test
    fun `emotion2vec model has expected properties`() {
        val emotion = ModelDownloadService.models.find { it.fileName == "emotion2vec.onnx" }
        assertNotNull("emotion2vec model should be registered", emotion)
        assertEquals("emotion2vec.onnx", emotion!!.fileName)
    }

    @Test
    fun `phi3 model has expected properties`() {
        val phi3 = ModelDownloadService.models.find { it.fileName == "phi3_mini_q4.onnx" }
        assertNotNull("Phi-3 model should be registered", phi3)
        assertTrue(phi3!!.expectedSize > 1_000_000_000)
    }

    @Test
    fun `tokenizer model has expected properties`() {
        val tokenizer = ModelDownloadService.models.find { it.fileName == "tokenizer.json" }
        assertNotNull("Tokenizer should be registered", tokenizer)
        assertEquals("tokenizer.json", tokenizer!!.fileName)
    }

    @Test
    fun `totalDownloadSize returns sum of undownloaded models`() {
        val total = ModelDownloadService.totalDownloadSize()
        assertTrue("Total should be non-zero", total > 0)
    }
}
