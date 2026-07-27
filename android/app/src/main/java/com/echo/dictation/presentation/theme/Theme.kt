package com.echo.dictation.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Typography
import androidx.compose.material3.Shapes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.googlefonts.Font
import androidx.compose.ui.text.googlefonts.GoogleFont
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import com.echo.dictation.R

// ─── Cormorant Garamond — date headers only ──────────────────────────────────

private val googleFontProvider = GoogleFont.Provider(
    providerAuthority = "com.google.android.gms.fonts",
    providerPackage   = "com.google.android.gms",
    certificates      = R.array.com_google_android_gms_fonts_certs,
)

/**
 * Cormorant Garamond SemiBold — used exclusively for date group headers
 * ("Today", "Yesterday", "Jul 27, 2026") in the History screen.
 */
val CormorantGaramondSemiBold: FontFamily = FontFamily(
    Font(
        googleFont      = GoogleFont("Cormorant Garamond"),
        fontProvider    = googleFontProvider,
        weight          = FontWeight.SemiBold,
    )
)

// ─── Brand gradient colours (fixed — theme-invariant decorative use) ─────────
// Used inside gradient Brush calls. For interactive UI elements use Primary/OnPrimary.
val PrimaryColor   = Color(0xFF9AA8FF)   // gradient start
val PrimaryVariant = Color(0xFF7C8CFF)   // gradient end

// ─── Static dark-only tokens (used only inside DarkColorScheme) ─────────────
private val DarkBackground    = Color(0xFF121212)
private val DarkSurface       = Color(0xFF1C1C22)
private val DarkCard          = Color(0xFF232329)
private val DarkOnBackground  = Color(0xFFE8EAF6)
private val DarkOnSurface     = Color(0xFFE8EAF6)
private val DarkOnSurfaceVar  = Color(0xFF9E9EAE)
private val DarkOutline       = Color(0xFF3A3A4A)
private val DarkOutlineVar    = Color(0xFF2C2C3A)

// ─── Dark colour scheme ──────────────────────────────────────────────────────
private val DarkColorScheme = darkColorScheme(
    primary              = PrimaryColor,
    onPrimary            = Color(0xFF0A0F2E),
    primaryContainer     = Color(0xFF1E245C),
    onPrimaryContainer   = Color(0xFFDDE1FF),
    secondary            = Color(0xFFB0B8FF),
    onSecondary          = Color(0xFF0D1550),
    secondaryContainer   = Color(0xFF232C6A),
    onSecondaryContainer = Color(0xFFDDE1FF),
    tertiary             = Color(0xFFCFB7FF),
    onTertiary           = Color(0xFF25005A),
    tertiaryContainer    = Color(0xFF3C1F72),
    onTertiaryContainer  = Color(0xFFEFDBFF),
    background           = DarkBackground,
    onBackground         = DarkOnBackground,
    surface              = DarkSurface,
    onSurface            = DarkOnSurface,
    surfaceVariant       = DarkCard,
    onSurfaceVariant     = DarkOnSurfaceVar,
    surfaceTint          = PrimaryColor,
    error                = Color(0xFFCF6679),
    onError              = Color(0xFF690020),
    errorContainer       = Color(0xFF93002A),
    onErrorContainer     = Color(0xFFFFDAD9),
    outline              = DarkOutline,
    outlineVariant       = DarkOutlineVar,
    inverseSurface       = Color(0xFFE4E1EC),
    inverseOnSurface     = Color(0xFF1C1B1F),
    inversePrimary       = Color(0xFF4F5CC2),
    scrim                = Color(0xFF000000),
)

// ─── Light colour scheme (fully specified) ───────────────────────────────────
private val LightColorScheme = lightColorScheme(
    primary              = Color(0xFF3A48B0),
    onPrimary            = Color(0xFFFFFFFF),
    primaryContainer     = Color(0xFFDDE1FF),
    onPrimaryContainer   = Color(0xFF00105C),
    secondary            = Color(0xFF575E9E),
    onSecondary          = Color(0xFFFFFFFF),
    secondaryContainer   = Color(0xFFDEE0FF),
    onSecondaryContainer = Color(0xFF121657),
    tertiary             = Color(0xFF7148AF),
    onTertiary           = Color(0xFFFFFFFF),
    tertiaryContainer    = Color(0xFFEFDBFF),
    onTertiaryContainer  = Color(0xFF260057),
    background           = Color(0xFFFAFAFF),
    onBackground         = Color(0xFF1A1C2E),
    surface              = Color(0xFFFFFFFF),
    onSurface            = Color(0xFF1A1C2E),
    surfaceVariant       = Color(0xFFE4E4F4),   // light card background
    onSurfaceVariant     = Color(0xFF46465C),
    surfaceTint          = Color(0xFF3A48B0),
    error                = Color(0xFFBA1A1A),
    onError              = Color(0xFFFFFFFF),
    errorContainer       = Color(0xFFFFDAD6),
    onErrorContainer     = Color(0xFF410002),
    outline              = Color(0xFF767688),
    outlineVariant       = Color(0xFFC6C5D8),
    inverseSurface       = Color(0xFF302F45),
    inverseOnSurface     = Color(0xFFF2EFFF),
    inversePrimary       = Color(0xFFBAC3FF),
    scrim                = Color(0xFF000000),
)

