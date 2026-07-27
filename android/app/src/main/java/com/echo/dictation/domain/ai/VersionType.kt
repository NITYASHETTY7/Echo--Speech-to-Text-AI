package com.echo.dictation.domain.ai

enum class VersionType {
    Original,
    GrammarCorrected,
    AutoEnhanced,
    Professional,
    Summary,
    MeetingNotes,
    Email,
    BulletPoints,
    Translation,
    Custom;

    val displayName: String get() = when (this) {
        Original         -> "Original"
        GrammarCorrected -> "Grammar Corrected"
        AutoEnhanced     -> "AI Enhanced"
        Professional     -> "Professional"
        Summary          -> "Summary"
        MeetingNotes     -> "Meeting Notes"
        Email            -> "Email"
        BulletPoints     -> "Bullet Points"
        Translation      -> "Translation"
        Custom           -> "Custom Rewrite"
    }
}
