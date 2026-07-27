package com.echo.dictation.ai

/**
 * An immutable snapshot of one version of a transcript.
 *
 * The original raw STT output is always preserved as [VersionKind.Original].
 * Subsequent AI enhancements are stored as additional [TranscriptVersion]s
 * in [TranscriptVersionStore] — the original is never overwritten.
 */
data class TranscriptVersion(
    /** Unique identifier for this version (timestamp-based for simple uniqueness). */
    val id: String,
    /** The text content of this version. */
    val text: String,
    /** What produced this version. */
    val kind: VersionKind,
    /** Human-readable label shown in the version selector. */
    val label: String,
    /** Unix millis when this version was created. */
    val createdAt: Long = System.currentTimeMillis(),
)

/**
 * Discriminates between the different ways a transcript version can be produced.
 */
sealed interface VersionKind {
    /** Raw output from the Speech-to-Text provider. */
    data object Original : VersionKind

    /** Grammar / punctuation correction applied by the LLM. */
    data object GrammarCorrected : VersionKind

    /** A named rewrite preset was applied (e.g. "Meeting Notes"). */
    data class Preset(val templateId: String, val templateTitle: String) : VersionKind

    /** The user typed a free-form instruction. */
    data class Custom(val userPrompt: String) : VersionKind
}
