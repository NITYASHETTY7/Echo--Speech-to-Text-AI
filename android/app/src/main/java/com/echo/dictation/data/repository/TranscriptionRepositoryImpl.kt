package com.echo.dictation.data.repository

import android.util.Log
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.data.local.db.TranscriptionDao
import com.echo.dictation.data.local.db.TranscriptionEntity
import com.echo.dictation.domain.ai.AIRepository
import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.ai.VersionType
import com.echo.dictation.domain.model.Transcription
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.domain.session.SessionManager
import com.echo.dictation.speech.provider.ProviderSettings
import com.echo.dictation.speech.provider.SpeechProviderFactory
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import java.io.File
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of [TranscriptionRepository].
 *
 * Account isolation guarantee:
 * [history] uses [flatMapLatest] on [SessionManager.currentUser] so the Room
 * query re-subscribes with the correct userId the instant the session changes.
 *
 * - Sign-out  → currentUser emits null  → userId = "local"
 *               Signed-in records are tagged with the user's Firebase uid,
 *               never with "local", so the history list immediately becomes empty.
 * - Sign-in as User B → currentUser emits User B → userId = User B's uid
 *               Only User B's rows are returned. User A's rows are never visible.
 *
 * Room Flows are cold; flatMapLatest cancels the previous subscription and opens
 * a new one every time currentUser changes, so the switch is synchronous from
 * the UI's perspective (the next collected value is the new user's list).
 */
@OptIn(ExperimentalCoroutinesApi::class)
@Singleton
class TranscriptionRepositoryImpl @Inject constructor(
    private val factory: SpeechProviderFactory,
    private val providerSettings: ProviderSettings,
    private val dao: TranscriptionDao,
    private val prefs: AppPreferences,
    private val aiRepository: AIRepository,
    private val sessionManager: SessionManager,
) : TranscriptionRepository {

    /**
     * Snapshot of the current user's UID for write operations.
     *
     * Resolution order: in-memory session → [com.google.firebase.auth.FirebaseAuth]
     * (persisted across process death) → "local".
     *
     * The FirebaseAuth fallback matters: if the session has not been populated yet
     * for any reason, a signed-in user's transcription would otherwise be written
     * with userId="local", making it invisible to the history Flow (which filters on
     * userId) and preventing it from ever being attributed to the right owner.
     */
    private val currentUserId: String
        get() = sessionManager.currentUser.value?.uid
            ?: runCatching { com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid }.getOrNull()
            ?: "local"

    override suspend fun transcribe(file: File, model: String): Result<Transcription> {
        Log.d(TAG, "╔══ PIPELINE START ══════════════════════════════════")
        Log.d(TAG, "║ [1] audio file  : ${file.absolutePath}")

        return runCatching {
            require(file.exists() && file.length() > 0) {
                "Audio file is empty or missing: ${file.absolutePath}"
            }

            val selectedModel = providerSettings.selectedModel.ifBlank { model }
            val language = prefs.language.takeIf { it.isNotBlank() && it != "auto" }

            val provider  = factory.getProvider()
            val sttResult = provider.transcribe(file, selectedModel, language)
            val rawText   = sttResult.text

            if (rawText.isEmpty()) {
                Log.d(TAG, "║ Empty transcript — returning without saving")
                return@runCatching Transcription(
                    id        = UUID.randomUUID().toString(),
                    text      = "",
                    timestamp = System.currentTimeMillis(),
                    model     = selectedModel,
                    audioPath = file.absolutePath,
                    userId    = currentUserId,
                )
            }

            val id   = UUID.randomUUID().toString()
            val item = Transcription(
                id        = id,
                text      = rawText,
                timestamp = System.currentTimeMillis(),
                model     = selectedModel,
                audioPath = file.absolutePath,
                userId    = currentUserId,
            )

            // 1. Persist the transcription row
            dao.insert(item.toEntity())
            Log.d(TAG, "║ [2] Inserted transcription $id to Room DB")

            // 2. Immediately save Original version — preserves untouched STT output forever
            val originalVersion = TranscriptVersion(
                id           = UUID.randomUUID().toString(),
                transcriptId = id,
                versionType  = VersionType.Original,
                createdAt    = item.timestamp,
                provider     = providerSettings.selectedProvider.displayName,
                model        = selectedModel,
                content      = rawText,
                metadata     = mapOf("source" to "stt"),
            )
            aiRepository.saveVersion(originalVersion)
            Log.d(TAG, "║ [3] Saved Original version for $id")

            item
        }.also { result ->
            if (result.isSuccess) {
                Log.d(TAG, "╚══ PIPELINE SUCCESS — text.length=${result.getOrNull()?.text?.length}")
            } else {
                Log.e(TAG, "╚══ PIPELINE FAILURE — ${result.exceptionOrNull()?.message}")
            }
        }
    }

    /**
     * Returns a Flow that re-subscribes to Room whenever either the authenticated
     * user OR the retention preference changes.
     *
     * Flow chain:
     *   combine(sessionManager.currentUser, prefs.retentionFlow) { user, retentionDays -> ... }
     *     flatMapLatest {
     *         dao.observeSince(limit, uid, since)  ← new Room Flow
     *             .map { toDomain() }
     *     }
     *
     * Retention logic:
     *   retentionDays <= 0  → since = 0L  (show everything)
     *   retentionDays > 0   → since = now - retentionDays * 86_400_000
     *
     * Changing the retention setting in SettingsViewModel calls
     * `prefs.retention = days` which updates prefs.retentionFlow,
     * triggering flatMapLatest to cancel the current Room subscription
     * and open a new one with the updated time window.
     */
    override fun history(limit: Int): Flow<List<Transcription>> =
        kotlinx.coroutines.flow.combine(
            sessionManager.currentUser,
            prefs.retentionFlow,
        ) { user, retentionDays ->
            val userId = user?.uid
                ?: runCatching { com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid }.getOrNull()
                ?: "local"
            val since  = if (retentionDays <= 0) 0L
                         else System.currentTimeMillis() - retentionDays * 24L * 60 * 60 * 1000
            Log.d(TAG, "History resubscribing — userId=$userId retentionDays=$retentionDays since=$since")
            Pair(userId, since)
        }.flatMapLatest { (userId, since) ->
            dao.observeSince(limit, userId, since).map { list -> list.map { it.toDomain() } }
        }

    override suspend fun sync(): Result<Unit> = Result.success(Unit)

    override suspend fun delete(id: String) = dao.delete(id)

    override suspend fun updateText(id: String, text: String) = dao.updateText(id, text)

    private fun Transcription.toEntity() =
        TranscriptionEntity(id, text, timestamp, model, audioPath, userId, synced, isFavorite, isPinned)

    private fun TranscriptionEntity.toDomain() =
        Transcription(id, text, timestamp, model, audioPath, userId, synced, isFavorite, isPinned, syncStatus)

    companion object {
        private const val TAG = "TranscriptionRepo"
    }
}
