package com.echo.dictation.presentation.ui.onboarding

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.unit.dp
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant
import kotlin.math.*

// ─── Page 1: Voice Anywhere ──────────────────────────────────────────────────

/**
 * Animated illustration for "Your Voice. Anywhere."
 * - Breathing waveform bars
 * - Floating orb with glow pulse
 * - Subtle particles rising
 * - Cursor blink effect
 */
@Composable
fun VoiceAnywhereIllustration(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "voice")

    // Waveform phase animation
    val wavePhase by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 2f * PI.toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "wavePhase",
    )

    // Orb breathing scale
    val orbScale by infiniteTransition.animateFloat(
        initialValue = 0.85f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "orbScale",
    )

    // Glow pulse alpha
    val glowAlpha by infiniteTransition.animateFloat(
        initialValue = 0.15f,
        targetValue = 0.45f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glowAlpha",
    )

    // Particle float offset
    val particleOffset by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(4000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "particleOffset",
    )

    // Cursor blink
    val cursorAlpha by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(800, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "cursorBlink",
    )

    val primaryColor = PrimaryColor
    val primaryVariant = PrimaryVariant

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val cx = w / 2f
        val cy = h / 2f

        // ── Background glow orb ──
        val orbRadius = w * 0.18f * orbScale
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    primaryColor.copy(alpha = glowAlpha),
                    primaryColor.copy(alpha = glowAlpha * 0.4f),
                    Color.Transparent,
                ),
                center = Offset(cx, cy - h * 0.05f),
                radius = orbRadius * 2.5f,
            ),
            center = Offset(cx, cy - h * 0.05f),
            radius = orbRadius * 2.5f,
        )

        // ── Central orb with gradient ──
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(primaryColor, primaryVariant, primaryVariant.copy(alpha = 0.6f)),
                center = Offset(cx - orbRadius * 0.3f, cy - h * 0.05f - orbRadius * 0.3f),
                radius = orbRadius * 1.2f,
            ),
            center = Offset(cx, cy - h * 0.05f),
            radius = orbRadius,
        )

        // ── Waveform bars ──
        val barCount = 24
        val barWidth = w * 0.012f
        val barMaxHeight = h * 0.12f
        val barSpacing = w * 0.025f
        val barStartX = cx - (barCount / 2f) * barSpacing

        for (i in 0 until barCount) {
            val x = barStartX + i * barSpacing
            val amplitude = sin(wavePhase + i * 0.4f) * 0.5f + 0.5f
            val barHeight = barMaxHeight * (0.2f + amplitude * 0.8f)
            val barY = cy + h * 0.18f

            val barAlpha = 0.4f + amplitude * 0.5f
            drawRoundRect(
                color = primaryColor.copy(alpha = barAlpha),
                topLeft = Offset(x - barWidth / 2f, barY - barHeight / 2f),
                size = Size(barWidth, barHeight),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(barWidth / 2f),
            )
        }

        // ── Floating particles ──
        val particleCount = 8
        for (i in 0 until particleCount) {
            val angle = (2f * PI.toFloat() / particleCount) * i + particleOffset * 2f * PI.toFloat()
            val radius = orbRadius * 1.8f + sin(particleOffset * PI.toFloat() * 2f + i) * 20f
            val px = cx + cos(angle) * radius
            val py = cy - h * 0.05f + sin(angle) * radius * 0.6f
            val pAlpha = (0.3f + sin(particleOffset * PI.toFloat() * 2f + i * 0.5f) * 0.3f).coerceIn(0f, 1f)
            val pSize = 2f + sin(angle + wavePhase) * 1.5f

            drawCircle(
                color = primaryColor.copy(alpha = pAlpha),
                radius = pSize,
                center = Offset(px, py),
            )
        }

        // ── Cursor line (bottom) ──
        val cursorX = cx + w * 0.12f
        val cursorY = cy + h * 0.30f
        drawRoundRect(
            color = primaryColor.copy(alpha = cursorAlpha * 0.8f),
            topLeft = Offset(cursorX, cursorY),
            size = Size(2.dp.toPx(), 18.dp.toPx()),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.dp.toPx()),
        )

        // ── Text placeholder lines (simulating text insertion) ──
        val lineY = cursorY + 4.dp.toPx()
        val lineStartX = cx - w * 0.25f
        for (i in 0..2) {
            val lineWidth = if (i == 2) w * 0.3f else w * 0.5f
            drawRoundRect(
                color = Color.White.copy(alpha = 0.08f),
                topLeft = Offset(lineStartX, lineY + i * 14.dp.toPx()),
                size = Size(lineWidth, 4.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()),
            )
        }
    }
}

