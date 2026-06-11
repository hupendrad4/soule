package com.soulo.app.services

import org.junit.Assert.*
import org.junit.Test

class Phi3ServiceTest {
    @Test
    fun `fallbackTopics extracts work-related topics`() {
        val transcript = "I had a great day at work today. My project is going well."
        val topics = Phi3Service.fallbackTopics(transcript)
        assertTrue(topics.any { it.first == "work" })
    }

    @Test
    fun `fallbackTopics extracts health topics`() {
        val transcript = "I went to the doctor and my health is improving."
        val topics = Phi3Service.fallbackTopics(transcript)
        assertTrue(topics.any { it.first == "health" })
    }

    @Test
    fun `fallbackTopics extracts relationship topics`() {
        val transcript = "My partner and I had a lovely dinner together."
        val topics = Phi3Service.fallbackTopics(transcript)
        assertTrue(topics.any { it.first == "relationships" })
    }

    @Test
    fun `fallbackTopics extracts multiple topics`() {
        val transcript = "Work is stressful but my family is supportive."
        val topics = Phi3Service.fallbackTopics(transcript)
        val topicNames = topics.map { it.first }
        assertTrue(topicNames.contains("work"))
        assertTrue(topicNames.contains("family"))
    }

    @Test
    fun `fallbackSentiment returns positive for happy text`() {
        val sentiment = Phi3Service.fallbackSentiment("I am so happy and grateful today!")
        assertTrue("Sentiment should be positive", sentiment > 0.3)
    }

    @Test
    fun `fallbackSentiment returns negative for sad text`() {
        val sentiment = Phi3Service.fallbackSentiment("I feel terrible and depressed.")
        assertTrue("Sentiment should be negative", sentiment < -0.3)
    }

    @Test
    fun `fallbackSentiment returns neutral for mixed text`() {
        val sentiment = Phi3Service.fallbackSentiment("The weather is cloudy.")
        assertTrue("Sentiment should be near zero", kotlin.math.abs(sentiment) < 0.2)
    }

    @Test
    fun `fallbackSentiment handles empty text`() {
        val sentiment = Phi3Service.fallbackSentiment("")
        assertEquals(0.0, sentiment, 0.01)
    }
}
