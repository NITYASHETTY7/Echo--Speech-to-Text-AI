package com.echo.dictation.data.ai

import android.util.Log
import com.echo.dictation.data.local.db.TranscriptVersionDao
import com.echo.dictation.data.local.db.toDomain
import com.echo.dictation.data.local.db.toEntity
import com.echo.dictation.domain.ai.AIError
import com.echo.dictation.domain.ai.AIProvider
import com.echo.dictation.domain.ai.AIRepository
import com.echo.dictation.domain.ai.TranscriptVersion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withTimeout
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AIRepositoryImpl @Inject constructor(
    private val defaultProvider: AIProvider,
    private val versionDao: TranscriptVersionDao,
) : AIRepository {

    override suspend fun executePrompt(
        systemPrompt: String?,
        userPrompt: String,
        providerId: String?,
        model: String?
    ): Result<String> {
        return try {
            withTimeout(TIMEOUT_MS) {
                // Currently delegates to defaultProvider (Groq). Plug in dynamic providers map in future.
                val provider = defaultProvider
                val result = provider.generateCompletion(systemPrompt, userPrompt, model)
                result.mapCatching { text ->
                    if (text.isBlank()) throw AIError.MalformedResponse("Empty response returned from AI provider")
                    text
                }
            }
        } catch (e: TimeoutCancellationException) {
            Log.e(TAG, "AI execution timed out after $TIMEOUT_MS ms", e)
            Result.failure(AIError.Timeout())
        } catch (e: UnknownHostException) {
            Log.e(TAG, "Network unavailable during AI call", e)
            Result.failure(AIError.NetworkFailure())
        } catch (e: SocketTimeoutException) {
            Log.e(TAG, "Socket timeout during AI call", e)
            Result.failure(AIError.Timeout())
        } catch (e: CancellationException) {
            Log.d(TAG, "AI call cancelled")
            Result.failure(AIError.Cancellation())
        } catch (e: IllegalStateException) {
            Log.e(TAG, "IllegalStateException during AI call: ${e.message}", e)
            if (e.message?.contains("API key", ignoreCase = true) == true) {
                Result.failure(AIError.InvalidApiKey(e.message ?: "Invalid API key"))
            } else {
                Result.failure(AIError.Unknown(e.message ?: "Illegal state error"))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error during AI call", e)
            val msg = e.message ?: ""
            val error = when {
                msg.contains("429") || msg.contains("quota", ignoreCase = true) -> AIError.QuotaExceeded(msg)
                msg.contains("401") || msg.contains("key", ignoreCase = true)   -> AIError.InvalidApiKey(msg)
                else -> AIError.Unknown(msg)
            }
            Result.failure(error)
        }
    }

    override suspend fun saveVersion(version: TranscriptVersion): Result<Unit> = runCatching {
        versionDao.insertVersion(version.toEntity())
        Log.d(TAG, "Saved transcript version ${version.id} (${version.versionType}) for ${version.transcriptId}")
        Unit
    }

    override fun getVersionsForTranscript(transcriptId: String): Flow<List<TranscriptVersion>> =
        versionDao.observeVersions(transcriptId).map { entities ->
            entities.map { it.toDomain() }
        }

    override suspend fun getLatestVersion(transcriptId: String): TranscriptVersion? =
        versionDao.getLatestVersion(transcriptId)?.toDomain()

    companion object {
        private const val TAG = "AIRepositoryImpl"
        private const val TIMEOUT_MS = 30_000L // 30 seconds timeout
    }
}