// ─── Page 2: Powered by AI ───────────────────────────────────────────────────

/**
 * Animated illustration for "Powered by AI"
 * - Central AI spark/star
 * - Document morphing effect
 * - Animated particles orbiting
 * - Text transformation lines
 */
@Composable
fun PoweredByAIIllustration(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "ai")

    // Star rotation
    val starRotation by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(8000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "starRotation",
    )

    // Pulse
    val pulse by infiniteTransition.animateFloat(
        initialValue = 0.7f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse",
    )

    // Document morph
    val morphProgress by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "morph",
    )

    // Orbit angle
    val orbitAngle by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 2f * PI.toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(5000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "orbit",
    )

    val primaryColor = PrimaryColor
    val primaryVariant = PrimaryVariant
    val accentBlue = Color(0xFF6B8AFF)

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val cx = w / 2f
        val cy = h / 2f

        // ── Outer glow ──
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    primaryColor.copy(alpha = 0.2f * pulse),
                    Color.Transparent,
                ),
                center = Offset(cx, cy),
                radius = w * 0.4f,
            ),
            center = Offset(cx, cy),
            radius = w * 0.4f,
        )

        // ── Document shape (left) ──
        val docLeft = cx - w * 0.22f
        val docTop = cy - h * 0.12f
        val docWidth = w * 0.18f
        val docHeight = h * 0.22f

        drawRoundRect(
            color = Color.White.copy(alpha = 0.06f + morphProgress * 0.04f),
            topLeft = Offset(docLeft, docTop),
            size = Size(docWidth, docHeight),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(8.dp.toPx()),
        )

        // Document lines (source text)
        for (i in 0..4) {
            val lineWidth = docWidth * (0.5f + (1f - morphProgress) * 0.3f) * if (i == 4) 0.6f else 1f
            drawRoundRect(
                color = Color.White.copy(alpha = 0.12f * (1f - morphProgress * 0.5f)),
                topLeft = Offset(docLeft + 8.dp.toPx(), docTop + 12.dp.toPx() + i * 10.dp.toPx()),
                size = Size(lineWidth, 3.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.5f.dp.toPx()),
            )
        }

        // ── Transformed document (right) ──
        val doc2Left = cx + w * 0.04f
        val doc2Top = cy - h * 0.12f

        drawRoundRect(
            color = primaryColor.copy(alpha = 0.08f + morphProgress * 0.06f),
            topLeft = Offset(doc2Left, doc2Top),
            size = Size(docWidth, docHeight),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(8.dp.toPx()),
            style = Stroke(width = 1.dp.toPx()),
        )

        // Enhanced lines (target text)
        for (i in 0..4) {
            val lineWidth = docWidth * (0.4f + morphProgress * 0.4f) * if (i == 4) 0.6f else 1f
            drawRoundRect(
                color = primaryColor.copy(alpha = 0.15f + morphProgress * 0.3f),
                topLeft = Offset(doc2Left + 8.dp.toPx(), doc2Top + 12.dp.toPx() + i * 10.dp.toPx()),
                size = Size(lineWidth, 3.dp.toPx()),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.5f.dp.toPx()),
            )
        }

        // ── Arrow between documents ──
        val arrowY = cy
        val arrowStartX = docLeft + docWidth + 4.dp.toPx()
        val arrowEndX = doc2Left - 4.dp.toPx()
        val arrowAlpha = 0.3f + morphProgress * 0.4f

        drawLine(
            color = primaryColor.copy(alpha = arrowAlpha),
            start = Offset(arrowStartX, arrowY),
            end = Offset(arrowEndX, arrowY),
            strokeWidth = 1.5f.dp.toPx(),
            cap = StrokeCap.Round,
        )

        // Arrow head
        val headSize = 4.dp.toPx()
        drawLine(
            color = primaryColor.copy(alpha = arrowAlpha),
            start = Offset(arrowEndX, arrowY),
            end = Offset(arrowEndX - headSize, arrowY - headSize),
            strokeWidth = 1.5f.dp.toPx(),
            cap = StrokeCap.Round,
        )
        drawLine(
            color = primaryColor.copy(alpha = arrowAlpha),
            start = Offset(arrowEndX, arrowY),
            end = Offset(arrowEndX - headSize, arrowY + headSize),
            strokeWidth = 1.5f.dp.toPx(),
            cap = StrokeCap.Round,
        )

        // ── Central AI spark (4-point star) ──
        val starCx = cx
        val starCy = cy - h * 0.22f
        val starSize = w * 0.06f * pulse

        rotate(degrees = starRotation, pivot = Offset(starCx, starCy)) {
            val starPath = Path().apply {
                // 4-point star
                val outer = starSize
                val inner = starSize * 0.3f
                for (j in 0 until 8) {
                    val r = if (j % 2 == 0) outer else inner
                    val angle = (j * PI.toFloat() / 4f) - PI.toFloat() / 2f
                    val x = starCx + cos(angle) * r
                    val y = starCy + sin(angle) * r
                    if (j == 0) moveTo(x, y) else lineTo(x, y)
                }
                close()
            }
            drawPath(
                path = starPath,
                brush = Brush.linearGradient(
                    colors = listOf(primaryColor, accentBlue),
                    start = Offset(starCx - starSize, starCy - starSize),
                    end = Offset(starCx + starSize, starCy + starSize),
                ),
            )
        }

        // ── Orbiting particles ──
        val orbitRadius = w * 0.28f
        for (i in 0 until 6) {
            val angle = orbitAngle + i * (2f * PI.toFloat() / 6f)
            val px = cx + cos(angle) * orbitRadius * (0.8f + sin(angle * 0.5f) * 0.2f)
            val py = cy + sin(angle) * orbitRadius * 0.4f
            val pAlpha = (0.2f + sin(angle + orbitAngle) * 0.3f).coerceIn(0f, 0.6f)
            val pRadius = 2f + sin(angle) * 1.5f

            drawCircle(
                color = primaryColor.copy(alpha = pAlpha),
                radius = pRadius,
                center = Offset(px, py),
            )
        }
    }
}

