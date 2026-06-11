package com.soulo.app.services

import com.soulo.app.models.*

object PatternDetectionService {
    private const val MIN_ENTRIES = 3
    private const val SENTIMENT_THRESHOLD = -0.3

    fun detectPatterns(
        entries: List<JournalEntry>,
        existingPatterns: List<DetectedPattern> = emptyList()
    ): List<DetectedPattern> {
        if (entries.size < MIN_ENTRIES) return emptyList()
        val sorted = entries.sortedBy { it.timestamp }
        val patterns = mutableListOf<DetectedPattern>()

        detectBrokenPromises(sorted, patterns)
        detectTopicAvoidance(sorted, patterns)
        detectSentimentDecline(sorted, patterns)
        detectGoalCycles(sorted, patterns)
        detectContradictions(sorted, patterns)
        detectCognitiveShift(sorted, patterns)
        detectRelationshipPatterns(sorted, patterns)
        detectDecisionRegret(sorted, patterns)

        return mergeWithExisting(patterns, existingPatterns)
    }

    private fun detectBrokenPromises(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val commitmentPhrases = listOf(
            "I will", "I'm going to", "I need to", "I should",
            "I promise", "I swear", "starting tomorrow", "this time"
        )
        val failurePhrases = listOf(
            "didn't", "couldn't", "failed", "gave up", "quit",
            "didn't follow through", "dropped the ball"
        )

        for (i in 1 until entries.size) {
            val prev = entries[i - 1].transcript?.lowercase() ?: continue
            val curr = entries[i].transcript?.lowercase() ?: continue
            val hasCommitment = commitmentPhrases.any { prev.contains(it) }
            val hasFailure = failurePhrases.any { curr.contains(it) }
            if (hasCommitment && hasFailure) {
                patterns.add(
                    DetectedPattern(
                        id = "bp_${entries[i].id}",
                        type = PatternType.brokenPromise,
                        title = "Broken Promise Detected",
                        message = "You committed to something on ${entries[i-1].formattedDate} but mentioned not following through.",
                        confidence = 0.7,
                        firstDetected = entries[i - 1].timestamp,
                        lastDetected = entries[i].timestamp,
                        occurrenceCount = 1
                    )
                )
            }
        }
    }

    private fun detectTopicAvoidance(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val topicFrequency = mutableMapOf<String, MutableList<Triple<Long, Double, Long>>>()
        for (entry in entries) {
            val topics = entry.topics ?: continue
            for (t in topics) {
                topicFrequency.getOrPut(t.topic) { mutableListOf() }
                    .add(Triple(entry.timestamp, t.sentiment, entry.durationMs))
            }
        }
        for ((topic, mentions) in topicFrequency) {
            if (mentions.size < 2) continue
            val sortedMentions = mentions.sortedBy { it.first }
            for (i in 1 until sortedMentions.size) {
                val gap = sortedMentions[i].first - sortedMentions[i - 1].first
                val prevDuration = sortedMentions[i - 1].third
                val currDuration = sortedMentions[i].third
                if (gap > 7 * 86400 && sortedMentions[i].second < 0 && currDuration < prevDuration * 0.7) {
                    patterns.add(
                        DetectedPattern(
                            id = "ta_${topic}_${sortedMentions[i].first}",
                            type = PatternType.topicAvoidance,
                            title = "Topic Avoidance: $topic",
                            message = "You mentioned '$topic' after a ${gap / 86400} day gap, but spoke about it briefly.",
                            confidence = 0.6,
                            relatedTopic = topic,
                            firstDetected = sortedMentions[i - 1].first,
                            lastDetected = sortedMentions[i].first
                        )
                    )
                }
            }
        }
    }

