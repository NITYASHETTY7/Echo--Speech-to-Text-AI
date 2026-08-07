package com.echo.dictation.presentation.ui.onboarding

/**
 * Data class representing a single onboarding page.
 */
data class OnboardingPage(
    val title: String,
    val subtitle: String,
    val illustrationType: IllustrationType,
)

enum class IllustrationType {
    VOICE_ANYWHERE,
    POWERED_BY_AI,
    READY_WHEN_YOU_ARE,
}

/**
 * The three onboarding pages for Echo.
 */
val onboardingPages = listOf(
    OnboardingPage(
        title = "Your Voice. Anywhere.",
        subtitle = "Capture speech instantly and insert text into any app with a single tap.",
        illustrationType = IllustrationType.VOICE_ANYWHERE,
    ),
    OnboardingPage(
        title = "Powered by AI",
        subtitle = "Automatically enhance grammar, rewrite content, translate languages, summarize meetings, and create professional notes.",
        illustrationType = IllustrationType.POWERED_BY_AI,
    ),
    OnboardingPage(
        title = "Ready When You Are",
        subtitle = "Echo stays one tap away while you work. Don\u2019t need it? Hold for 3 seconds to snooze\u2009\u2014\u2009customizable duration, completely out of your way.",
        illustrationType = IllustrationType.READY_WHEN_YOU_ARE,
    ),
)