// ─── Page 3: Ready When You Are ──────────────────────────────────────────────

/**
 * Animated illustration for "Ready When You Are"
 * - Floating assistant orb with hover animation
 * - App grid suggestion
 * - Cursor movement
 * - Soft wave pulse
 */
@Composable
fun ReadyWhenYouAreIllustration(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "ready")

    // Float hover
    val hoverOffset by infiniteTransition.animateFloat(
        initialValue = -8f,
        targetValue = 8f,
        animationSpec = infiniteRepeatable(
            animation = tween(2500, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "hover",
    )

    // Wave pulse radius
    val waveRadius by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(3000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "wave",
    )

    // Cursor movement
    val cursorX by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "cursorX",
    )

    // Glow
    val glowAlpha by infiniteTransition.animateFloat(
        initialValue = 0.2f,
        targetValue = 0.5f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glow",
    )

    val primaryColor = PrimaryColor
    val primaryVariant = PrimaryVariant

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height
        val cx = w / 2f
        val cy = h / 2f

        // ── Wave pulse rings ──
        val maxWaveRadius = w * 0.35f
        for (i in 0 until 3) {
            val progress = ((waveRadius + i * 0.33f) % 1f)
            val ringRadius = maxWaveRadius * progress
            val ringAlpha = (1f - progress) * 0.15f

            drawCircle(
                color = primaryColor.copy(alpha = ringAlpha),
                radius = ringRadius,
                center = Offset(cx, cy - h * 0.05f + hoverOffset),
                style = Stroke(width = 1.5f.dp.toPx()),
            )
        }

        // ── Central floating orb (assistant) ──
        val orbRadius = w * 0.12f
        val orbCy = cy - h * 0.05f + hoverOffset

        // Outer glow
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    primaryColor.copy(alpha = glowAlpha),
                    Color.Transparent,
                ),
                center = Offset(cx, orbCy),
                radius = orbRadius * 2.2f,
            ),
            center = Offset(cx, orbCy),
            radius = orbRadius * 2.2f,
        )

        // Orb
        drawCircle(
            brush = Brush.linearGradient(
                colors = listOf(primaryColor, primaryVariant),
                start = Offset(cx - orbRadius, orbCy - orbRadius),
                end = Offset(cx + orbRadius, orbCy + orbRadius),
            ),
            center = Offset(cx, orbCy),
            radius = orbRadius,
        )

        // Inner highlight
        drawCircle(
            color = Color.White.copy(alpha = 0.2f),
            center = Offset(cx - orbRadius * 0.25f, orbCy - orbRadius * 0.25f),
            radius = orbRadius * 0.35f,
        )

        // ── App grid (small rounded squares) ──
        val gridStartX = cx - w * 0.2f
        val gridStartY = cy + h * 0.18f
        val cellSize = w * 0.06f
        val cellGap = w * 0.04f
        val appColors = listOf(
            Color(0xFF4A5568).copy(alpha = 0.3f),
            Color(0xFF5A6A80).copy(alpha = 0.3f),
            primaryColor.copy(alpha = 0.4f),
            Color(0xFF4A5568).copy(alpha = 0.25f),
            Color(0xFF5A6A80).copy(alpha = 0.25f),
            Color(0xFF4A5568).copy(alpha = 0.2f),
        )

        for (row in 0 until 2) {
            for (col in 0 until 3) {
                val idx = row * 3 + col
                val x = gridStartX + col * (cellSize + cellGap)
                val y = gridStartY + row * (cellSize + cellGap)
                drawRoundRect(
                    color = appColors[idx],
                    topLeft = Offset(x, y),
                    size = Size(cellSize, cellSize),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(6.dp.toPx()),
                )
            }
        }

        // Highlight on the "active" app (the lavender one)
        val activeX = gridStartX + 2 * (cellSize + cellGap)
        val activeY = gridStartY
        drawRoundRect(
            color = primaryColor.copy(alpha = glowAlpha * 0.6f),
            topLeft = Offset(activeX - 2.dp.toPx(), activeY - 2.dp.toPx()),
            size = Size(cellSize + 4.dp.toPx(), cellSize + 4.dp.toPx()),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(8.dp.toPx()),
            style = Stroke(width = 1.dp.toPx()),
        )

        // ── Cursor with movement ──
        val cursorBaseX = cx - w * 0.1f
        val cursorY2 = cy + h * 0.14f
        val cursorActualX = cursorBaseX + cursorX * w * 0.2f

        drawRoundRect(
            color = primaryColor.copy(alpha = 0.8f),
            topLeft = Offset(cursorActualX, cursorY2),
            size = Size(2.dp.toPx(), 14.dp.toPx()),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.dp.toPx()),
        )

        // Text line behind cursor
        drawRoundRect(
            color = Color.White.copy(alpha = 0.06f),
            topLeft = Offset(cursorBaseX - w * 0.05f, cursorY2 + 4.dp.toPx()),
            size = Size(cursorActualX - cursorBaseX + w * 0.05f, 3.dp.toPx()),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(1.5f.dp.toPx()),
        )
    }
}
