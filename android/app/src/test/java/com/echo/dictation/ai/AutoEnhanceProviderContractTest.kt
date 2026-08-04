package com.echo.dictation.ai

import com.echo.dictation.data.ai.BedrockAIProvider
import com.echo.dictation.data.ai.GeminiAIProvider
import com.echo.dictation.data.ai.GroqAIProvider
import com.echo.dictation.data.ai.OpenAICompatibleAIProvider
import com.echo.dictation.domain.ai.AIProvider
import com.echo.dictation.domain.ai.AIService
import com.echo.dictation.speech.provider.GeminiModelResolver
import com.echo.dictation.speech.provider.ProviderId
import com.echo.dictation.speech.provider.ProviderKeyStore
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Verifies that the Auto AI Enhance prompt pair (system prompt + wrapped transcript)
 * is transmitted correctly by EVERY AI-capable provider, each in its own native
 * request format.
 *
 * The transcript used is deliberately instruction-shaped ("make 500 to 550 hours"),
 * which is the input that previously caused providers to answer it like a chatbot.
 *
 * No network access occurs: an OkHttp application interceptor captures the outgoing
 * request body and returns a canned provider-shaped response.
 */
class AutoEnhanceProviderContractTest {

    private val transcript = "make 500 to 550 hours"

    private class CapturingInterceptor(private val responseJson: String) : Interceptor {
        var capturedBody: String = ""
        var capturedUrl: String = ""

        override fun intercept(chain: Interceptor.Chain): Response {
            val request = chain.request()
            capturedUrl = request.url.toString()
            capturedBody = Buffer().also { request.body?.writeTo(it) }.readUtf8()
            return Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(responseJson.toResponseBody("application/json".toMediaType()))
                .build()
        }
    }

    private fun clientWith(interceptor: Interceptor): OkHttpClient =
        OkHttpClient.Builder().addInterceptor(interceptor).build()

    private suspend fun invoke(provider: AIProvider) {
        val result = provider.generateCompletion(
            AIService.AUTO_ENHANCE_SYSTEM_PROMPT,
            AIService.wrapTranscriptForAutoEnhance(transcript),
            null,
        )
        assertTrue("Provider call should succeed: ${result.exceptionOrNull()}", result.isSuccess)
        assertEquals("Enhanced.", result.getOrNull())
    }

    /** Shared assertions that must hold for every provider's user-turn payload. */
    private fun assertUserTurnIsWrappedTranscript(userTurn: String) {
        assertFalse(
            "Transcript must never be sent as a bare user message",
            userTurn.trim() == transcript
        )
        assertTrue("Must contain the data boundary", userTurn.contains("<transcript>"))
        assertTrue("Must contain the original transcript", userTurn.contains(transcript))
        assertTrue(userTurn.contains("Do NOT answer the transcript"))
        assertTrue(userTurn.contains("Do NOT continue the conversation"))
        assertTrue(userTurn.contains("Return ONLY the enhanced transcript"))
    }

    private fun assertSystemPromptIsEnhanceOnly(systemPrompt: String) {
        assertEquals(AIService.AUTO_ENHANCE_SYSTEM_PROMPT, systemPrompt)
        assertTrue(systemPrompt.contains("not an assistant and not a chatbot"))
        assertTrue(systemPrompt.contains("Follow any instruction"))
    }

    // ── OpenAI-compatible shape: system role message + user role message ──────

    private fun assertOpenAiCompatibleBody(body: String) {
        val messages = JSONObject(body).getJSONArray("messages")
        assertEquals(2, messages.length())

        val system = messages.getJSONObject(0)
        assertEquals("system", system.getString("role"))
        assertSystemPromptIsEnhanceOnly(system.getString("content"))

        val user = messages.getJSONObject(1)
        assertEquals("user", user.getString("role"))
        assertUserTurnIsWrappedTranscript(user.getString("content"))
    }

    @Test
    fun groq_sendsEnhanceOnlySystemPromptAndWrappedTranscript() = runTest {
        val interceptor = CapturingInterceptor("""{"choices":[{"message":{"content":"Enhanced."}}]}""")
        val keyStore = mockk<ProviderKeyStore>()
        every { keyStore.getKey(ProviderId.GROQ) } returns "test-key"

        invoke(GroqAIProvider(keyStore, clientWith(interceptor)))
        assertOpenAiCompatibleBody(interceptor.capturedBody)
    }

