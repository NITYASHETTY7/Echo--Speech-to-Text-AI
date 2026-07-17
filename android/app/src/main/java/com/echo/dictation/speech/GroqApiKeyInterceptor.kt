package com.echo.dictation.speech

import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * OkHttp interceptor that attaches the Groq API key on every outbound request.
 *
 * The key is read lazily from [GroqApiKeyStore] on each request so a key saved
 * after the OkHttp client was built is picked up without restarting the app.
 * If no key has been configured yet, the request is forwarded without an
 * Authorization header. Groq will respond with 401, which surfaces as an
 * exception in [GroqTranscriptionService] and is shown to the user as an error.
 */
@Singleton
class GroqApiKeyInterceptor @Inject constructor(
    private val keyStore: GroqApiKeyStore,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val key = keyStore.apiKey
        val request = if (key.isNullOrBlank()) {
            chain.request()
        } else {
            chain.request().newBuilder()
                .header("Authorization", "Bearer $key")
                .build()
        }
        return chain.proceed(request)
    }
}
