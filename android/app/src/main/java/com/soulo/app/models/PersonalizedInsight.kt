package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
data class PersonalizedInsight(
    val id: String,
    val insightType: InsightType,
    val title: String,
    val message: String,
    val sensitivityLevel: SensitivityLevel,
    val shouldShow: Boolean,
    val expiresAt: Long,
    val dismissed: Boolean = false
) {
    @Serializable
    enum class SensitivityLevel {
        neutral, gentle, direct, urgent
    }
}
