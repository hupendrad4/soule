package com.soulo.app.ui.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.soulo.app.models.JournalEntry
import com.soulo.app.services.StorageService
import com.soulo.app.ui.theme.SouloColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(storage: StorageService, onNavigate: (String) -> Unit) {
    var entries by remember { mutableStateOf(storage.loadEntries()) }
    var searchQuery by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("History") },
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
                NavigationBarItem(selected = true, onClick = {},
                    icon = { Text("\uD83D\uDCCB") }, label = { Text("History") },
                    colors = NavigationBarItemDefaults.colors(selectedIconColor = SouloColors.accent, selectedTextColor = SouloColors.accent, indicatorColor = SouloColors.surfaceLight))
                NavigationBarItem(selected = false, onClick = { onNavigate("insights") },
                    icon = { Text("\uD83D\uDCCA") }, label = { Text("Insights") },
                    colors = NavigationBarItemDefaults.colors(indicatorColor = SouloColors.surfaceLight))
                NavigationBarItem(selected = false, onClick = { onNavigate("settings") },
                    icon = { Text("\u2699\uFE0F") }, label = { Text("Settings") },
                    colors = NavigationBarItemDefaults.colors(indicatorColor = SouloColors.surfaceLight))
            }
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it
                    entries = storage.loadEntries() },
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                placeholder = { Text("Search entries...") },
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = SouloColors.textPrimary,
                    unfocusedTextColor = SouloColors.textPrimary,
                    focusedBorderColor = SouloColors.accent,
                    unfocusedBorderColor = SouloColors.surfaceLight
                )
            )

            LazyColumn(contentPadding = PaddingValues(horizontal = 16.dp)) {
                items(entries) { entry ->
                    EntryCard(entry)
                }
                if (entries.isEmpty()) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) {
                            Text("No entries yet", color = SouloColors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EntryCard(entry: JournalEntry) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        colors = CardDefaults.cardColors(containerColor = SouloColors.cardBackground)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(entry.formattedDate, color = SouloColors.accent, style = MaterialTheme.typography.labelLarge)
                Text(entry.durationFormatted, color = SouloColors.textSecondary, style = MaterialTheme.typography.labelSmall)
            }
            Spacer(modifier = Modifier.height(8.dp))
            entry.transcript?.let {
                Text(it, maxLines = 2, overflow = TextOverflow.Ellipsis, color = SouloColors.textPrimary)
            }
            if (entry.emotion != null) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    entry.emotion!!.primaryEmotion.name,
                    color = SouloColors.accentWarm,
                    style = MaterialTheme.typography.labelSmall
                )
            }
        }
    }
}
