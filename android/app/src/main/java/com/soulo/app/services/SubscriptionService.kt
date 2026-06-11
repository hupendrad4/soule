package com.soulo.app.services

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.*
import com.soulo.app.SouloApplication
import com.soulo.app.models.SubscriptionPlan
import com.soulo.app.models.SubscriptionStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

object SubscriptionService {
    private const val PREFS = "subscription_prefs"
    private const val KEY_ACTIVE = "is_active"
    private const val KEY_PLAN = "plan"
    private const val KEY_EXPIRY = "expiry"
    private const val KEY_FAMILY = "is_family"

    private val ctx = SouloApplication.instance
    private var billingClient: BillingClient? = null
    private var pendingPurchaseCallback: ((Boolean) -> Unit)? = null

    private val _status = MutableStateFlow(loadPersistedStatus())
    val status: StateFlow<SubscriptionStatus> = _status

    private val listener = PurchasesUpdatedListener { billingResult, purchases ->
        if (billingResult.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            purchases.forEach { purchase ->
                handlePurchase(purchase)
            }
        }
    }

    fun initialize() {
        billingClient = BillingClient.newBuilder(ctx)
            .setListener(listener)
            .enablePendingPurchases()
            .build()

        billingClient?.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    queryExistingPurchases()
                }
            }

            override fun onBillingServiceDisconnected() {}
        })
    }

    fun launchBillingFlow(activity: Activity, plan: SubscriptionPlan, onComplete: (Boolean) -> Unit) {
        pendingPurchaseCallback = onComplete
        val client = billingClient ?: run {
            onComplete(false)
            return
        }

        val productId = plan.storeId
        val productType = BillingClient.ProductType.SUBS

        client.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(productType).build()
        ) { _, purchases ->
            // Check if already subscribed to this product
            if (purchases.any { it.products.contains(productId) && it.purchaseState == Purchase.PurchaseState.PURCHASED }) {
                onComplete(true)
                return@queryPurchasesAsync
            }
        }

        val productParams = QueryProductDetailsParams.Product.newBuilder()
            .setProductId(productId)
            .setProductType(productType)
            .build()

        client.queryProductDetailsAsync(
            QueryProductDetailsParams.newBuilder().setProductList(listOf(productParams)).build()
        ) { billingResult, details ->
            if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                onComplete(false)
                return@queryProductDetailsAsync
            }

            val productDetail = details.firstOrNull() ?: run {
                onComplete(false)
                return@queryProductDetailsAsync
            }

            val offerToken = productDetail.subscriptionOfferDetails?.firstOrNull()?.offerToken

            val productParamsList = BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(productDetail)
                .apply { offerToken?.let { setOfferToken(it) } }
                .build()

            val billingFlowParams = BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(productParamsList))
                .build()

            client.launchBillingFlow(activity, billingFlowParams)
        }
    }

    fun queryExistingPurchases() {
        billingClient?.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        ) { _, purchases ->
            val active = purchases.firstOrNull { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            if (active != null) {
                handlePurchase(active)
            }
        }
    }

    private fun handlePurchase(purchase: Purchase) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return

        // Acknowledge the purchase
        if (!purchase.isAcknowledged) {
            val params = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            billingClient?.acknowledgePurchase(params) { _ -> }
        }

        // Determine plan from product IDs
        val plan = when {
            purchase.products.any { it.contains("annual") } -> SubscriptionPlan.annual
            purchase.products.any { it.contains("family") } -> SubscriptionPlan.family
            else -> SubscriptionPlan.monthly
        }

        val newStatus = SubscriptionStatus(
            isActive = true,
            plan = plan,
            expiryDate = (System.currentTimeMillis() / 1000) + 365 * 86400,
            entryCount = loadPersistedStatus().entryCount,
            isFamilyShared = plan == SubscriptionPlan.family
        )

        persistStatus(newStatus)
        _status.value = newStatus
        pendingPurchaseCallback?.invoke(true)
        pendingPurchaseCallback = null
    }

    private fun loadPersistedStatus(): SubscriptionStatus {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return SubscriptionStatus(
            isActive = prefs.getBoolean(KEY_ACTIVE, false),
            plan = prefs.getString(KEY_PLAN, null)?.let { SubscriptionPlan.valueOf(it) },
            expiryDate = prefs.getLong(KEY_EXPIRY, -1).takeIf { it >= 0 },
            isFamilyShared = prefs.getBoolean(KEY_FAMILY, false)
        )
    }

    private fun persistStatus(status: SubscriptionStatus) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putBoolean(KEY_ACTIVE, status.isActive)
            putString(KEY_PLAN, status.plan?.name)
            putLong(KEY_EXPIRY, status.expiryDate ?: -1)
            putBoolean(KEY_FAMILY, status.isFamilyShared)
            apply()
        }
    }
}
