package com.echo.dictation.ai

import com.echo.dictation.domain.ai.AIError
import com.echo.dictation.domain.ai.AIRepository
import com.echo.dictation.domain.ai.PromptTemplateRepository
import com.echo.dictation.domain.ai.RewriteService
import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.ai.VersionType
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RewriteServiceTest {

    class FakeAIRepository(private val responseMap: Map<String, String> = emptyMap()) : AIRepository {
        val savedVersions = mutableListOf<TranscriptVersion>()

        override suspend fun executePrompt(
            systemPrompt: String?,
            userPrompt: String,
            providerId: String?,
            model: String?
        ): Result<String> {
            val response = responseMap[userPrompt] ?: "Default transformed output"
            return Result.success(response)
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

    private val promptRepository = PromptTemplateRepository()

    @Test
    fun testRewriteWithPresetSuccess() = runTest {
        val fakeRepo = FakeAIRepository(mapOf("Meeting content" to "1. Item 1\n2. Item 2"))
        val rewriteService = RewriteService(fakeRepo, promptRepository)

        val result = rewriteService.rewriteWithPreset("meeting_notes", "Meeting content", "meeting_notes")
        assertTrue(result.isSuccess)
        val version = result.getOrNull()
        assertNotNull(version)
        assertEquals("meeting_notes", version?.transcriptId)
        assertEquals(VersionType.MeetingNotes, version?.versionType)
        assertEquals("1. Item 1\n2. Item 2", version?.content)
    }

    @Test
    fun testRewriteWithCustomPromptSuccess() = runTest {
        val fakeRepo = FakeAIRepository(mapOf("Raw text" to "Texto sin formato"))
        val rewriteService = RewriteService(fakeRepo, promptRepository)

        val result = rewriteService.rewriteWithCustomPrompt("tx_2", "Raw text", "Translate to Spanish")
        assertTrue(result.isSuccess)
        val version = result.getOrNull()
        assertNotNull(version)
        assertEquals(VersionType.Custom, version?.versionType)
        assertEquals("Texto sin formato", version?.content)
    }
}
