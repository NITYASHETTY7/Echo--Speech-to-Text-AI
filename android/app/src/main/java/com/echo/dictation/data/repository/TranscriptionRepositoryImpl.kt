package com.echo.dictation.data.repository

import android.util.Log
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.data.local.db.TranscriptionDao
import com.echo.dictation.data.local.db.TranscriptionEntity
import com.echo.dictation.domain.model.Transcription
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.speech.provider.ProviderSettings
import com.echo.dictation.speech.provider.SpeechProviderFactory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.io.File
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TranscriptionRepositoryImpl @Inject constructor(
    private val factory: SpeechProviderFactory,
    private val providerSettings: ProviderSettings,
    private val dao: TranscriptionDao,
    private val prefs: AppPreferences,
) : TranscriptionRepository {

    override suspend fun transcribe(file: File, model: String): Result<Transcription> {
        Log.d(TAG, "╔══ PIPELINE START ══════════════════════════════════")
        Log.d(TAG, "║ [1] audio file  : ${file.absolutePath}")
        Log.d(TAG, "║ [2] file exists : ${file.exists()}")
        Log.d(TAG, "║ [3] file size   : ${file.length()} B")
        Log.d(TAG, "║ [4] model param : $model")

        return runCatching {
            require(file.exists() && file.length() > 0) { "Audio file is empty or missing: ${file.absolutePath}" }

            // ── Step 5: load provider settings ───────────────────────────────
            val selectedProvider = providerSettings.selectedProvider
            val selectedModel    = providerSettings.selectedModel.ifBlank { model }
            val language         = prefs.language.takeIf { it.isNotBlank() && it != "auto" }

            Log.d(TAG, "║ [5] selectedProvider : $selectedProvider")
            Log.d(TAG, "║ [6] selectedModel    : $selectedModel")
            Log.d(TAG, "║ [7] language         : ${language ?: "(auto)"}")

            // ── Step 6: build provider via factory ────────────────────────────
            Log.d(TAG, "║ [8] calling factory.getProvider()…")
            val provider = try {
                factory.getProvider()
            } catch (e: Exception) {
                Log.e(TAG, "║ [8] FAILED — factory.getProvider() threw: ${e::class.java.name}: ${e.message}", e)
                throw e
            }
            Log.d(TAG, "║ [9] provider instance : ${provider::class.java.simpleName}")
            Log.d(TAG, "║[10] provider config   : ${provider.config.displayName}  baseUrl=${
                if (provider.config.requiresCustomBaseUrl) "(custom)" else provider.config.defaultBaseUrl
            }")

            // ── Step 7: call provider.transcribe ─────────────────────────────
            Log.d(TAG, "║[11] calling provider.transcribe()…")
            val result = try {
                provider.transcribe(file, selectedModel, language)
            } catch (e: Exception) {
                Log.e(TAG, "║[11] FAILED — provider.transcribe() threw: ${e::class.java.name}: ${e.message}", e)
                throw e
            }
            Log.d(TAG, "║[12] provider.transcribe() returned — text.length=${result.text.length}")
            Log.d(TAG, "║[13] transcript : \"${result.text.take(120)}\"")

            // ── Step 8: persist to Room ───────────────────────────────────────
            val text = result.text
            if (text.isEmpty()) {
                Log.d(TAG, "║[14] empty transcript (hallucination/silence) — not saving to DB")
                return@runCatching Transcription(
                    id        = UUID.randomUUID().toString(),
                    text      = "",
                    timestamp = System.currentTimeMillis(),
                    model     = selectedModel,
                    audioPath = file.absolutePath,
                    userId    = "local",
                )
            }

            val item = Transcription(
                id        = UUID.randomUUID().toString(),
                text      = text,
                timestamp = System.currentTimeMillis(),
                model     = selectedModel,
                audioPath = file.absolutePath,
                userId    = "local",
            )
            Log.d(TAG, "║[14] inserting into Room DB…")
            dao.insert(item.toEntity())
            Log.d(TAG, "║[15] Room insert done")
            item
        }.also { result ->
            if (result.isSuccess) {
                Log.d(TAG, "╚══ PIPELINE SUCCESS — text.length=${result.getOrNull()?.text?.length}")
            } else {
                Log.e(TAG, "╚══ PIPELINE FAILURE — ${result.exceptionOrNull()?.let { "${it::class.java.name}: ${it.message}" }}")
            }
        }
    }

    override fun history(limit: Int): Flow<List<Transcription>> =
        dao.observe(limit).map { list -> list.map { it.toDomain() } }

    override suspend fun sync(): Result<Unit> = Result.success(Unit)

    override suspend fun delete(id: String) = dao.delete(id)

    private fun Transcription.toEntity() =
        TranscriptionEntity(id, text, timestamp, model, audioPath, userId, synced)

    private fun TranscriptionEntity.toDomain() =
        Transcription(id, text, timestamp, model, audioPath, userId, synced)

    companion object {
        private const val TAG = "TranscriptionRepo"
    }
}
