package com.echo.dictation.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Typography
import androidx.compose.material3.Shapes
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape

// ─── Brand colours ──────────────────────────────────────────────────────────
val PrimaryColor       = Color(0xFF9AA8FF)   // #9AA8FF
val PrimaryVariant     = Color(0xFF7C8CFF)   // #7C8CFF  (accent)
val BackgroundColor    = Color(0xFF121212)   // #121212
val SurfaceColor       = Color(0xFF1C1C22)   // slightly lighter surface
val CardColor          = Color(0xFF232329)   // #232329
val OnPrimaryColor     = Color(0xFF0A0F2E)
val OnBackgroundColor  = Color(0xFFE8EAF6)
val OnSurfaceColor     = Color(0xFFE8EAF6)
val OnSurfaceVariant   = Color(0xFF9E9EAE)
val ErrorColor         = Color(0xFFCF6679)
val OutlineColor       = Color(0xFF3A3A4A)
val SecondaryColor     = Color(0xFFB0B8FF)
val TertiaryColor      = Color(0xFFCFB7FF)

// ─── Dark colour scheme ──────────────────────────────────────────────────────
private val DarkColorScheme = darkColorScheme(
    primary            = PrimaryColor,
    onPrimary          = OnPrimaryColor,
    primaryContainer   = Color(0xFF1E245C),
    onPrimaryContainer = Color(0xFFDDE1FF),
    secondary          = SecondaryColor,
    onSecondary        = Color(0xFF0D1550),
    secondaryContainer = Color(0xFF232C6A),
    onSecondaryContainer = Color(0xFFDDE1FF),
    tertiary           = TertiaryColor,
    onTertiary         = Color(0xFF25005A),
    tertiaryContainer  = Color(0xFF3C1F72),
    onTertiaryContainer = Color(0xFFEFDBFF),
    background         = BackgroundColor,
    onBackground       = OnBackgroundColor,
    surface            = SurfaceColor,
    onSurface          = OnSurfaceColor,
    surfaceVariant     = CardColor,
    onSurfaceVariant   = OnSurfaceVariant,
    surfaceTint        = PrimaryColor,
    error              = ErrorColor,
    onError            = Color(0xFF690020),
    errorContainer     = Color(0xFF93002A),
    onErrorContainer   = Color(0xFFFFDAD9),
    outline            = OutlineColor,
    outlineVariant     = Color(0xFF2C2C3A),
    inverseSurface     = Color(0xFFE4E1EC),
    inverseOnSurface   = Color(0xFF1C1B1F),
    inversePrimary     = Color(0xFF4F5CC2),
    scrim              = Color(0xFF000000),
)

// ─── Light colour scheme (fallback, app is dark-first) ──────────────────────
private val LightColorScheme = lightColorScheme(
    primary            = Color(0xFF4F5CC2),
    onPrimary          = Color(0xFFFFFFFF),
    background         = Color(0xFFFAFAFF),
    onBackground       = Color(0xFF1A1C2E),
    surface            = Color(0xFFFFFFFF),
    onSurface          = Color(0xFF1A1C2E),
)

// ─── Typography ──────────────────────────────────────────────────────────────
val EchoTypography = Typography(
    // Screen / section titles
    headlineLarge = TextStyle(
        fontWeight = FontWeight.Bold,
        fontSize   = 28.sp,
        lineHeight = 36.sp,
        letterSpacing = (-0.5).sp,
    ),
    headlineMedium = TextStyle(
        fontWeight = FontWeight.Bold,
        fontSize   = 24.sp,
        lineHeight = 32.sp,
        letterSpacing = (-0.25).sp,
    ),
    headlineSmall = TextStyle(
        fontWeight = FontWeight.SemiBold,
        fontSize   = 20.sp,
        lineHeight = 28.sp,
    ),
    // Card / section titles
    titleLarge = TextStyle(
        fontWeight = FontWeight.SemiBold,
        fontSize   = 18.sp,
        lineHeight = 24.sp,
    ),
    titleMedium = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize   = 16.sp,
        lineHeight = 22.sp,
        letterSpacing = 0.1.sp,
    ),
    titleSmall = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize   = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    // Body
    bodyLarge = TextStyle(
        fontWeight = FontWeight.Normal,
        fontSize   = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.15.sp,
    ),
    bodyMedium = TextStyle(
        fontWeight = FontWeight.Normal,
        fontSize   = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    bodySmall = TextStyle(
        fontWeight = FontWeight.Normal,
        fontSize   = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.4.sp,
    ),
    // Labels
    labelLarge = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize   = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    labelMedium = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize   = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp,
    ),
    labelSmall = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize   = 11.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp,
    ),
)

// ─── Shapes ──────────────────────────────────────────────────────────────────
val EchoShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small      = RoundedCornerShape(12.dp),
    medium     = RoundedCornerShape(16.dp),
    large      = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(24.dp),
)

// ─── Theme entry-point ───────────────────────────────────────────────────────
@Composable
fun EchoTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        typography  = EchoTypography,
        shapes      = EchoShapes,
        content     = content,
    )
}
