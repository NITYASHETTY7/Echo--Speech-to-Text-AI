package com.echo.dictation.domain.model

data class Transcription(
    val id: String,
    val text: String,
    val timestamp: Long,
    val model: String,
    val audioPath: String? = null,
    val userId: String,
    val synced: Boolean = false,
    val isFavorite: Boolean = false,
    val isPinned: Boolean = false,
    /** One of: "PENDING", "SYNCED", "LOCAL_ONLY" */
    val syncStatus: String = "PENDING",
    /**
     * The raw Speech-to-Text output, stored immediately after transcription and
     * never modified by grammar correction, AI enhancement, translation, or sync.
     *
     * This is the single source of truth for the Original tab — it always
     * reflects what the user actually spoke, regardless of which language.
     *
     * Null for rows created before this field was introduced (backward compat).
     * The UI falls back to [text] in that case.
     */
    val rawTranscript: String? = null,
)

data class AppSettings(
    val language: String = "en",
    val model: String = "whisper-large-v3-turbo",
    val retentionDays: Int = 30,
    val grammarEnabled: Boolean = true,
    val theme: String = "system",
    val autoStart: Boolean = false,
    /** Map of provider ID (lowercase name) → configured flag. */
    val providerConfigured: Map<String, Boolean> = emptyMap(),
)
