package com.soulo.app.models

import kotlinx.serialization.Serializable

@Serializable
enum class SubscriptionPlan(val storeId: String, val price: Double) {
    monthly("soulo_monthly", 9.99),
    annual("soulo_annual", 79.99),
    family("soulo_family", 14.99);

    val displayName: String get() = when (this) {
        monthly -> "Monthly"
        annual -> "Annual"
        family -> "Family"
    }

    val priceDisplay: String get() = when (this) {
        monthly -> "$9.99/month"
        annual -> "$79.99/year"
        family -> "$14.99/month"
    }
}

@Serializable
data class SubscriptionStatus(
    val isActive: Boolean = false,
    val plan: SubscriptionPlan? = null,
    val expiryDate: Long? = null,
    val entryCount: Int = 0,
    val trialLimit: Int = 7,
    val isFamilyShared: Boolean = false
) {
    val canRecord: Boolean get() = isActive || entryCount < trialLimit
    val remainingTrial: Int get() = (trialLimit - entryCount).coerceAtLeast(0)
}
