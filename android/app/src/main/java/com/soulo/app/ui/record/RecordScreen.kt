package com.soulo.app.ui.record

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.soulo.app.models.JournalEntry
import com.soulo.app.models.SubscriptionStatus
import com.soulo.app.services.AudioRecorderService
import com.soulo.app.services.ProcessingPipelineService
import com.soulo.app.services.StorageService
import com.soulo.app.ui.theme.SouloColors
import com.soulo.app.utilities.HapticManager
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordScreen(storage: StorageService, onNavigate: (String) -> Unit) {
    val recorder = remember { AudioRecorderService() }
    val pipeline = remember { ProcessingPipelineService(storage) }
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current

    var isRecording by remember { mutableStateOf(false) }
    var showQuickEntry by remember { mutableStateOf(false) }
    var quickText by remember { mutableStateOf("") }
    var processingStage by remember { mutableStateOf("idle") }
    var entryCount by remember { mutableIntStateOf(storage.entryCount()) }
    var amplitude by remember { mutableFloatStateOf(0f) }
    var recordingDurationMs by remember { mutableLongStateOf(0L) }

    val animatedAmplitude by animateFloatAsState(
        targetValue = amplitude,
        animationSpec = androidx.compose.animation.core.tween(100)
    )

    val subscription = remember {
        mutableStateOf(SubscriptionStatus(entryCount = entryCount))
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Soulo") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = SouloColors.background,
                    titleContentColor = SouloColors.textPrimary
                )
            )
        },
        bottomBar = {
            BottomNavBar(selectedTab = 0, onNavigate = onNavigate)
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            when {
                processingStage != "idle" -> {
                    CircularProgressIndicator(
                        color = SouloColors.accent,
                        modifier = Modifier.size(48.dp)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = processingStage,
                        style = MaterialTheme.typography.bodyLarge,
                        color = SouloColors.textSecondary
                    )
                }

                showQuickEntry -> {
                    QuickEntryInput(
                        text = quickText,
                        onTextChange = { quickText = it },
                        onSubmit = {
                            if (quickText.isNotBlank()) {
                                val entry = JournalEntry(
                                    id = UUID.randomUUID().toString(),
                                    timestamp = System.currentTimeMillis() / 1000,
                                    durationMs = 0,
                                    transcript = quickText,
                                    isQuickEntry = true,
                                    transcriptStatus = com.soulo.app.models.ProcessingStatus.completed,
                                    biomarkersStatus = com.soulo.app.models.ProcessingStatus.completed,
                                    emotionStatus = com.soulo.app.models.ProcessingStatus.completed,
                                    topicsStatus = com.soulo.app.models.ProcessingStatus.completed
                                )
                                scope.launch {
                                    processingStage = "Processing..."
                                    pipeline.process(entry)
                                    processingStage = "idle"
                                    showQuickEntry = false
                                    quickText = ""
                                    entryCount = storage.entryCount()
                                }
                            }
                        },
                        onCancel = {
                            showQuickEntry = false
                            quickText = ""
                        }
                    )
                }

                else -> {
                    if (!subscription.value.canRecord) {
                        Text(
                            "Free trial used. Subscribe to continue.",
                            color = SouloColors.warning,
                            style = MaterialTheme.typography.bodyLarge
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Button(
                            onClick = { onNavigate("subscription") },
                            colors = ButtonDefaults.buttonColors(containerColor = SouloColors.accent)
                        ) { Text("View Plans") }
                    } else {
                        Text(
                            text = if (isRecording) "Recording..." else "Tap to Record",
                            style = MaterialTheme.typography.headlineMedium,
                            color = SouloColors.textPrimary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        if (!subscription.value.isActive) {
                            Text(
                                "${subscription.value.remainingTrial} free entries left",
                                color = SouloColors.accentWarm,
                                style = MaterialTheme.typography.labelLarge
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                        }
                        Text(
                            text = if (isRecording) "Speak naturally" else "3 minutes a day",
                            style = MaterialTheme.typography.bodyMedium,
                            color = SouloColors.textSecondary
                        )

                        Spacer(modifier = Modifier.height(24.dp))

                        if (isRecording) {
                            WaveformView(
                                amplitude = animatedAmplitude,
                                modifier = Modifier.fillMaxWidth().height(80.dp)
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                formatDuration(recordingDurationMs),
                                color = SouloColors.textSecondary
                            )
                            Spacer(modifier = Modifier.height(24.dp))
                        }

                        RecordButton(
                            isRecording = isRecording,
                            onClick = {
                                if (isRecording) {
                                    HapticManager.recordStop()
                                    val file = recorder.stopRecording()
                                    isRecording = false
                                    if (file != null && file.exists()) {
                                        scope.launch {
                                            processingStage = "Transcribing..."
                                            val entry = JournalEntry(
                                                id = UUID.randomUUID().toString(),
                                                timestamp = System.currentTimeMillis() / 1000,
                                                durationMs = recordingDurationMs,
                                                audioFile = file.absolutePath,
                                                biomarkersStatus = com.soulo.app.models.ProcessingStatus.processing,
                                                emotionStatus = com.soulo.app.models.ProcessingStatus.processing,
                                                topicsStatus = com.soulo.app.models.ProcessingStatus.processing
                                            )
                                            pipeline.process(entry)
                                            HapticManager.processingComplete()
                                            processingStage = "idle"
                                            entryCount = storage.entryCount()
                                        }
                                    }
                                } else {
                                    HapticManager.recordStart()
                                    recorder.startRecording()
                                    isRecording = true
                                    scope.launch {
                                        while (recorder.isRecording.get()) {
                                            amplitude = recorder.amplitude.value
                                            recordingDurationMs = recorder.durationMs.value
                                            delay(50)
                                        }
                                    }
                                }
                            }
                        )

                        Spacer(modifier = Modifier.height(32.dp))

                        TextButton(onClick = { showQuickEntry = true }) {
                            Text("Quick Entry (text)", color = SouloColors.accent)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WaveformView(amplitude: Float, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val barCount = 40
        val barWidth = size.width / barCount
        for (i in 0 until barCount) {
            val barHeight = size.height * amplitude * (0.3f + 0.7f * kotlin.math.sin(i.toDouble() * 0.5).toFloat())
            drawRect(
                color = SouloColors.accent,
                topLeft = androidx.compose.ui.geometry.Offset(
                    i * barWidth + 2f,
                    size.height / 2f - barHeight / 2f
                ),
                size = androidx.compose.ui.geometry.Size(
                    barWidth - 4f,
                    barHeight.coerceAtLeast(2f)
                )
            )
        }
    }
}

@Composable
private fun QuickEntryInput(
    text: String,
    onTextChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onCancel: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.End
    ) {
        OutlinedTextField(
            value = text,
            onValueChange = onTextChange,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 120.dp),
            placeholder = { Text("Type your thoughts...") },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onSubmit() }),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = SouloColors.textPrimary,
                unfocusedTextColor = SouloColors.textPrimary,
                focusedBorderColor = SouloColors.accent,
                unfocusedBorderColor = SouloColors.surfaceLight
            )
        )
        Spacer(modifier = Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onCancel) { Text("Cancel") }
            Button(
                onClick = onSubmit,
                enabled = text.isNotBlank(),
                colors = ButtonDefaults.buttonColors(containerColor = SouloColors.accent)
            ) { Text("Save") }
        }
    }
}

@Composable
private fun RecordButton(isRecording: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.size(96.dp),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isRecording) SouloColors.error else SouloColors.accent
        ),
        contentPadding = PaddingValues(0.dp)
    ) {
        Box(
            modifier = Modifier
                .size(if (isRecording) 36.dp else 48.dp)
                .clip(if (isRecording) RoundedCornerShape(4.dp) else CircleShape)
                .background(SouloColors.textPrimary)
        )
    }
}

