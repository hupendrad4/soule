package com.soulo.app.ui.settings

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.soulo.app.SouloApplication
import com.soulo.app.models.Settings
import com.soulo.app.services.*
import com.soulo.app.ui.theme.SouloColors
import com.soulo.app.utilities.RateAppPrompt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(storage: StorageService, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var settings by remember { mutableStateOf(storage.loadSettings()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = SouloColors.background,
                    titleContentColor = SouloColors.textPrimary
                )
            )
        },
        bottomBar = {
            NavigationBar(
                containerColor = SouloColors.surface,
                contentColor = SouloColors.textPrimary
            ) {
                NavigationBarItem(selected = false, onClick = { onNavigate("record") },
                    icon = { Text("\uD83C\uDFA4") }, label = { Text("Record") },
                    colors = NavigationBarItemDefaults.colors(indicatorColor = SouloColors.surfaceLight))
                NavigationBarItem(selected = false, onClick = { onNavigate("history") },
                    icon = { Text("\uD83D\uDCCB") }, label = { Text("History") },
                    colors = NavigationBarItemDefaults.colors(indicatorColor = SouloColors.surfaceLight))
                NavigationBarItem(selected = false, onClick = { onNavigate("insights") },
                    icon = { Text("\uD83D\uDCCA") }, label = { Text("Insights") },
                    colors = NavigationBarItemDefaults.colors(indicatorColor = SouloColors.surfaceLight))
                NavigationBarItem(selected = true, onClick = {},
                    icon = { Text("\u2699\uFE0F") }, label = { Text("Settings") },
                    colors = NavigationBarItemDefaults.colors(selectedIconColor = SouloColors.accent, selectedTextColor = SouloColors.accent, indicatorColor = SouloColors.surfaceLight))
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)
        ) {
            Text("Preferences", style = MaterialTheme.typography.titleLarge, color = SouloColors.textPrimary)
            Spacer(modifier = Modifier.height(16.dp))

            SettingToggle(
                title = "Daily Reminder",
                description = "Get reminded to journal every evening",
                checked = settings.dailyReminderEnabled,
                onCheckedChange = {
                    settings = settings.copy(dailyReminderEnabled = it)
                    storage.saveSettings(settings)
                }
            )

            SettingToggle(
                title = "Daily Insights",
                description = "Receive morning insight notifications",
                checked = settings.dailyInsightEnabled,
                onCheckedChange = {
                    settings = settings.copy(dailyInsightEnabled = it)
                    storage.saveSettings(settings)
                }
            )

            SettingToggle(
                title = "Keep Raw Audio",
                description = "Save original recording after processing",
                checked = settings.keepRawAudio,
                onCheckedChange = {
                    settings = settings.copy(keepRawAudio = it)
                    storage.saveSettings(settings)
                }
            )

            SettingToggle(
                title = "Haptic Feedback",
                description = "Vibration feedback during recording",
                checked = settings.hapticFeedback,
                onCheckedChange = {
                    settings = settings.copy(hapticFeedback = it)
                    storage.saveSettings(settings)
                }
            )

            Spacer(modifier = Modifier.height(24.dp))

            Text("Data", style = MaterialTheme.typography.titleLarge, color = SouloColors.textPrimary)
            Spacer(modifier = Modifier.height(12.dp))

            Button(
                onClick = {
                    scope.launch {
                        val entries = storage.loadEntries()
                        val patterns = storage.loadPatterns()
                        val decisions = storage.loadDecisions()
                        val text = TherapistShareService.generateShareText(entries, patterns, decisions)
                        TherapistShareService.shareText(text)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = SouloColors.cardBackground)
            ) { Text("Share Therapy Summary", color = SouloColors.textPrimary) }

            Spacer(modifier = Modifier.height(8.dp))

            Button(
                onClick = {
                    scope.launch {
                        val file = withContext(Dispatchers.IO) {
                            ExportService.exportEntries(storage.loadEntries())
                        }
                        ExportService.shareFile(file)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = SouloColors.cardBackground)
            ) { Text("Export Journal", color = SouloColors.textPrimary) }

            Spacer(modifier = Modifier.height(24.dp))

            Text("Account", style = MaterialTheme.typography.titleLarge, color = SouloColors.textPrimary)
            Spacer(modifier = Modifier.height(12.dp))

            Button(
                onClick = { onNavigate("subscription") },
                colors = ButtonDefaults.buttonColors(containerColor = SouloColors.accent),
                modifier = Modifier.fillMaxWidth()
            ) { Text("Manage Subscription") }

            Spacer(modifier = Modifier.height(24.dp))

            Text("Support", style = MaterialTheme.typography.titleLarge, color = SouloColors.textPrimary)
            Spacer(modifier = Modifier.height(12.dp))

            TextButton(onClick = {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://soulo.app/privacy"))
                context.startActivity(intent)
            }) { Text("Privacy Policy", color = SouloColors.accent) }
            TextButton(onClick = {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://soulo.app/terms"))
                context.startActivity(intent)
            }) { Text("Terms of Service", color = SouloColors.accent) }
            TextButton(onClick = {
                RateAppPrompt.launchReview(context as android.app.Activity)
            }) { Text("Rate Soulo", color = SouloColors.accent) }

            Spacer(modifier = Modifier.weight(1f))
            Text(
                "Soulo v1.0.0",
                color = SouloColors.textSecondary,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
        }
    }
}

@Composable
private fun SettingToggle(
    title: String, description: String,
    checked: Boolean, onCheckedChange: (Boolean) -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = SouloColors.cardBackground),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, color = SouloColors.textPrimary)
                Text(description, color = SouloColors.textSecondary, style = MaterialTheme.typography.bodySmall)
            }
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                colors = SwitchDefaults.colors(checkedTrackColor = SouloColors.accent)
            )
        }
    }
}
