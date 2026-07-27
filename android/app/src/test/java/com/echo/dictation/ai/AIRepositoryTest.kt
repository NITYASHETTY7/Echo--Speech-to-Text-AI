package com.echo.dictation.ai

import com.echo.dictation.data.ai.AIRepositoryImpl
import com.echo.dictation.data.local.db.TranscriptVersionDao
import com.echo.dictation.data.local.db.TranscriptVersionEntity
import com.echo.dictation.domain.ai.AIError
import com.echo.dictation.domain.ai.AIProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.SocketTimeoutException

class AIRepositoryTest {

    class FakeAIProvider(private val exceptionToThrow: Exception? = null, private val successResponse: String = "Response") : AIProvider {
        override val id: String = "groq"
        override val name: String = "Groq"
        override val defaultModel: String = "llama-3.3-70b-versatile"

        override suspend fun generateCompletion(
            systemPrompt: String?,
            userPrompt: String,
            modelOverride: String?
        ): Result<String> {
            if (exceptionToThrow != null) throw exceptionToThrow
            return Result.success(successResponse)
        }
    }

    class FakeTranscriptVersionDao : TranscriptVersionDao {
        val storedEntities = mutableListOf<TranscriptVersionEntity>()

        override fun observeVersions(transcriptId: String): Flow<List<TranscriptVersionEntity>> =
            flowOf(storedEntities.filter { it.transcriptId == transcriptId })

        override suspend fun getLatestVersion(transcriptId: String): TranscriptVersionEntity? =
            storedEntities.filter { it.transcriptId == transcriptId }.lastOrNull()

        override suspend fun insertVersion(version: TranscriptVersionEntity) {
            storedEntities.add(version)
        }

        override suspend fun getPendingSyncVersions(): List<TranscriptVersionEntity> =
            storedEntities.filter { it.syncStatus == "PENDING" }

        override suspend fun deleteVersionsForTranscript(transcriptId: String) {
            storedEntities.removeAll { it.transcriptId == transcriptId }
        }
    }

    @Test
    fun testExecutePromptSuccess() = runTest {
        val provider = FakeAIProvider(successResponse = "Response")
        val dao = FakeTranscriptVersionDao()
        val repository = AIRepositoryImpl(provider, dao)

        val result = repository.executePrompt(null, "Hello")
        assertTrue(result.isSuccess)
        assertEquals("Response", result.getOrNull())
    }

    @Test
    fun testExecutePromptTimeoutErrorMapping() = runTest {
        val provider = FakeAIProvider(exceptionToThrow = SocketTimeoutException("Connection timed out"))
        val dao = FakeTranscriptVersionDao()
        val repository = AIRepositoryImpl(provider, dao)

        val result = repository.executePrompt(null, "Test")
        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is AIError.Timeout)
    }

    @Test
    fun testExecutePromptQuotaErrorMapping() = runTest {
        val provider = FakeAIProvider(exceptionToThrow = RuntimeException("HTTP 429 quota exceeded"))
        val dao = FakeTranscriptVersionDao()
        val repository = AIRepositoryImpl(provider, dao)

        val result = repository.executePrompt(null, "Test")
        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is AIError.QuotaExceeded)
    }
}