    private fun detectSentimentDecline(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val sorted = entries
            .filter { it.emotion != null && it.transcriptStatus == ProcessingStatus.completed }
            .sortedBy { it.timestamp }
        if (sorted.size < 3) return

        val recent = sorted.takeLast(3)
        val prevValence = sorted[sorted.size - 4].emotion!!.valence
        val recentAvg = recent.map { it.emotion!!.valence }.average()
        val decline = recentAvg - prevValence

        if (decline < SENTIMENT_THRESHOLD) {
            patterns.add(
                DetectedPattern(
                    id = "sd_${sorted.last().id}",
                    type = PatternType.sentimentDecline,
                    title = "Sentiment Decline",
                    message = "Your emotional valence dropped ${String.format("%.2f", kotlin.math.abs(decline))} points recently.",
                    confidence = kotlin.math.abs(decline).coerceAtMost(1.0),
                    firstDetected = sorted.first().timestamp,
                    lastDetected = sorted.last().timestamp
                )
            )
        }
    }

    private fun detectGoalCycles(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val goalPhrases = listOf(
            "I want to", "my goal", "I'm trying", "working on",
            "need to improve", "I should start", "I've been meaning to"
        )
        val abandonPhrases = listOf(
            "stopped", "gave up", "failed again", "can't keep up",
            "missed", "forgot", "didn't have time", "let it slip"
        )

        val goalMentions = mutableMapOf<String, MutableList<Pair<Long, String>>>()
        for (entry in entries) {
            val text = entry.transcript?.lowercase() ?: continue
            for (phrase in goalPhrases) {
                if (text.contains(phrase)) {
                    val goal = extractGoal(text, phrase)
                    goalMentions.getOrPut(goal) { mutableListOf() }
                        .add(entry.timestamp to phrase)
                }
            }
        }

        for ((goal, mentions) in goalMentions) {
            if (mentions.size < 3) continue
            val sortedM = mentions.sortedBy { it.first }
            var cycleCount = 0
            for (i in 1 until sortedM.size) {
                if (sortedM[i].second in abandonPhrases ||
                    sortedM[i - 1].second in abandonPhrases
                ) cycleCount++
            }
            if (cycleCount >= 2) {
                patterns.add(
                    DetectedPattern(
                        id = "gc_$goal",
                        type = PatternType.goalCycle,
                        title = "Goal Cycle: $goal",
                        message = "You've revisited '$goal' with ${mentions.size} mentions and $cycleCount gaps.",
                        confidence = 0.65,
                        firstDetected = sortedM.first().first,
                        lastDetected = sortedM.last().first,
                        occurrenceCount = cycleCount
                    )
                )
            }
        }
    }

    private fun extractGoal(text: String, phrase: String): String {
        val idx = text.indexOf(phrase) + phrase.length
        val end = text.indexOf('.', idx).takeIf { it > 0 } ?: text.indexOf(',', idx).takeIf { it > 0 } ?: (idx + 40).coerceAtMost(text.length)
        return text.substring(idx, end).trim()
    }

    private fun detectContradictions(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val contradictionPairs = listOf(
            "I love" to "I hate",
            "I'm happy" to "I'm miserable",
            "it's fine" to "it's terrible",
            "I'm good" to "I'm struggling",
            "no problem" to "big problem"
        )
        for (i in 1 until entries.size) {
            val prev = entries[i - 1].transcript?.lowercase() ?: continue
            val curr = entries[i].transcript?.lowercase() ?: continue
            for ((pos, neg) in contradictionPairs) {
                if (prev.contains(pos) && curr.contains(neg)) {
                    patterns.add(
                        DetectedPattern(
                            id = "ct_${entries[i].id}",
                            type = PatternType.contradiction,
                            title = "Contradictory Statements",
                            message = "You said '$pos' recently, but now mention '$neg'.",
                            confidence = 0.5,
                            firstDetected = entries[i - 1].timestamp,
                            lastDetected = entries[i].timestamp
                        )
                    )
                }
            }
        }
    }

