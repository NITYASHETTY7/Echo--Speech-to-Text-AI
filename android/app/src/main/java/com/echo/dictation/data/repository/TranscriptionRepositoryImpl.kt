package com.echo.dictation.data.repository

import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.data.local.db.TranscriptionDao
import com.echo.dictation.data.local.db.TranscriptionEntity
import com.echo.dictation.domain.model.Transcription
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.speech.GroqTranscriptionService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.io.File
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Concrete [TranscriptionRepository].
 *
 * Replaces the Flask -> Groq proxy path with a direct call to [GroqTranscriptionService],
 * which POSTs the audio file straight to https://api.groq.com/openai/v1/audio/transcriptions.
 *
 * Room persistence is unchanged: every successful transcription is written to the
 * local database and surfaced via [history] as before.
 *
 * The [sync] function previously merged history from the Flask server. Since there
 * is no longer a backend, sync is a no-op. All history is local. The function
 * signature is kept so no callers need to change.
 */
@Singleton
class TranscriptionRepositoryImpl @Inject constructor(
    private val groqService: GroqTranscriptionService,
    private val dao: TranscriptionDao,
    private val prefs: AppPreferences,
) : TranscriptionRepository {

    // --- Transcribe ---

    override suspend fun transcribe(file: File, model: String): Result<Transcription> =
        runCatching {
            require(file.exists() && file.length() > 0) { "Audio file is empty" }

            // Read language preference; null / "auto" -> Groq auto-detects.
            val language = prefs.language.takeIf { it.isNotBlank() && it != "auto" }

            val text = groqService.transcribe(file, model, language)

            // Empty string means the transcription was discarded as a hallucination
            // (high no_speech_prob or known filler phrase). Treat as no speech detected
            // rather than an error — the caller will show a "no speech" toast.
            if (text.isEmpty()) return@runCatching Transcription(
                id = UUID.randomUUID().toString(),
                text = "",
                timestamp = System.currentTimeMillis(),
                model = model,
                audioPath = file.absolutePath,
                userId = "local",
            )

            val item = Transcription(
                id = UUID.randomUUID().toString(),
                text = text,
                timestamp = System.currentTimeMillis(),
                model = model,
                audioPath = file.absolutePath,
                userId = "local",
            )
            dao.insert(item.toEntity())
            item
        }

    // --- History ---

    override fun history(limit: Int): Flow<List<Transcription>> =
        dao.observe(limit).map { list -> list.map { it.toDomain() } }

    // --- Sync (no-op - no backend to sync with) ---

    override suspend fun sync(): Result<Unit> = Result.success(Unit)

    // --- Delete ---

    override suspend fun delete(id: String) = dao.delete(id)

    // --- Mapping helpers ---

    private fun Transcription.toEntity() =
        TranscriptionEntity(id, text, timestamp, model, audioPath, userId, synced)

    private fun TranscriptionEntity.toDomain() =
        Transcription(id, text, timestamp, model, audioPath, userId, synced)
}