@Composable
fun BottomNavBar(selectedTab: Int, onNavigate: (String) -> Unit) {
    NavigationBar(
        containerColor = SouloColors.surface,
        contentColor = SouloColors.textPrimary
    ) {
        NavigationBarItem(
            selected = selectedTab == 0,
            onClick = {},
            icon = { Text("\uD83C\uDFA4") },
            label = { Text("Record") },
            colors = navColors()
        )
        NavigationBarItem(
            selected = selectedTab == 1,
            onClick = { onNavigate("history") },
            icon = { Text("\uD83D\uDCCB") },
            label = { Text("History") },
            colors = navColors()
        )
        NavigationBarItem(
            selected = selectedTab == 2,
            onClick = { onNavigate("insights") },
            icon = { Text("\uD83D\uDCCA") },
            label = { Text("Insights") },
            colors = navColors()
        )
        NavigationBarItem(
            selected = selectedTab == 3,
            onClick = { onNavigate("settings") },
            icon = { Text("\u2699\uFE0F") },
            label = { Text("Settings") },
            colors = navColors()
        )
    }
}

private fun navColors() = NavigationBarItemDefaults.colors(
    selectedIconColor = SouloColors.accent,
    selectedTextColor = SouloColors.accent,
    indicatorColor = SouloColors.surfaceLight
)

private fun formatDuration(ms: Long): String {
    val secs = ms / 1000
    val m = secs / 60
    val s = secs % 60
    return "%d:%02d".format(m, s)
}
