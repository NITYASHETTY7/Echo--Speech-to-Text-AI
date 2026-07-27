package com.echo.dictation.domain.ai

import kotlinx.coroutines.flow.Flow

sealed class AIError : Exception() {
    data class Timeout(override val message: String = "Request timed out") : AIError()
    data class NetworkFailure(override val message: String = "Network connection unavailable") : AIError()
    data class QuotaExceeded(override val message: String = "API rate limit or quota exceeded") : AIError()
    data class InvalidApiKey(override val message: String = "Invalid or missing API key") : AIError()
    data class MalformedResponse(override val message: String = "Malformed response from AI provider") : AIError()
    data class Cancellation(override val message: String = "Operation was cancelled") : AIError()
    data class Unknown(override val message: String) : AIError()
}

interface AIRepository {
    suspend fun executePrompt(
        systemPrompt: String?,
        userPrompt: String,
        providerId: String? = null,
        model: String? = null
    ): Result<String>

    suspend fun saveVersion(version: TranscriptVersion): Result<Unit>

    fun getVersionsForTranscript(transcriptId: String): Flow<List<TranscriptVersion>>

    suspend fun getLatestVersion(transcriptId: String): TranscriptVersion?
}
