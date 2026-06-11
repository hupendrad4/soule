package com.soulo.app.ui.insights

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.soulo.app.models.DetectedPattern
import com.soulo.app.services.*
import com.soulo.app.ui.theme.SouloColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsightsScreen(storage: StorageService, onNavigate: (String) -> Unit) {
    var patterns by remember { mutableStateOf(storage.loadPatterns()) }
    var entries = remember { storage.loadEntries() }
    var showCognitive by remember { mutableStateOf(false) }
    var showPredictions by remember { mutableStateOf(false) }

    val driftReport = remember(entries) {
        if (entries.size >= 6) {
            val baselines = BiomarkerTrendService.computeTrends(
                entries.mapNotNull { it.biomarkers }, emptyMap()
            ).associate { it.metric to it.baseline }
            CognitiveDriftService.detectDrift(entries, baselines)
        } else null
    }

    val predictions = remember(entries, patterns) {
        if (entries.size >= 5) {
            BehaviorPredictionService.predict(entries, patterns, storage.loadDecisions())
        } else emptyList()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Insights") },
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
                NavigationBarItem(selected = true, onClick = {},
                    icon = { Text("\uD83D\uDCCA") }, label = { Text("Insights") },
                    colors = NavigationBarItemDefaults.colors(selectedIconColor = SouloColors.accent, selectedTextColor = SouloColors.accent, indicatorColor = SouloColors.surfaceLight))
                NavigationBarItem(selected = false, onClick = { onNavigate("settings") },
                    icon = { Text("\u2699\uFE0F") }, label = { Text("Settings") },
                    colors = NavigationBarItemDefaults.colors(indicatorColor = SouloColors.surfaceLight))
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp)
        ) {
            // Cognitive Drift section
            if (driftReport != null) {
                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = SouloColors.cardBackground),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Cognitive Drift", style = MaterialTheme.typography.titleMedium, color = SouloColors.accentWarm)
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("Score: ${"%.2f".format(driftReport.overallSignificance.score)}", color = SouloColors.textPrimary)
                            Text("Trend: ${driftReport.overallSignificance.name}", color = SouloColors.textSecondary)
                            driftReport.drifts.take(3).forEach { drift ->
                                Spacer(modifier = Modifier.height(4.dp))
                                Text(
                                    "${drift.metric.name}: ${"%.2f".format(drift.delta)} (${drift.direction.name})",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = SouloColors.textSecondary
                                )
                            }
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                }
            }

            // Behavior Predictions
            if (predictions.isNotEmpty()) {
                item {
                    Text("Predictions", style = MaterialTheme.typography.titleLarge, color = SouloColors.textPrimary)
                    Spacer(modifier = Modifier.height(8.dp))
                }
                items(predictions) { pred ->
                    Card(
                        colors = CardDefaults.cardColors(containerColor = SouloColors.cardBackground),
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(pred.description, style = MaterialTheme.typography.titleSmall, color = SouloColors.accent)
                                Text("${(pred.probability * 100).toInt()}%", color = SouloColors.textSecondary)
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(pred.suggestedAction ?: pred.description, color = SouloColors.textPrimary, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
                item { Spacer(modifier = Modifier.height(16.dp)) }
            }

            // Patterns
            item {
                Text("Detected Patterns", style = MaterialTheme.typography.titleLarge, color = SouloColors.textPrimary)
                Spacer(modifier = Modifier.height(12.dp))
            }

            items(patterns.filter { it.confidence > 0.3 }) { pattern ->
                PatternCard(pattern)
                Spacer(modifier = Modifier.height(8.dp))
            }

            if (patterns.isEmpty() && driftReport == null && predictions.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(48.dp), contentAlignment = androidx.compose.ui.Alignment.Center) {
                        Text("Record more entries to see insights", color = SouloColors.textSecondary)
                    }
                }
            }

            item { Spacer(modifier = Modifier.height(32.dp)) }

            // Recent entries
            item {
                Text("Recent Entries", style = MaterialTheme.typography.titleLarge, color = SouloColors.textPrimary)
                Spacer(modifier = Modifier.height(12.dp))
                entries.take(5).forEach { entry ->
                    Text(
                        "${entry.formattedDate}: ${entry.transcript?.take(80) ?: "No transcript"}",
                        color = SouloColors.textSecondary,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(vertical = 2.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun PatternCard(pattern: DetectedPattern) {
    Card(
        colors = CardDefaults.cardColors(containerColor = SouloColors.cardBackground),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(pattern.title, style = MaterialTheme.typography.titleSmall, color = SouloColors.accent)
                Text("${(pattern.confidence * 100).toInt()}%", color = SouloColors.textSecondary)
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(pattern.message, color = SouloColors.textPrimary, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
