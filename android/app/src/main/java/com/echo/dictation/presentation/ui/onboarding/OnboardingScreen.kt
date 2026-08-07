package com.echo.dictation.presentation.ui.onboarding

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant
import kotlinx.coroutines.launch

/**
 * Premium 3-page onboarding carousel with glassmorphism, smooth animations,
 * and page indicators. Replaces the old static WelcomeOnboardingScreen.
 */
@Composable
fun OnboardingScreen(
    onGetStarted: () -> Unit,
    onSkip: () -> Unit,
    onSignIn: () -> Unit = {},
) {
    val pages = onboardingPages
    val pagerState = rememberPagerState(pageCount = { pages.size })
    val scope = rememberCoroutineScope()
    val isLastPage = pagerState.currentPage == pages.lastIndex

    // Background gradient animation
    val infiniteTransition = rememberInfiniteTransition(label = "bg")
    val bgShift by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(10000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "bgShift",
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .drawBehind {
                // Subtle gradient orbs in background for depth
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            PrimaryColor.copy(alpha = 0.06f),
                            Color.Transparent,
                        ),
                        center = Offset(size.width * (0.2f + bgShift * 0.3f), size.height * 0.2f),
                        radius = size.width * 0.5f,
                    ),
                    center = Offset(size.width * (0.2f + bgShift * 0.3f), size.height * 0.2f),
                    radius = size.width * 0.5f,
                )
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            PrimaryVariant.copy(alpha = 0.04f),
                            Color.Transparent,
                        ),
                        center = Offset(size.width * (0.8f - bgShift * 0.2f), size.height * 0.7f),
                        radius = size.width * 0.4f,
                    ),
                    center = Offset(size.width * (0.8f - bgShift * 0.2f), size.height * 0.7f),
                    radius = size.width * 0.4f,
                )
            }
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // ── Top bar with Skip ──
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                TextButton(
                    onClick = onSkip,
                    modifier = Modifier.align(Alignment.CenterEnd),
                ) {
                    Text(
                        text = "Skip",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // ── Pager ──
            HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                beyondViewportPageCount = 1,
            ) { page ->
                OnboardingPageContent(pages[page])
            }

            // ── Bottom section: indicators + buttons ──
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                // Page indicators
                PageIndicator(
                    pageCount = pages.size,
                    currentPage = pagerState.currentPage,
                    currentPageOffsetFraction = pagerState.currentPageOffsetFraction,
                )

                // Action buttons
                AnimatedContent(
                    targetState = isLastPage,
                    transitionSpec = {
                        fadeIn(animationSpec = tween(300)) togetherWith
                            fadeOut(animationSpec = tween(200))
                    },
                    label = "buttonTransition",
                ) { lastPage ->
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        if (lastPage) {
                            // Get Started (final page)
                            Button(
                                onClick = onGetStarted,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(56.dp),
                                shape = RoundedCornerShape(16.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = PrimaryColor,
                                    contentColor = Color(0xFF0A0F2E),
                                ),
                                elevation = ButtonDefaults.buttonElevation(
                                    defaultElevation = 8.dp,
                                    pressedElevation = 4.dp,
                                ),
                            ) {
                                Text(
                                    text = "Get Started",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                )
                            }

                            TextButton(onClick = onSignIn) {
                                Text(
                                    text = "Sign in",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        } else {
                            // Next button
                            Button(
                                onClick = {
                                    scope.launch {
                                        pagerState.animateScrollToPage(pagerState.currentPage + 1)
                                    }
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(56.dp),
                                shape = RoundedCornerShape(16.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = PrimaryColor,
                                    contentColor = Color(0xFF0A0F2E),
                                ),
                                elevation = ButtonDefaults.buttonElevation(
                                    defaultElevation = 6.dp,
                                    pressedElevation = 2.dp,
                                ),
                            ) {
                                Text(
                                    text = "Next",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Single page content ─────────────────────────────────────────────────────

@Composable
private fun OnboardingPageContent(page: OnboardingPage) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // ── Illustration area with glassmorphism container ──
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .padding(16.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(
                    Brush.linearGradient(
                        colors = listOf(
                            Color.White.copy(alpha = 0.04f),
                            Color.White.copy(alpha = 0.02f),
                        ),
                    )
                )
                .drawBehind {
                    // Glassmorphism border effect
                    drawRoundRect(
                        brush = Brush.linearGradient(
                            colors = listOf(
                                Color.White.copy(alpha = 0.1f),
                                Color.White.copy(alpha = 0.03f),
                                Color.White.copy(alpha = 0.08f),
                            ),
                            start = Offset(0f, 0f),
                            end = Offset(size.width, size.height),
                        ),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(24.dp.toPx()),
                        style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.dp.toPx()),
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            when (page.illustrationType) {
                IllustrationType.VOICE_ANYWHERE -> VoiceAnywhereIllustration(
                    modifier = Modifier.fillMaxSize().padding(24.dp)
                )
                IllustrationType.POWERED_BY_AI -> PoweredByAIIllustration(
                    modifier = Modifier.fillMaxSize().padding(24.dp)
                )
                IllustrationType.READY_WHEN_YOU_ARE -> ReadyWhenYouAreIllustration(
                    modifier = Modifier.fillMaxSize().padding(24.dp)
                )
            }
        }

        Spacer(Modifier.height(32.dp))

        // ── Title ──
        Text(
            text = page.title,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.height(12.dp))

        // ── Subtitle ──
        Text(
            text = page.subtitle,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            lineHeight = MaterialTheme.typography.bodyLarge.lineHeight,
        )
    }
}

// ─── Page indicator with animated pill ───────────────────────────────────────

@Composable
private fun PageIndicator(
    pageCount: Int,
    currentPage: Int,
    currentPageOffsetFraction: Float,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(pageCount) { index ->
            val isActive = index == currentPage
            val width by animateDpAsState(
                targetValue = if (isActive) 24.dp else 8.dp,
                animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
                label = "indicatorWidth",
            )
            val color by animateColorAsState(
                targetValue = if (isActive) PrimaryColor else PrimaryColor.copy(alpha = 0.25f),
                animationSpec = tween(300),
                label = "indicatorColor",
            )

            Box(
                modifier = Modifier
                    .height(8.dp)
                    .width(width)
                    .clip(CircleShape)
                    .background(color),
            )
        }
    }
}