// ─── Theme-aware helpers used across the app ─────────────────────────────────

/**
 * Primary interactive colour that adapts to the active theme.
 * Use this for buttons, badges, icon tints, and interactive highlights.
 * Dark:  Color(0xFF9AA8FF)  — soft lavender-blue on dark background
 * Light: Color(0xFF3A48B0)  — deep indigo with sufficient contrast on white
 */
val Primary: Color
    @Composable @ReadOnlyComposable
    get() = MaterialTheme.colorScheme.primary

/**
 * Text / icon colour on top of a Primary-coloured container.
 * Maps to MaterialTheme.colorScheme.onPrimary so it is always readable.
 */
val OnPrimary: Color
    @Composable @ReadOnlyComposable
    get() = MaterialTheme.colorScheme.onPrimary

/** Card / list-item background. Maps to surfaceVariant in both schemes. */
val CardColor: Color
    @Composable @ReadOnlyComposable
    get() = MaterialTheme.colorScheme.surfaceVariant

/** Subtle text / icon colour. Maps to onSurfaceVariant. */
val OnSurfaceVariant: Color
    @Composable @ReadOnlyComposable
    get() = MaterialTheme.colorScheme.onSurfaceVariant

/** Border / divider colour. Maps to outline. */
val OutlineColor: Color
    @Composable @ReadOnlyComposable
    get() = MaterialTheme.colorScheme.outline

// ─── Typography ──────────────────────────────────────────────────────────────
val EchoTypography = Typography(
    headlineLarge = TextStyle(
        fontWeight    = FontWeight.Bold,
        fontSize      = 28.sp,
        lineHeight    = 36.sp,
        letterSpacing = (-0.5).sp,
    ),
    headlineMedium = TextStyle(
        fontWeight    = FontWeight.Bold,
        fontSize      = 24.sp,
        lineHeight    = 32.sp,
        letterSpacing = (-0.25).sp,
    ),
    headlineSmall = TextStyle(
        fontWeight = FontWeight.SemiBold,
        fontSize   = 20.sp,
        lineHeight = 28.sp,
    ),
    titleLarge = TextStyle(
        fontWeight = FontWeight.SemiBold,
        fontSize   = 18.sp,
        lineHeight = 24.sp,
    ),
    titleMedium = TextStyle(
        fontWeight    = FontWeight.Medium,
        fontSize      = 16.sp,
        lineHeight    = 22.sp,
        letterSpacing = 0.1.sp,
    ),
    titleSmall = TextStyle(
        fontWeight    = FontWeight.Medium,
        fontSize      = 14.sp,
        lineHeight    = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    bodyLarge = TextStyle(
        fontWeight    = FontWeight.Normal,
        fontSize      = 16.sp,
        lineHeight    = 24.sp,
        letterSpacing = 0.15.sp,
    ),
    bodyMedium = TextStyle(
        fontWeight    = FontWeight.Normal,
        fontSize      = 14.sp,
        lineHeight    = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    bodySmall = TextStyle(
        fontWeight    = FontWeight.Normal,
        fontSize      = 12.sp,
        lineHeight    = 16.sp,
        letterSpacing = 0.4.sp,
    ),
    labelLarge = TextStyle(
        fontWeight    = FontWeight.Medium,
        fontSize      = 14.sp,
        lineHeight    = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    labelMedium = TextStyle(
        fontWeight    = FontWeight.Medium,
        fontSize      = 12.sp,
        lineHeight    = 16.sp,
        letterSpacing = 0.5.sp,
    ),
    labelSmall = TextStyle(
        fontWeight    = FontWeight.Medium,
        fontSize      = 11.sp,
        lineHeight    = 16.sp,
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
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        typography  = EchoTypography,
        shapes      = EchoShapes,
        content     = content,
    )
}
