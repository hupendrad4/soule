package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class DecisionCategory {
    career, relationship, health, finance, education, lifestyle, family, other

}

@Serializable
enum class DecisionStatus {
    kept, broken, regretted, pending

}

@Serializable
data class JournalDecision(
    val id: String,
    val decisionText: String,
    val category: DecisionCategory? = null,
    val madeAt: Long,
    val status: DecisionStatus,
    val daysSinceDecision: Int,
    val followUpSentiment: Double? = null,
    val regretScore: Double? = null
)
