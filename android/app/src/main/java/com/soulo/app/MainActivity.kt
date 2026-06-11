package com.soulo.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.soulo.app.services.StorageService
import com.soulo.app.services.SubscriptionService
import com.soulo.app.ui.history.HistoryScreen
import com.soulo.app.ui.insights.InsightsScreen
import com.soulo.app.ui.onboarding.OnboardingScreen
import com.soulo.app.ui.record.RecordScreen
import com.soulo.app.ui.settings.SettingsScreen
import com.soulo.app.ui.subscription.SubscriptionScreen
import com.soulo.app.ui.theme.SouloColors

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val storage = StorageService(this)

        setContent {
            MaterialTheme(
                colorScheme = androidx.compose.material3.darkColorScheme(
                    primary = SouloColors.accent,
                    secondary = SouloColors.accentWarm,
                    background = SouloColors.background,
                    surface = SouloColors.surface,
                    onPrimary = SouloColors.textPrimary,
                    onSecondary = SouloColors.textPrimary,
                    onBackground = SouloColors.textPrimary,
                    onSurface = SouloColors.textPrimary,
                    error = SouloColors.error
                )
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    AppNavigation(storage)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        SubscriptionService.queryExistingPurchases()
    }
}

@Composable
fun AppNavigation(storage: StorageService) {
    val navController = rememberNavController()
    var showOnboarding by remember {
        mutableStateOf(storage.loadSettings().run { !hasCompletedOnboarding })
    }

    LaunchedEffect(Unit) {
        SubscriptionService.initialize()
    }

    if (showOnboarding) {
        OnboardingScreen(
            onComplete = {
                val settings = storage.loadSettings().copy(hasCompletedOnboarding = true)
                storage.saveSettings(settings)
                showOnboarding = false
            }
        )
    } else {
        NavHost(navController = navController, startDestination = "record") {
            composable("record") {
                RecordScreen(
                    storage = storage,
                    onNavigate = { route -> navController.navigate(route) }
                )
            }
            composable("history") {
                HistoryScreen(
                    storage = storage,
                    onNavigate = { route -> navController.navigate(route) }
                )
            }
            composable("insights") {
                InsightsScreen(
                    storage = storage,
                    onNavigate = { route -> navController.navigate(route) }
                )
            }
            composable("settings") {
                SettingsScreen(
                    storage = storage,
                    onNavigate = { route -> navController.navigate(route) }
                )
            }
            composable("subscription") {
                SubscriptionScreen(
                    storage = storage,
                    onNavigate = { navController.popBackStack() }
                )
            }
        }
    }
}
