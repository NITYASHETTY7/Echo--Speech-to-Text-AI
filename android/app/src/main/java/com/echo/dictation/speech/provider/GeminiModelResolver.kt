package com.echo.dictation.speech.provider

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Resilient Gemini model resolver.
 *
 * Mirrors the iOS EchoCore GeminiModelResolver logic:
 *
 * 1. **Fetch** — GET /v1beta/models?key=... returns every model the API key can see.
 * 2. **Filter** — keep only models whose `supportedGenerationMethods` includes
 *    `generateContent` (excludes embedding, TTS, vision-only, image models).
 * 3. **Rank** — prefer newest stable Flash, then newest stable Pro.
 *    Penalise `preview`, `experimental`, `exp` suffix patterns.
 * 4. **Cache** — persist the last working model name in SharedPreferences keyed
 *    to the API key's fingerprint so different keys don't share a cache entry.
 * 5. **Fallback** — callers call [markDeprecated] when they see HTTP 404 / 410 or
 *    a "no longer available" error body.  The resolver removes that model from the
 *    candidate list for this session and the caller retries with [resolveModel].
 *
 * Thread-safety: every mutable field is guarded by `synchronized(this)`.
 * Network calls are intentionally synchronous (OkHttp blocking) so they can be
 * called from coroutine IO contexts without extra wrappers.
 */
