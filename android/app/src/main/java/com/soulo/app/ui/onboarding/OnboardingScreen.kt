package com.soulo.app.ui.onboarding

import androidx.compose.animation.*
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.soulo.app.ui.theme.SouloColors
import kotlinx.coroutines.launch

data class OnboardingPage(
    val emoji: String,
    val title: String,
    val subtitle: String,
    val detail: String
)

private val pages = listOf(
    OnboardingPage(
        "\uD83E\uDDE0",
        "Welcome to Soulo",
        "Your private AI voice journal",
        "Speak your mind freely. Everything stays on your device."
    ),
    OnboardingPage(
        "\uD83C\uDFA4",
        "Record Your Day",
        "Daily voice check-ins",
        "Just 3 minutes a day. Soulo transcribes and analyzes your speech patterns."
    ),
    OnboardingPage(
        "\uD83D\uDCCA",
        "Discover Patterns",
        "Understand yourself better",
        "Track emotional trends, cognitive drift, and behavioral patterns over time."
    ),
    OnboardingPage(
        "\uD83D\uDD12",
        "Privacy First",
        "All data stays on your device",
        "No account required. No analytics. No cloud uploads. Your voice is yours."
    )
)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(onComplete: () -> Unit) {
    val pagerState = rememberPagerState(pageCount = { pages.size })
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Skip button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End
        ) {
            TextButton(onClick = onComplete) {
                Text("Skip", color = SouloColors.textSecondary)
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        // Pager
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.weight(3f)
        ) { pageIndex ->
            PageContent(pages[pageIndex])
        }

        Spacer(modifier = Modifier.weight(0.5f))

        // Page indicators
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center
        ) {
            repeat(pages.size) { index ->
                Box(
                    modifier = Modifier
                        .padding(4.dp)
                        .size(if (pagerState.currentPage == index) 10.dp else 8.dp)
                        .clip(CircleShape)
                        .then(
                            if (pagerState.currentPage == index) Modifier
                            else Modifier
                        )
                ) {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        shape = CircleShape,
                        color = if (pagerState.currentPage == index) SouloColors.accent else SouloColors.surfaceLight
                    ) {}
                }
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        // Next / Get Started button
        Button(
            onClick = {
                if (pagerState.currentPage < pages.size - 1) {
                    scope.launch {
                        pagerState.animateScrollToPage(pagerState.currentPage + 1)
                    }
                } else {
                    onComplete()
                }
            },
            modifier = Modifier.fillMaxWidth().height(56.dp),
            colors = ButtonDefaults.buttonColors(containerColor = SouloColors.accent),
            shape = MaterialTheme.shapes.medium
        ) {
            Text(
                if (pagerState.currentPage < pages.size - 1) "Next" else "Get Started",
                style = MaterialTheme.typography.titleMedium
            )
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun PageContent(page: OnboardingPage) {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(page.emoji, style = MaterialTheme.typography.displayLarge)
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            page.title,
            style = MaterialTheme.typography.headlineMedium,
            color = SouloColors.textPrimary,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            page.subtitle,
            style = MaterialTheme.typography.bodyLarge,
            color = SouloColors.accentWarm,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            page.detail,
            style = MaterialTheme.typography.bodyMedium,
            color = SouloColors.textSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 24.dp)
        )
    }
}