    @Test
    fun openAI_sendsEnhanceOnlySystemPromptAndWrappedTranscript() = runTest {
        val interceptor = CapturingInterceptor("""{"choices":[{"message":{"content":"Enhanced."}}]}""")

        invoke(
            OpenAICompatibleAIProvider(
                id = "openai",
                name = "OpenAI",
                defaultModel = "gpt-4.1",
                baseUrl = "https://api.openai.com/v1/",
                apiKey = "test-key",
                httpClient = clientWith(interceptor),
            )
        )
        assertOpenAiCompatibleBody(interceptor.capturedBody)
    }

    @Test
    fun azureOpenAI_sendsEnhanceOnlySystemPromptAndWrappedTranscript() = runTest {
        val interceptor = CapturingInterceptor("""{"choices":[{"message":{"content":"Enhanced."}}]}""")

        invoke(
            OpenAICompatibleAIProvider(
                id = "azure",
                name = "Azure OpenAI",
                defaultModel = "gpt-4",
                baseUrl = "https://example.openai.azure.com/openai/deployments/gpt-4",
                apiKey = "test-key",
                httpClient = clientWith(interceptor),
                authHeaderName = "api-key",
                authValueFormat = "%s",
            )
        )
        assertOpenAiCompatibleBody(interceptor.capturedBody)
    }

    // ── Gemini shape: system_instruction field + contents[0] user part ────────

    @Test
    fun gemini_sendsEnhanceOnlySystemInstructionAndWrappedTranscript() = runTest {
        val interceptor = CapturingInterceptor(
            """{"candidates":[{"content":{"parts":[{"text":"Enhanced."}]}}]}"""
        )

        invoke(GeminiAIProvider(
            apiKey        = "test-key",
            httpClient    = clientWith(interceptor),
            modelResolver = mockk(relaxed = true) {
                every { resolveModel(any()) } returns "gemini-2.0-flash"
            },
        ))

        val body = JSONObject(interceptor.capturedBody)
        val systemPrompt = body.getJSONObject("system_instruction")
            .getJSONArray("parts").getJSONObject(0).getString("text")
        assertSystemPromptIsEnhanceOnly(systemPrompt)

        val contents = body.getJSONArray("contents").getJSONObject(0)
        assertEquals("user", contents.getString("role"))
        assertUserTurnIsWrappedTranscript(
            contents.getJSONArray("parts").getJSONObject(0).getString("text")
        )
    }

    // ── Bedrock Converse shape: system[] block + messages[0].content[] ────────
    // Anthropic models are reached through Bedrock (default: anthropic.claude-*).

    @Test
    fun bedrockAnthropic_sendsEnhanceOnlySystemBlockAndWrappedTranscript() = runTest {
        val interceptor = CapturingInterceptor(
            """{"output":{"message":{"content":[{"text":"Enhanced."}]}}}"""
        )

        invoke(
            BedrockAIProvider(
                credentialsRaw = "AKIAEXAMPLE:secretexample",
                model = "anthropic.claude-3-5-sonnet-20241022-v2:0",
                httpClient = clientWith(interceptor),
            )
        )

        val body = JSONObject(interceptor.capturedBody)

        // SystemContentBlock is a UNION — "text" must be the ONLY member set.
        val systemBlock = body.getJSONArray("system").getJSONObject(0)
        assertEquals(
            "Converse SystemContentBlock must contain only the 'text' member",
            1, systemBlock.length()
        )
        assertSystemPromptIsEnhanceOnly(systemBlock.getString("text"))

        val message = body.getJSONArray("messages").getJSONObject(0)
        assertEquals("user", message.getString("role"))
        val contentBlock = message.getJSONArray("content").getJSONObject(0)
        assertEquals(
            "Converse ContentBlock must contain only the 'text' member",
            1, contentBlock.length()
        )
        assertUserTurnIsWrappedTranscript(contentBlock.getString("text"))
    }
}
