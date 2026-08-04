package com.echo.dictation.ai

import com.echo.dictation.domain.ai.AIError
import com.echo.dictation.domain.ai.AIProvider
import com.echo.dictation.domain.ai.AIProviderFactory
import com.echo.dictation.domain.ai.AIRepository
import com.echo.dictation.domain.ai.GrammarService
import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.ai.VersionType
import com.echo.dictation.speech.provider.ProviderId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GrammarServiceTest {

    class FakeAIProvider : AIProvider {
        override val id: String = "groq"
        override val name: String = "Groq"
        override val defaultModel: String = "llama-3.3-70b-versatile"
        override suspend fun generateCompletion(
            systemPrompt: String?,
            userPrompt: String,
            modelOverride: String?
        ): Result<String> = Result.success("OK")
    }

    class FakeAIProviderFactory : AIProviderFactory {
        override fun getProvider(): AIProvider = FakeAIProvider()
        override fun getProvider(providerId: ProviderId): AIProvider = FakeAIProvider()
        override fun isCurrentProviderConfiguredForAI(): Boolean = true
        override fun currentProviderDisplayName(): String = "Groq"
    }

    class FakeAIRepository(
        private val shouldFail: Boolean = false,
        private val returnedText: String = "This is a test."
    ) : AIRepository {
        var executePromptCount = 0
        val savedVersions = mutableListOf<TranscriptVersion>()

        override suspend fun executePrompt(
            systemPrompt: String?,
            userPrompt: String,
            providerId: String?,
            model: String?
        ): Result<String> {
            executePromptCount++
            return if (shouldFail) {
                Result.failure(AIError.Timeout())
            } else {
                Result.success(returnedText)
            }
        }

        override suspend fun saveVersion(version: TranscriptVersion): Result<Unit> {
            savedVersions.add(version)
            return Result.success(Unit)
        }

        override fun getVersionsForTranscript(transcriptId: String): Flow<List<TranscriptVersion>> =
            flowOf(savedVersions)

        override suspend fun getLatestVersion(transcriptId: String): TranscriptVersion? =
            savedVersions.lastOrNull()
    }

    private val providerFactory = FakeAIProviderFactory()

    @Test
    fun testGrammarCorrectionDisabledReturnsNull() = runTest {
        val fakeRepo = FakeAIRepository()
        val grammarService = GrammarService(fakeRepo, providerFactory)

        val result = grammarService.correctGrammar("tx_1", "raw text", enabled = false)
        assertTrue(result.isSuccess)
        assertNull(result.getOrNull())
        assertEquals(0, fakeRepo.executePromptCount)
    }

    @Test
    fun testGrammarCorrectionEnabledSuccess() = runTest {
        val fakeRepo = FakeAIRepository(shouldFail = false, returnedText = "This is a test.")
        val grammarService = GrammarService(fakeRepo, providerFactory)

        val result = grammarService.correctGrammar("tx_1", "this is test", enabled = true)
        assertTrue(result.isSuccess)
        val version = result.getOrNull()
        assertNotNull(version)
        assertEquals("tx_1", version?.transcriptId)
        assertEquals("This is a test.", version?.content)
        assertEquals(VersionType.GrammarCorrected, version?.versionType)
        assertEquals(1, fakeRepo.savedVersions.size)
    }

    @Test
    fun testGrammarCorrectionFailureKeepsOriginalSafely() = runTest {
        val fakeRepo = FakeAIRepository(shouldFail = true)
        val grammarService = GrammarService(fakeRepo, providerFactory)

        val result = grammarService.correctGrammar("tx_1", "raw text", enabled = true)
        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is AIError.Timeout)
        assertEquals(0, fakeRepo.savedVersions.size)
    }
}