@Singleton
class GeminiModelResolver @Inject constructor(
    @ApplicationContext private val context: Context,
    private val httpClient: OkHttpClient,
) {

    // ── Persistence ───────────────────────────────────────────────────────────

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
    }

    // ── In-memory session state ───────────────────────────────────────────────

    /**
     * Models that have been deprecated (returned 404/410) during this session.
     * Keyed by model name — persists for the lifetime of the process.
     */
    private val deprecatedThisSession = mutableSetOf<String>()

    /**
     * Cached ranked model list per API-key fingerprint, so we don't re-fetch on
     * every call within the same session.
     */
    private val sessionCache = mutableMapOf<String, List<String>>()

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Returns the best available Gemini model for [apiKey].
     *
     * Resolution order:
     * 1. Cached working model (SharedPreferences, keyed to API-key fingerprint)
     *    — if it hasn't been deprecated this session.
     * 2. Freshly fetched + ranked list from the Gemini Models endpoint.
     * 3. Built-in fallbacks in [BUILT_IN_FALLBACKS] — used when the network is
     *    unavailable or the API returns no usable models.
     *
     * @throws NoCompatibleGeminiModelException when every candidate is exhausted
     *   and the network is unreachable.
     */
    @Throws(NoCompatibleGeminiModelException::class)
    fun resolveModel(apiKey: String): String {
        val fingerprint = apiKeyFingerprint(apiKey)

        synchronized(this) {
            // 1. Try the cached winner first
            val cached = prefs.getString(cachedModelKey(fingerprint), null)
            if (!cached.isNullOrBlank() && cached !in deprecatedThisSession) {
                Log.d(TAG, "resolveModel — using cached model: $cached")
                return cached
            }

            // 2. Try the in-session ranked list (avoids re-fetching within a session)
            val sessionList = sessionCache[fingerprint]
            if (!sessionList.isNullOrEmpty()) {
                val candidate = sessionList.firstOrNull { it !in deprecatedThisSession }
                if (candidate != null) {
                    Log.d(TAG, "resolveModel — using session-cached model: $candidate")
                    cacheModel(fingerprint, candidate)
                    return candidate
                }
            }
        }

        // 3. Fetch from API (outside the lock — network call)
        val fetched = fetchRankedModels(apiKey)

        synchronized(this) {
            if (fetched.isNotEmpty()) {
                sessionCache[fingerprint] = fetched
                val candidate = fetched.firstOrNull { it !in deprecatedThisSession }
                if (candidate != null) {
                    Log.d(TAG, "resolveModel — selected from fetched list: $candidate")
                    cacheModel(fingerprint, candidate)
                    return candidate
                }
            }

            // 4. Fall back to built-ins (network unavailable, empty list, all deprecated)
            val fallback = BUILT_IN_FALLBACKS.firstOrNull { it !in deprecatedThisSession }
            if (fallback != null) {
                Log.w(TAG, "resolveModel — using built-in fallback: $fallback")
                return fallback
            }
        }

        Log.e(TAG, "resolveModel — no compatible model found for fingerprint=$fingerprint")
        throw NoCompatibleGeminiModelException(
            "No compatible Gemini models are currently available for this API key."
        )
    }

    /**
     * Returns the ranked model list cached during this session for [apiKey], or
     * an empty list if [resolveModel] has not been called yet for this key.
     *
     * Used by [SettingsViewModel] to populate the model dropdown after
     * [resolveModel] has already fetched the list.
     */
    fun getCachedRankedModels(apiKey: String): List<String> {
        val fingerprint = apiKeyFingerprint(apiKey)
        return synchronized(this) { sessionCache[fingerprint] ?: emptyList() }
    }

    /**
     * Marks [model] as deprecated for this session (e.g. HTTP 404 or 410).
     *
     * Also removes it from the SharedPreferences cache so the resolver doesn't
     * serve it again after an app restart.
     */
    fun markDeprecated(model: String, apiKey: String) {
        val fingerprint = apiKeyFingerprint(apiKey)
        synchronized(this) {
            deprecatedThisSession.add(model)
            // If this was the cached winner, evict it
            val cached = prefs.getString(cachedModelKey(fingerprint), null)
            if (cached == model) {
                prefs.edit().remove(cachedModelKey(fingerprint)).apply()
                Log.d(TAG, "markDeprecated — evicted $model from cache (fingerprint=$fingerprint)")
            }
            // Also remove from the session ranked list
            sessionCache[fingerprint] = sessionCache[fingerprint]?.filterNot { it == model } ?: emptyList()
        }
        Log.d(TAG, "markDeprecated — $model marked as deprecated this session")
    }

    /**
     * Clears the cached model for a given [apiKey].
     * Call this when the user changes their Gemini API key so the new key gets
     * a fresh model discovery pass.
     */
    fun invalidateCacheForKey(apiKey: String) {
        val fingerprint = apiKeyFingerprint(apiKey)
        synchronized(this) {
            prefs.edit().remove(cachedModelKey(fingerprint)).apply()
            sessionCache.remove(fingerprint)
        }
        Log.d(TAG, "invalidateCacheForKey — cache cleared for fingerprint=$fingerprint")
    }

    // ── Fetch + rank ──────────────────────────────────────────────────────────

    /**
     * Calls the Gemini Models endpoint and returns a ranked list of model names
     * that support `generateContent`.
     *
     * Returns an empty list on any network or parse failure (caller falls back to
     * built-ins; nothing crashes).
     */
    private fun fetchRankedModels(apiKey: String): List<String> {
        Log.d(TAG, "Fetching Gemini model list from API…")
        val url = "${BASE_URL}models?key=$apiKey"
        val request = Request.Builder().url(url).get().build()

        val body: String = try {
            val response = httpClient.newCall(request).execute()
            val rawBody = response.body?.string() ?: ""
            if (!response.isSuccessful) {
                Log.e(TAG, "Models endpoint returned HTTP ${response.code}: $rawBody")
                return emptyList()
            }
            rawBody
        } catch (e: IOException) {
            Log.w(TAG, "Network unavailable while fetching Gemini models: ${e.message}")
            return emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error fetching Gemini models: ${e.message}")
            return emptyList()
        }

        return parseAndRankModels(body)
    }

    /**
     * Parses the `/v1beta/models` JSON response and returns a ranked list of
     * model names suitable for `generateContent`.
     *
     * Example response shape:
     * ```json
     * {
     *   "models": [
     *     {
     *       "name": "models/gemini-2.0-flash",
     *       "supportedGenerationMethods": ["generateContent", "countTokens"],
     *       "displayName": "Gemini 2.0 Flash",
     *       ...
     *     }
     *   ]
     * }
     * ```
     */
    internal fun parseAndRankModels(json: String): List<String> {
        return try {
            val root = JSONObject(json)
            val modelsArray = root.optJSONArray("models") ?: return emptyList()

            val compatible = mutableListOf<String>()
            for (i in 0 until modelsArray.length()) {
                val obj = modelsArray.optJSONObject(i) ?: continue
                val name = obj.optString("name", "").removePrefix("models/")
                if (name.isBlank()) continue

                // Filter: must support generateContent
                val methods = obj.optJSONArray("supportedGenerationMethods")
                val supportsGenerate = methods != null && (0 until methods.length()).any {
                    methods.optString(it) == "generateContent"
                }
                if (!supportsGenerate) continue

                // Filter out obviously unsupported model families
                if (EXCLUDED_FAMILIES.any { name.contains(it, ignoreCase = true) }) continue

                compatible.add(name)
            }

            Log.d(TAG, "Available generateContent-capable models (${compatible.size}): $compatible")

            val ranked = compatible.sortedWith(compareByDescending { rankModel(it) })
            Log.d(TAG, "Ranked models: $ranked")
            ranked
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse models response: ${e.message}")
            emptyList()
        }
    }

    /**
     * Assigns a numeric rank to a model name so the list can be sorted best-first.
     *
     * Ranking strategy (higher = better):
     *
     * Base score by family:
     *   flash   → 200   (preferred: fast, multimodal, cost-effective)
     *   pro     → 100   (powerful, but higher latency/cost)
     *   nano    →  50   (lightweight, but limited)
     *   other   →   0
     *
     * Version bonus:
     *   Extract the leading major version number (e.g. "2.5" → 25, "2.0" → 20,
     *   "1.5" → 15). Newer versions score higher within the same family.
     *
     * Preview/experimental penalty:
     *   Subtract 50 when the name contains "preview", "experimental", or "-exp"
     *   so stable models always rank above unstable ones at the same version.
     */
    internal fun rankModel(name: String): Int {
        val lower = name.lowercase()

        val familyScore = when {
            lower.contains("flash") -> 200
            lower.contains("pro")   -> 100
            lower.contains("nano")  ->  50
            else                    ->   0
        }

        // Extract version: match digits-and-dots immediately after "gemini-"
        val versionScore = VERSION_REGEX.find(lower)?.value
            ?.replace(".", "")
            ?.toIntOrNull()
            ?: 0

        val previewPenalty = if (
            lower.contains("preview") ||
            lower.contains("experimental") ||
            lower.contains("-exp")
        ) -50 else 0

        return familyScore + versionScore + previewPenalty
    }

    // ── Cache helpers ─────────────────────────────────────────────────────────

    private fun cacheModel(fingerprint: String, model: String) {
        prefs.edit().putString(cachedModelKey(fingerprint), model).apply()
        Log.d(TAG, "Cached model '$model' for fingerprint=$fingerprint")
    }

    private fun cachedModelKey(fingerprint: String) = "gemini_model_$fingerprint"

    /**
     * Returns a short, non-sensitive fingerprint of the API key.
     * Uses the last 8 characters (not the key itself — never logged).
     */
    private fun apiKeyFingerprint(apiKey: String): String =
        if (apiKey.length >= 8) apiKey.takeLast(8) else apiKey.padStart(8, '0')

    // ── Constants ─────────────────────────────────────────────────────────────

    companion object {
        private const val TAG       = "GeminiModelResolver"
        private const val PREFS_FILE = "gemini_model_cache"
        private const val BASE_URL   = "https://generativelanguage.googleapis.com/v1beta/"

        /**
         * Model name fragments that indicate a model family that does NOT
         * support text/audio generation (embedding, TTS, image, vision-only).
         */
        private val EXCLUDED_FAMILIES = setOf(
            "embedding",
            "text-embedding",
            "aqa",
            "imagen",
            "tts",
        )

        /**
         * Regex to extract the version number from a Gemini model name.
         * Matches patterns like "2.0", "2.5", "1.5" in "gemini-2.0-flash".
         */
        private val VERSION_REGEX = Regex("""(?<=gemini-)(\d+\.\d+)""")

        /**
         * Hard-coded fallbacks used only when:
         *  - The network is unavailable on first launch, OR
         *  - The API returns an empty model list.
         *
         * These are NOT used as a primary source. The resolver always prefers
         * freshly-fetched models for the configured API key.
         *
         * Listed newest-first so the first un-deprecated one is chosen.
         */
        val BUILT_IN_FALLBACKS = listOf(
            "gemini-2.5-flash",
            "gemini-2.0-flash",
            "gemini-1.5-flash",
            "gemini-1.5-pro",
            "gemini-pro",
        )

        /** Maximum retry attempts before giving up with a user-visible error. */
        const val MAX_RETRIES = 3
    }
}

/**
 * Thrown when [GeminiModelResolver.resolveModel] exhausts every candidate
 * model and cannot find a working one for the current API key.
 */
class NoCompatibleGeminiModelException(message: String) : Exception(message)