    private fun detectCognitiveShift(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val sorted = entries
            .filter { it.biomarkers != null && it.emotion != null }
            .sortedBy { it.timestamp }
        if (sorted.size < 5) return

        val early = sorted.take(3)
        val late = sorted.takeLast(3)
        val earlyAvgSpeech = early.mapNotNull { it.biomarkers?.speechRate }.average()
        val lateAvgSpeech = late.mapNotNull { it.biomarkers?.speechRate }.average()
        val speechDelta = lateAvgSpeech - earlyAvgSpeech

        if (kotlin.math.abs(speechDelta) > 0.5) {
            val changes = mutableListOf<String>()
            if (speechDelta > 0.5) changes.add("speaking faster")
            if (speechDelta < -0.5) changes.add("speaking slower")
            if (late.map { it.biomarkers!!.pitchInstability }.average() > 0.3) changes.add("more pitch variation")

            if (changes.isNotEmpty()) {
                patterns.add(
                    DetectedPattern(
                        id = "cs_${sorted.last().id}",
                        type = PatternType.cognitiveShift,
                        title = "Cognitive Shift Detected",
                        message = "Your speech patterns have changed: ${changes.joinToString(", ")}.",
                        confidence = 0.55,
                        firstDetected = sorted.first().timestamp,
                        lastDetected = sorted.last().timestamp
                    )
                )
            }
        }
    }

    private fun detectRelationshipPatterns(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val people = mutableSetOf<String>()
        val relationshipTerms = listOf(
            "partner", "spouse", "boyfriend", "girlfriend", "husband", "wife",
            "mother", "father", "mom", "dad", "sister", "brother", "friend",
            "manager", "colleague", "therapist", "doctor"
        )

        for (entry in entries) {
            val text = entry.transcript?.lowercase() ?: continue
            for (term in relationshipTerms) {
                if (text.contains(term)) {
                    people.add(term)
                }
            }
        }

        for (person in people.take(5)) {
            val mentions = entries.filter { it.transcript?.lowercase()?.contains(person) == true }
            if (mentions.size < 2) continue
            val sentiments = mentions.mapNotNull { it.emotion?.valence }
            if (sentiments.size < 2) continue
            val trend = sentiments.zipWithNext().map { (a, b) -> b - a }
            val avgDelta = if (trend.isNotEmpty()) trend.average() else 0.0
            val volatility = if (sentiments.isNotEmpty()) {
                val mean = sentiments.average()
                sentiments.map { kotlin.math.abs(it - mean) }.average()
            } else 0.0

            if (volatility > 0.4) {
                patterns.add(
                    DetectedPattern(
                        id = "rp_$person",
                        type = PatternType.relationshipPattern,
                        title = "Relationship Pattern: $person",
                        message = "Your sentiment around '$person' shows high volatility (${String.format("%.2f", volatility)}).",
                        confidence = volatility.coerceAtMost(1.0),
                        firstDetected = mentions.first().timestamp,
                        lastDetected = mentions.last().timestamp,
                        occurrenceCount = mentions.size
                    )
                )
            }
        }
    }

    private fun detectDecisionRegret(entries: List<JournalEntry>, patterns: MutableList<DetectedPattern>) {
        val regretPhrases = listOf("I regret", "I shouldn't have", "I wish I hadn't", "big mistake", "wrong choice", "I made a mistake")
        for (entry in entries) {
            val text = entry.transcript?.lowercase() ?: continue
            val matched = regretPhrases.firstOrNull { text.contains(it) } ?: continue
            patterns.add(
                DetectedPattern(
                    id = "dr_${entry.id}",
                    type = PatternType.decisionRegret,
                    title = "Decision Regret",
                    message = "You expressed regret: \"$matched\"",
                    confidence = 0.8,
                    firstDetected = entry.timestamp,
                    lastDetected = entry.timestamp,
                    relatedEmotions = listOfNotNull(entry.emotion?.primaryEmotion)
                )
            )
        }
    }

    private fun mergeWithExisting(
        newPatterns: List<DetectedPattern>,
        existing: List<DetectedPattern>
    ): List<DetectedPattern> {
        val merged = existing.toMutableList()
        for (np in newPatterns) {
            val match = merged.find {
                it.type == np.type && it.relatedTopic == np.relatedTopic && it.title == np.title
            }
            if (match != null) {
                val idx = merged.indexOf(match)
                merged[idx] = match.copy(
                    occurrenceCount = match.occurrenceCount + 1,
                    lastDetected = np.lastDetected,
                    confidence = maxOf(match.confidence, np.confidence)
                )
            } else {
                merged.add(np)
            }
        }
        return merged
    }
}
