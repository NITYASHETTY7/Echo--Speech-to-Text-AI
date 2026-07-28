package com.echo.dictation.data.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import com.echo.dictation.data.local.AppPreferences
import com.echo.dictation.data.local.db.AIJobDao
import com.echo.dictation.data.local.db.TranscriptionDao
import com.echo.dictation.data.local.db.TranscriptionEntity
import com.echo.dictation.data.local.db.TranscriptVersionDao
import com.echo.dictation.data.local.db.TranscriptVersionEntity
import com.echo.dictation.domain.session.SessionManager
import com.echo.dictation.domain.sync.SyncManager
import com.echo.dictation.domain.sync.SyncState
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SyncManagerImpl @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessionManager: SessionManager,
    private val prefs: AppPreferences,
    private val transcriptionDao: TranscriptionDao,
    private val versionDao: TranscriptVersionDao,
    private val aiJobDao: AIJobDao,
) : SyncManager {

    private val firestore: FirebaseFirestore?
        get() = runCatching { FirebaseFirestore.getInstance() }.getOrNull()

    private val _syncState = MutableStateFlow<SyncState>(SyncState.Idle)
    override val syncState: StateFlow<SyncState> = _syncState.asStateFlow()

    private val _isOnline = MutableStateFlow(checkInitialNetwork())
    override val isOnline: StateFlow<Boolean> = _isOnline.asStateFlow()

    private val syncScope = CoroutineScope(Dispatchers.IO)

    init {
        registerNetworkCallback()
    }

    /**
     * Authoritative owner UID for all cloud operations.
     *
     * Resolution order:
     *  1. [FirebaseAuth.currentUser] — persisted on disk by the Firebase SDK and
     *     therefore valid immediately after process death / cold start.
     *  2. [SessionManager.currentUser] — in-memory mirror.
     *
     * FirebaseAuth is checked FIRST because the in-memory session used to be
     * populated only by a lazily-created singleton that frequently never ran.
     * Relying on the session alone was the reason every upload aborted before
     * reaching Firestore.
     */
    private fun resolveOwnerUid(): String? {
        val fbUid = runCatching { FirebaseAuth.getInstance().currentUser?.uid }.getOrNull()
        if (fbUid != null) return fbUid
        val sessionUid = sessionManager.currentUser.value?.uid
        if (sessionUid != null) {
            Log.w(DIAG, "resolveOwnerUid: FirebaseAuth had no user; falling back to session uid=$sessionUid")
        }
        return sessionUid
    }

    /**
     * Re-tags any transcription/version rows that were written while the session was
     * unresolved (userId == "local") with the real owner UID.
     *
     * Without this, records created before the session fix stay invisible to the
     * history Flow (which filters on userId) and are effectively orphaned.
     */
    private suspend fun backfillLocalRows(uid: String) {
        val orphans = transcriptionDao.all().filter { it.userId == LOCAL_USER_ID }
        if (orphans.isEmpty()) return
        Log.w(DIAG, "backfillLocalRows: re-tagging ${orphans.size} orphaned 'local' rows → uid=$uid")
        orphans.forEach { row ->
            transcriptionDao.insert(
                row.copy(
                    userId     = uid,
                    syncStatus = "PENDING",
                    updatedAt  = System.currentTimeMillis(),
                )
            )
            Log.d(DIAG, "  re-tagged transcription ${row.id} → uid=$uid, syncStatus=PENDING")
        }
    }

    private fun checkInitialNetwork(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val activeNetwork = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun registerNetworkCallback() {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(DIAG, "NetworkCallback.onAvailable — isOnline → true, triggering sync")
                _isOnline.value = true
                syncScope.launch { triggerSync() }
            }
            override fun onLost(network: Network) {
                Log.d(DIAG, "NetworkCallback.onLost — isOnline → false")
                _isOnline.value = false
                _syncState.value = SyncState.Offline
            }
        })
    }

    // ── Full sync cycle ───────────────────────────────────────────────────────

    override suspend fun triggerSync(): Result<Unit> {
        val fbUser = FirebaseAuth.getInstance().currentUser
        val sessionUser = sessionManager.currentUser.value
        Log.d(DIAG, "triggerSync() — FirebaseAuth.currentUser=${fbUser?.uid} " +
                "sessionUser=${sessionUser?.uid} isOnline=${_isOnline.value}")

        if (resolveOwnerUid() == null) {
            Log.w(DIAG, "triggerSync: no authenticated user — skipping")
            _syncState.value = SyncState.Idle
            return Result.success(Unit)
        }
        if (!_isOnline.value) {
            Log.w(DIAG, "triggerSync: offline — skipping")
            _syncState.value = SyncState.Offline
            return Result.success(Unit)
        }
        if (firestore == null) {
            Log.e(DIAG, "triggerSync: Firestore.getInstance() returned null — Firebase may not be initialized")
            _syncState.value = SyncState.Failed("Firestore not initialized")
            return Result.failure(IllegalStateException("Firestore unavailable"))
        }

        _syncState.value = SyncState.Syncing
        return try {
            // Propagate sub-operation failures instead of reporting a false success.
            val upload   = uploadPendingChanges()
            val download = downloadRemoteUpdates()
            val prefsRes = syncUserPreferences()

            val firstFailure = listOf(upload, download, prefsRes).firstOrNull { it.isFailure }
            if (firstFailure != null) {
                val ex = firstFailure.exceptionOrNull()!!
                Log.e(DIAG, "triggerSync: PARTIAL/FAILED — ${ex.javaClass.name}: ${ex.message}", ex)
                _syncState.value = SyncState.Failed(ex.message ?: "Sync error")
                return Result.failure(ex)
            }

            _syncState.value = SyncState.Success(System.currentTimeMillis())
            Log.d(DIAG, "triggerSync: full sync SUCCESS for uid=${resolveOwnerUid()}")
            Result.success(Unit)
        } catch (ex: Exception) {
            Log.e(DIAG, "triggerSync: FAILED — ${ex.javaClass.name}: ${ex.message}", ex)
            _syncState.value = SyncState.Failed(ex.message ?: "Sync error")
            Result.failure(ex)
        }
    }

    // ── Upload ────────────────────────────────────────────────────────────────

    override suspend fun uploadPendingChanges(): Result<Unit> {
        // ── Step A: Resolve owner UID (FirebaseAuth first — survives process death) ──
        val fbUser = FirebaseAuth.getInstance().currentUser
        val sessionUser = sessionManager.currentUser.value
        Log.d(DIAG, "uploadPendingChanges() called")
        Log.d(DIAG, "  FirebaseAuth.currentUser uid  = ${fbUser?.uid ?: "NULL"}")
        Log.d(DIAG, "  FirebaseAuth.currentUser email= ${fbUser?.email ?: "NULL"}")
        Log.d(DIAG, "  FirebaseAuth.isAnonymous      = ${fbUser?.isAnonymous}")
        Log.d(DIAG, "  SessionManager.currentUser uid= ${sessionUser?.uid ?: "NULL"}")

        val ownerUid = resolveOwnerUid()
        if (ownerUid == null) {
            // Genuinely signed out. Return FAILURE (not success) so the caller and
            // WorkManager see a real error instead of a false positive.
            Log.e(DIAG, "uploadPendingChanges: ABORT — no authenticated user (FirebaseAuth AND session are null)")
            return Result.failure(IllegalStateException("Not signed in — cannot upload"))
        }
        Log.d(DIAG, "  Resolved ownerUid = $ownerUid")

        // ── Step B: Verify Firestore ──────────────────────────────────────────
        val db = firestore
        if (db == null) {
            Log.e(DIAG, "uploadPendingChanges: ABORT — Firestore.getInstance() returned null")
            return Result.failure(IllegalStateException("Firestore unavailable"))
        }
        Log.d(DIAG, "  Firestore app=${db.app.name} projectId=${db.app.options.projectId}")

        // ── Step C: Adopt any rows orphaned with userId='local' ───────────────
        backfillLocalRows(ownerUid)

        // ── Step D: Query pending transcriptions ──────────────────────────────
        val pending = transcriptionDao.getPendingSyncTranscriptions()
        Log.d(DIAG, "  Pending transcriptions in Room: ${pending.size}")
        if (pending.isEmpty()) {
            val all = transcriptionDao.all()
            Log.w(DIAG, "  No pending transcriptions. Total rows in Room: ${all.size}")
            all.forEach { t ->
                Log.d(DIAG, "    Row: id=${t.id} userId=${t.userId} " +
                        "syncStatus=${t.syncStatus} textLen=${t.text.length} ts=${t.timestamp}")
            }
        }

        // ── Step E: Upload each pending record ────────────────────────────────
        var uploaded = 0
        var failed = 0
        // Records the first exception encountered so the caller learns the upload
        // did not fully succeed. Previously this method always returned success,
        // which is why "upload SUCCESS" appeared in logs while nothing was written.
        var lastError: Exception? = null
        for (item in pending) {
            val path = "$COLLECTION_TRANSCRIPTS/${item.id}"
            Log.d(DIAG, "  Uploading → path=$path ownerUid=$ownerUid " +
                    "userId=${item.userId} syncStatus=${item.syncStatus} textLen=${item.text.length}")

            val doc = hashMapOf(
                "ownerUid"    to ownerUid,
                "id"          to item.id,
                "text"        to item.text,
                "timestamp"   to item.timestamp,
                "model"       to item.model,
                "audioPath"   to item.audioPath,
                "userId"      to ownerUid,
                "syncVersion" to item.syncVersion,
                "updatedAt"   to item.updatedAt,
                "deleted"     to item.deleted,
            )

            try {
                Log.d(DIAG, "    set() → collection('$COLLECTION_TRANSCRIPTS').document('${item.id}')")
                db.collection(COLLECTION_TRANSCRIPTS).document(item.id)
                    .set(doc, SetOptions.merge()).await()
                transcriptionDao.insert(item.copy(
                    userId = ownerUid,
                    syncStatus = "SYNCED",
                    lastSyncedAt = System.currentTimeMillis(),
                ))
                uploaded++
                Log.d(DIAG, "    SUCCESS — $path written; Room marked SYNCED")
            } catch (ex: Exception) {
                failed++
                lastError = ex
                // Full stacktrace — nothing swallowed.
                Log.e(DIAG, "    FAILED $path — ${ex.javaClass.name}: ${ex.message}", ex)
                if (ex is com.google.firebase.firestore.FirebaseFirestoreException) {
                    Log.e(DIAG, "    FirestoreException code=${ex.code}")
                }
                transcriptionDao.insert(item.copy(syncStatus = "PENDING"))
            }
        }
        Log.d(DIAG, "  Transcripts: uploaded=$uploaded failed=$failed")

        // ── Step E: Upload pending versions ──────────────────────────────────
        val pendingVersions = versionDao.getPendingSyncVersions()
        Log.d(DIAG, "  Pending versions in Room: ${pendingVersions.size}")
        for (ver in pendingVersions) {
            val path = "$COLLECTION_VERSIONS/${ver.id}"
            Log.d(DIAG, "  Uploading version → path=$path transcriptId=${ver.transcriptId} type=${ver.versionType}")
            val doc = hashMapOf(
                "ownerUid"     to ownerUid,
                "id"           to ver.id,
                "transcriptId" to ver.transcriptId,
                "versionType"  to ver.versionType,
                "createdAt"    to ver.createdAt,
                "provider"     to ver.provider,
                "model"        to ver.model,
                "content"      to ver.content,
                "metadataJson" to ver.metadataJson,
                "syncVersion"  to ver.syncVersion,
                "updatedAt"    to ver.updatedAt,
                "deleted"      to ver.deleted,
            )
            try {
                db.collection(COLLECTION_VERSIONS).document(ver.id)
                    .set(doc, SetOptions.merge()).await()
                versionDao.insertVersion(ver.copy(syncStatus = "SYNCED", lastSyncedAt = System.currentTimeMillis()))
                Log.d(DIAG, "    SUCCESS — version ${ver.id} written to Firestore")
            } catch (ex: Exception) {
                lastError = ex
                Log.e(DIAG, "    FAILED to upload version ${ver.id} — ${ex.javaClass.name}: ${ex.message}", ex)
            }
        }

        // ── Step F: Upload pending AI jobs ────────────────────────────────────
        val pendingJobs = aiJobDao.getPendingSyncJobs()
        Log.d(DIAG, "  Pending AI jobs in Room: ${pendingJobs.size}")
        for (job in pendingJobs) {
            val doc = hashMapOf(
                "ownerUid"         to ownerUid,
                "id"               to job.id,
                "transcriptId"     to job.transcriptId,
                "versionType"      to job.versionType,
                "promptTemplateId" to job.promptTemplateId,
                "provider"         to job.provider,
                "model"            to job.model,
                "status"           to job.status,
                "retryCount"       to job.retryCount,
                "createdAt"        to job.createdAt,
                "startedAt"        to job.startedAt,
                "completedAt"      to job.completedAt,
                "processingTimeMs" to job.processingTimeMs,
                "errorMessage"     to job.errorMessage,
                "syncVersion"      to job.syncVersion,
                "updatedAt"        to job.updatedAt,
                "deleted"          to job.deleted,
            )
            try {
                db.collection(COLLECTION_AI_JOBS).document(job.id)
                    .set(doc, SetOptions.merge()).await()
                aiJobDao.insertOrUpdateJob(job.copy(syncStatus = "SYNCED", lastSyncedAt = System.currentTimeMillis()))
                Log.d(DIAG, "  SUCCESS — job ${job.id} written to Firestore")
            } catch (ex: Exception) {
                lastError = ex
                Log.e(DIAG, "  FAILED to upload job ${job.id} — ${ex.javaClass.name}: ${ex.message}", ex)
            }
        }

        Log.d(DIAG, "uploadPendingChanges: complete")
        if (lastError != null) {
            Log.e(DIAG, "uploadPendingChanges: finished WITH FAILURES — reporting failure to caller")
            return Result.failure(lastError!!)
        }
        return Result.success(Unit)
    }

    // ── Download ──────────────────────────────────────────────────────────────

    /**
     * Incrementally pulls changes from Firestore that arrived since the last sync.
     * Uses a 48-hour window for the incremental pull; for full restore after reinstall
     * use [restoreRecentHistory] which has no time filter.
     */
    override suspend fun downloadRemoteUpdates(): Result<Unit> = runCatching {
        val uid  = resolveOwnerUid() ?: return@runCatching Unit
        val db   = firestore ?: return@runCatching Unit
        val since = System.currentTimeMillis() - RECENT_HISTORY_WINDOW_MS

        // Single equality filter on ownerUid only. Adding whereGreaterThanOrEqualTo("updatedAt")
        // would require a composite index (equality + range on different fields), so the
        // time window is applied client-side instead.
        val txSnap = db.collection(COLLECTION_TRANSCRIPTS)
            .whereEqualTo("ownerUid", uid)
            .get().await()

        var merged = 0
        for (doc in txSnap.documents) {
            if ((doc.getLong("updatedAt") ?: 0L) >= since) {
                mergeRemoteTranscription(doc, uid)
                merged++
            }
        }
        val verSnap = db.collection(COLLECTION_VERSIONS)
            .whereEqualTo("ownerUid", uid)
            .get().await()
        for (doc in verSnap.documents) {
            if ((doc.getLong("updatedAt") ?: 0L) >= since) {
                mergeRemoteVersion(doc)
            }
        }
        Log.d(DIAG, "downloadRemoteUpdates: merged $merged transcripts for uid=$uid")
        Unit
    }.also { result ->
        result.onFailure { ex ->
            Log.e(DIAG, "downloadRemoteUpdates: FAILED — ${ex.javaClass.name}: ${ex.message}", ex)
        }
    }

    // ── History restoration ───────────────────────────────────────────────────

    /**
     * Full restore after reinstall / first sign-in.
     * Downloads ALL transcripts for this user with NO time filter.
     * This is intentionally unconditional: Firestore is the permanent source of truth.
     */
    override suspend fun restoreRecentHistory(): Result<Unit> {
        val fbUser = FirebaseAuth.getInstance().currentUser
        val sessionUser = sessionManager.currentUser.value
        Log.d(DIAG, "restoreRecentHistory() called")
        Log.d(DIAG, "  FirebaseAuth.currentUser uid  = ${fbUser?.uid ?: "NULL"}")
        Log.d(DIAG, "  FirebaseAuth.currentUser email= ${fbUser?.email ?: "NULL"}")
        Log.d(DIAG, "  SessionManager.currentUser uid= ${sessionUser?.uid ?: "NULL"}")
        Log.d(DIAG, "  isOnline = ${_isOnline.value}")

        val ownerUid = resolveOwnerUid()
        if (ownerUid == null) {
            Log.e(DIAG, "restoreRecentHistory: ABORT — no authenticated user")
            return Result.failure(IllegalStateException("Not signed in — cannot restore"))
        }
        if (!_isOnline.value) {
            Log.w(DIAG, "restoreRecentHistory: deferred — offline. " +
                    "Will retry when NetworkCallback.onAvailable() fires.")
            return Result.failure(IllegalStateException("Offline — restore deferred"))
        }
        val db = firestore
        if (db == null) {
            Log.e(DIAG, "restoreRecentHistory: ABORT — Firestore.getInstance() returned null")
            return Result.failure(IllegalStateException("Firestore unavailable"))
        }

        _syncState.value = SyncState.Syncing

        return try {
            // ── NO time filter: restore every transcript belonging to this user ──
            Log.d(DIAG, "  Query: collection='$COLLECTION_TRANSCRIPTS' " +
                    "whereEqualTo('ownerUid', '$ownerUid')  [no timestamp filter]")
            Log.d(DIAG, "  Firestore projectId=${db.app.options.projectId}")

            val txSnap = db.collection(COLLECTION_TRANSCRIPTS)
                .whereEqualTo("ownerUid", ownerUid)
                .get().await()

            Log.d(DIAG, "  Firestore returned ${txSnap.size()} documents from '$COLLECTION_TRANSCRIPTS'")

            var restored = 0
            val restoredIds = mutableListOf<String>()

            for (doc in txSnap.documents) {
                val timestamp = doc.getLong("timestamp") ?: 0L
                val isDeleted = doc.getBoolean("deleted") ?: false
                Log.d(DIAG, "    Doc id=${doc.id} timestamp=$timestamp deleted=$isDeleted " +
                        "ownerUid=${doc.getString("ownerUid")} textLen=${doc.getString("text")?.length ?: 0}")
                if (!isDeleted) {
                    mergeRemoteTranscription(doc, ownerUid)
                    restoredIds.add(doc.id)
                    restored++
                    Log.d(DIAG, "    → merged into Room")
                } else {
                    Log.d(DIAG, "    → skipped (deleted)")
                }
            }

            Log.d(DIAG, "  $restored transcripts merged into Room")

            // Restore associated versions.
            //
            // NOTE: this queries by ownerUid ONLY (a single equality filter), then filters
            // transcriptIds client-side. Two reasons:
            //  1. Security rules for transcriptVersions authorise on ownerUid. A query that
            //     filtered only on transcriptId is NOT satisfiable against such a rule and
            //     Firestore rejects the whole list query with PERMISSION_DENIED.
            //  2. Combining whereIn(transcriptId) with whereEqualTo(ownerUid) would require
            //     a composite index. Filtering client-side avoids that entirely.
            if (restoredIds.isNotEmpty()) {
                val wanted = restoredIds.toSet()
                val verSnap = db.collection(COLLECTION_VERSIONS)
                    .whereEqualTo("ownerUid", ownerUid)
                    .get().await()
                Log.d(DIAG, "  Version query returned ${verSnap.size()} docs for ownerUid=$ownerUid")
                var mergedVersions = 0
                for (doc in verSnap.documents) {
                    if (doc.getString("transcriptId") in wanted) {
                        mergeRemoteVersion(doc)
                        mergedVersions++
                    }
                }
                Log.d(DIAG, "  $mergedVersions versions merged into Room")
            }

            _syncState.value = SyncState.Success(System.currentTimeMillis())
            Log.d(DIAG, "restoreRecentHistory: COMPLETE — $restored transcripts restored for uid=$ownerUid")
            Result.success(Unit)
        } catch (ex: Exception) {
            Log.e(DIAG, "restoreRecentHistory: FAILED — ${ex.javaClass.name}: ${ex.message}", ex)
            if (ex is com.google.firebase.firestore.FirebaseFirestoreException) {
                Log.e(DIAG, "  FirestoreException code=${ex.code}")
            }
            _syncState.value = SyncState.Failed(ex.message ?: "Restore failed")
            Result.failure(ex)
        }
    }

    // ── Merge helpers ─────────────────────────────────────────────────────────

    private suspend fun mergeRemoteTranscription(
        doc: com.google.firebase.firestore.DocumentSnapshot,
        uid: String,
    ) {
        val remoteId        = doc.id
        val remoteUpdatedAt = doc.getLong("updatedAt") ?: System.currentTimeMillis()
        val text            = doc.getString("text") ?: ""
        val timestamp       = doc.getLong("timestamp") ?: System.currentTimeMillis()
        val model           = doc.getString("model") ?: ""
        val audioPath       = doc.getString("audioPath")
        val isDeleted       = doc.getBoolean("deleted") ?: false

        val local = transcriptionDao.getById(remoteId)
        if (local == null || remoteUpdatedAt >= local.updatedAt) {
            transcriptionDao.insert(
                TranscriptionEntity(
                    id           = remoteId,
                    text         = text,
                    timestamp    = timestamp,
                    model        = model,
                    audioPath    = audioPath,
                    userId       = uid,
                    synced       = true,
                    syncStatus   = "SYNCED",
                    lastSyncedAt = System.currentTimeMillis(),
                    remoteId     = remoteId,
                    updatedAt    = remoteUpdatedAt,
                    deleted      = isDeleted,
                )
            )
        }
    }

    private suspend fun mergeRemoteVersion(doc: com.google.firebase.firestore.DocumentSnapshot) {
        val verId           = doc.id
        val remoteUpdatedAt = doc.getLong("updatedAt") ?: System.currentTimeMillis()
        val transcriptId    = doc.getString("transcriptId") ?: return
        val versionType     = doc.getString("versionType") ?: "Custom"
        val createdAt       = doc.getLong("createdAt") ?: System.currentTimeMillis()
        val provider        = doc.getString("provider") ?: "Groq"
        val model           = doc.getString("model") ?: "llama-3.3-70b-versatile"
        val content         = doc.getString("content") ?: ""
        val metadataJson    = doc.getString("metadataJson") ?: "{}"
        val isDeleted       = doc.getBoolean("deleted") ?: false

        versionDao.insertVersion(
            TranscriptVersionEntity(
                id           = verId,
                transcriptId = transcriptId,
                versionType  = versionType,
                createdAt    = createdAt,
                provider     = provider,
                model        = model,
                content      = content,
                metadataJson = metadataJson,
                syncStatus   = "SYNCED",
                lastSyncedAt = System.currentTimeMillis(),
                remoteId     = verId,
                updatedAt    = remoteUpdatedAt,
                deleted      = isDeleted,
            )
        )
    }

    // ── Preferences sync ──────────────────────────────────────────────────────

    override suspend fun syncUserPreferences(): Result<Unit> = runCatching {
        val uid = resolveOwnerUid() ?: return@runCatching Unit
        val db  = firestore ?: return@runCatching Unit
        val ref = db.collection(COLLECTION_PREFERENCES).document(uid)
        val localPrefs = hashMapOf(
            "ownerUid"                      to uid,
            "grammarCorrectionEnabled"      to prefs.grammarCorrectionEnabled,
            "autoEnhanceAfterTranscription" to prefs.autoEnhanceAfterTranscription,
            "defaultRewriteStyle"           to prefs.defaultRewriteStyle,
            "defaultAiProvider"             to prefs.defaultAiProvider,
            "language"                      to prefs.language,
            "theme"                         to prefs.theme,
            "updatedAt"                     to System.currentTimeMillis(),
        )
        ref.set(localPrefs, SetOptions.merge()).await()
        val remoteDoc = ref.get().await()
        if (remoteDoc.exists()) {
            remoteDoc.getBoolean("grammarCorrectionEnabled")?.let      { prefs.grammarCorrectionEnabled = it }
            remoteDoc.getBoolean("autoEnhanceAfterTranscription")?.let { prefs.autoEnhanceAfterTranscription = it }
            remoteDoc.getString("defaultRewriteStyle")?.let            { prefs.defaultRewriteStyle = it }
            remoteDoc.getString("defaultAiProvider")?.let              { prefs.defaultAiProvider = it }
            remoteDoc.getString("language")?.let                       { prefs.language = it }
            remoteDoc.getString("theme")?.let                          { prefs.theme = it }
        }
    }.also { result ->
        result.onFailure { ex ->
            Log.e(DIAG, "syncUserPreferences: FAILED — ${ex.javaClass.name}: ${ex.message}", ex)
        }
    }

    companion object {
        private const val DIAG = "CloudSync"      // filter by this tag in Logcat
        private const val TAG  = "SyncManagerImpl"
        private const val COLLECTION_TRANSCRIPTS  = "transcripts"
        private const val COLLECTION_VERSIONS     = "transcriptVersions"
        private const val COLLECTION_AI_JOBS      = "aiJobs"
        private const val COLLECTION_PREFERENCES  = "userPreferences"
        /** Placeholder userId written when no session was resolved. */
        private const val LOCAL_USER_ID           = "local"
        /** Window for incremental sync only — not used for full restore. */
        private const val RECENT_HISTORY_WINDOW_MS = 48L * 60 * 60 * 1000
    }
}
