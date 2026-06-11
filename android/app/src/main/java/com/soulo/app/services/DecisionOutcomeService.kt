package com.soulo.app.services

import com.soulo.app.models.*
import java.util.*

object DecisionOutcomeService {
    fun enhanceDecision(original: JournalDecision): EnhancedDecision {
        return EnhancedDecision(
            id = original.id,
            title = extractTitle(original.decisionText),
            category = original.category ?: categorizeDecision(original.decisionText),
            timestamp = original.madeAt,
            details = original,
            status = original.status
        )
    }

    private fun categorizeDecision(text: String): DecisionCategory {
        val lower = text.lowercase(Locale.US)
        return when {
            lower.contains("work") || lower.contains("job") || lower.contains("career") -> DecisionCategory.career
            lower.contains("love") || lower.contains("partner") || lower.contains("friend") || lower.contains("relationship") -> DecisionCategory.relationship
            lower.contains("money") || lower.contains("spend") || lower.contains("buy") || lower.contains("budget") -> DecisionCategory.finance
            lower.contains("doctor") || lower.contains("health") || lower.contains("exercise") || lower.contains("diet") -> DecisionCategory.health
            lower.contains("study") || lower.contains("course") || lower.contains("learn") -> DecisionCategory.education
            lower.contains("drink") || lower.contains("smoke") || lower.contains("habit") || lower.contains("sleep") -> DecisionCategory.lifestyle
            lower.contains("family") || lower.contains("parent") || lower.contains("child") || lower.contains("mom") -> DecisionCategory.family
            else -> DecisionCategory.other
        }
    }

    private fun extractTitle(description: String): String {
        val lower = description.lowercase(Locale.US)
        val verbs = listOf("decide to", "going to", "will ", "should i", "need to", "plan to")
        for (verb in verbs) {
            val idx = lower.indexOf(verb)
            if (idx >= 0) {
                val start = idx + verb.length
                if (start < description.length) return description.substring(start).trim().take(80)
            }
        }
        return description.take(80)
    }

    fun getStatistics(decisions: List<JournalDecision>): DecisionStatistics {
        val enhanced = decisions.map { enhanceDecision(it) }
        val byCategory = enhanced.groupBy { it.category }

        val categoryCounts = byCategory.map { (cat, items) ->
            val kept = items.count { it.status == DecisionStatus.kept }
            val regretted = items.count { it.status == DecisionStatus.regretted }
            CategoryBreakdown(cat.name, items.size, kept, regretted)
        }

        val byMonth = enhanced.groupBy {
            val cal = Calendar.getInstance().apply { timeInMillis = it.timestamp * 1000 }
            "${cal.get(Calendar.YEAR)}-${cal.get(Calendar.MONTH) + 1}"
        }

        val monthlyTrend = byMonth.map { (month, items) ->
            val kept = items.count { it.status == DecisionStatus.kept }
            val regretted = items.count { it.status == DecisionStatus.regretted }
            MonthlyDecisionCounts(month, items.size, kept, regretted)
        }.sortedBy { it.month }

        return DecisionStatistics(
            total = enhanced.size,
            kept = enhanced.count { it.status == DecisionStatus.kept },
            regretted = enhanced.count { it.status == DecisionStatus.regretted },
            pending = enhanced.count { it.status == DecisionStatus.pending },
            categories = categoryCounts,
            monthlyTrend = monthlyTrend
        )
    }
}

data class EnhancedDecision(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val category: DecisionCategory,
    val timestamp: Long = System.currentTimeMillis() / 1000,
    val details: JournalDecision? = null,
    val status: DecisionStatus = DecisionStatus.pending
)

data class DecisionStatistics(
    val total: Int,
    val kept: Int,
    val regretted: Int,
    val pending: Int,
    val categories: List<CategoryBreakdown>,
    val monthlyTrend: List<MonthlyDecisionCounts>
)

data class CategoryBreakdown(
    val category: String,
    val total: Int,
    val kept: Int,
    val regretted: Int
)

data class MonthlyDecisionCounts(
    val month: String,
    val total: Int,
    val kept: Int,
    val regretted: Int
)
