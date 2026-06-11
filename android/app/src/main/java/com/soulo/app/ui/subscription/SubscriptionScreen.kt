package com.soulo.app.ui.subscription

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.soulo.app.models.SubscriptionPlan
import com.soulo.app.models.SubscriptionStatus
import com.soulo.app.services.StorageService
import com.soulo.app.services.SubscriptionService
import com.soulo.app.ui.theme.SouloColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionScreen(storage: StorageService, onNavigate: () -> Unit) {
    val context = LocalContext.current
    val subStatus by SubscriptionService.status.collectAsState()
    var isPurchasing by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Soulo Premium") },
                navigationIcon = {
                    TextButton(onClick = onNavigate) { Text("Close", color = SouloColors.accent) }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = SouloColors.background,
                    titleContentColor = SouloColors.textPrimary
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (subStatus.isActive) {
                Text("\u2728", style = MaterialTheme.typography.displayLarge)
                Spacer(modifier = Modifier.height(16.dp))
                Text("You are subscribed!", style = MaterialTheme.typography.headlineMedium, color = SouloColors.textPrimary)
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "${subStatus.plan?.displayName ?: "Premium"} plan",
                    color = SouloColors.accent,
                    style = MaterialTheme.typography.titleMedium
                )
            } else {
                Text("\uD83E\uDDE0", style = MaterialTheme.typography.displayLarge)
                Spacer(modifier = Modifier.height(16.dp))
                Text("Understand Yourself", style = MaterialTheme.typography.headlineMedium, color = SouloColors.textPrimary)
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Soulo analyzes your speech patterns to reveal hidden insights about your emotional well-being.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = SouloColors.textSecondary,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(24.dp))

                SubscriptionPlanCard(
                    plan = SubscriptionPlan.monthly,
                    features = listOf("Unlimited entries", "All insights", "Priority support"),
                    isPurchasing = isPurchasing,
                    onPurchase = {
                        isPurchasing = true
                        SubscriptionService.launchBillingFlow(context as android.app.Activity, SubscriptionPlan.monthly) {
                            isPurchasing = false
                        }
                    }
                )
                Spacer(modifier = Modifier.height(12.dp))
                SubscriptionPlanCard(
                    plan = SubscriptionPlan.annual,
                    features = listOf("Unlimited entries", "All insights", "Priority support", "Best value"),
                    recommended = true,
                    isPurchasing = isPurchasing,
                    onPurchase = {
                        isPurchasing = true
                        SubscriptionService.launchBillingFlow(context as android.app.Activity, SubscriptionPlan.annual) {
                            isPurchasing = false
                        }
                    }
                )
                Spacer(modifier = Modifier.height(12.dp))
                SubscriptionPlanCard(
                    plan = SubscriptionPlan.family,
                    features = listOf("Everything in Premium", "Share with up to 5 family", "Separate private journals"),
                    isPurchasing = isPurchasing,
                    onPurchase = {
                        isPurchasing = true
                        SubscriptionService.launchBillingFlow(context as android.app.Activity, SubscriptionPlan.family) {
                            isPurchasing = false
                        }
                    }
                )

                Spacer(modifier = Modifier.height(16.dp))
                Text("Secure payment via Google Play.", color = SouloColors.textSecondary, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun SubscriptionPlanCard(
    plan: SubscriptionPlan,
    features: List<String>,
    recommended: Boolean = false,
    isPurchasing: Boolean = false,
    onPurchase: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = if (recommended) SouloColors.accent.copy(alpha = 0.15f) else SouloColors.cardBackground
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(plan.displayName, style = MaterialTheme.typography.titleMedium, color = SouloColors.textPrimary)
                Text(plan.priceDisplay, style = MaterialTheme.typography.titleLarge, color = SouloColors.accent)
            }
            if (recommended) {
                Text("Best Value", color = SouloColors.accent, style = MaterialTheme.typography.labelSmall)
            }
            Spacer(modifier = Modifier.height(8.dp))
            features.forEach { feature ->
                Text("\u2713 $feature", color = SouloColors.textSecondary, style = MaterialTheme.typography.bodySmall)
            }
            Spacer(modifier = Modifier.height(12.dp))
            Button(
                onClick = onPurchase,
                enabled = !isPurchasing,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = SouloColors.accent)
            ) {
                Text(if (isPurchasing) "Processing..." else "Subscribe")
            }
        }
    }
}
