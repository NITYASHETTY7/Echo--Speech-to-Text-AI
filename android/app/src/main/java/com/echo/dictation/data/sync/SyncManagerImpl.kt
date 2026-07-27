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

    private fun checkInitialNetwork(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val activeNetwork = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun registerNetworkCallback() {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d(TAG, "Network available — triggering sync")
                _isOnline.value = true
                syncScope.launch { triggerSync() }
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "Network lost")
                _isOnline.value = false
                _syncState.value = SyncState.Offline
            }
        })
    }

    // ── Full sync cycle ───────────────────────────────────────────────────────

    override suspend fun triggerSync(): Result<Unit> {
        val user = sessionManager.currentUser.value
        if (user == null) {
            Log.d(TAG, "triggerSync: no user — skipping")
            _syncState.value = SyncState.Idle
            return Result.success(Unit)
        }
        if (!_isOnline.value) {
            _syncState.value = SyncState.Offline
            return Result.success(Unit)
        }
        if (firestore == null) {
            _syncState.value = SyncState.Failed("Firestore not initialized")
            return Result.failure(IllegalStateException("Firestore unavailable"))
        }

        _syncState.value = SyncState.Syncing
        return runCatching {
            uploadPendingChanges()
            downloadRemoteUpdates()
            syncUserPreferences()
            _syncState.value = SyncState.Success(System.currentTimeMillis())
            Log.d(TAG, "Full sync successful for ${user.uid}")
            Unit
        }.onFailure { ex ->
            Log.e(TAG, "Full sync failed: ${ex.message}", ex)
            _syncState.value = SyncState.Failed(ex.message ?: "Sync error")
        }
    }

    // ── Upload ────────────────────────────────────────────────────────────────

    override suspend fun uploadPendingChanges(): Result<Unit> = runCatching {
        val user = sessionManager.currentUser.value ?: run {
            Log.d(TAG, "uploadPendingChanges: no user"); return@runCatching Unit
        }
        val db = firestore ?: run {
            Log.w(TAG, "uploadPendingChanges: Firestore null"); return@runCatching Unit
        }

        // Transcriptions
        val pendingTranscriptions = transcriptionDao.getPendingSyncTranscriptions()
        Log.d(TAG, "Uploading ${pendingTranscriptions.size} pending transcriptions")
        for (item in pendingTranscriptions) {
            val doc = hashMapOf(
                "ownerUid"    to user.uid,
                "id"          to item.id,
                "text"        to item.text,
                "timestamp"   to item.timestamp,
                "model"       to item.model,
                "audioPath"   to item.audioPath,
                "userId"      to user.uid,
                "syncVersion" to item.syncVersion,
                "updatedAt"   to item.updatedAt,
                "deleted"     to item.deleted,
            )
            db.collection(COLLECTION_TRANSCRIPTS).document(item.id)
                .set(doc, SetOptions.merge()).await()
            transcriptionDao.insert(item.copy(syncStatus = "SYNCED", lastSyncedAt = System.currentTimeMillis()))
            Log.d(TAG, "Uploaded transcript ${item.id}")
        }

        // Versions
        val pendingVersions = versionDao.getPendingSyncVersions()
        Log.d(TAG, "Uploading ${pendingVersions.size} pending versions")
        for (ver in pendingVersions) {
            val doc = hashMapOf(
                "ownerUid"     to user.uid,
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
            db.collection(COLLECTION_VERSIONS).document(ver.id)
                .set(doc, SetOptions.merge()).await()
            versionDao.insertVersion(ver.copy(syncStatus = "SYNCED", lastSyncedAt = System.currentTimeMillis()))
            Log.d(TAG, "Uploaded version ${ver.id} (${ver.versionType})")
        }

        // AI jobs
        val pendingJobs = aiJobDao.getPendingSyncJobs()
        for (job in pendingJobs) {
            val doc = hashMapOf(
                "ownerUid"        to user.uid,
                "id"              to job.id,
                "transcriptId"    to job.transcriptId,
                "versionType"     to job.versionType,
                "promptTemplateId" to job.promptTemplateId,
                "provider"        to job.provider,
                "model"           to job.model,
                "status"          to job.status,
                "retryCount"      to job.retryCount,
                "createdAt"       to job.createdAt,
                "startedAt"       to job.startedAt,
                "completedAt"     to job.completedAt,
                "processingTimeMs" to job.processingTimeMs,
                "errorMessage"    to job.errorMessage,
                "syncVersion"     to job.syncVersion,
                "updatedAt"       to job.updatedAt,
                "deleted"         to job.deleted,
            )
            db.collection(COLLECTION_AI_JOBS).document(job.id)
                .set(doc, SetOptions.merge()).await()
            aiJobDao.insertOrUpdateJob(job.copy(syncStatus = "SYNCED", lastSyncedAt = System.currentTimeMillis()))
        }
    }

    // ── Download (incremental 48h window) ────────────────────────────────────

    override suspend fun downloadRemoteUpdates(): Result<Unit> = runCatching {
        val user = sessionManager.currentUser.value ?: return@runCatching Unit
        val db   = firestore ?: return@runCatching Unit
        val since = System.currentTimeMillis() - RECENT_HISTORY_WINDOW_MS

        // Single-field query: ownerUid only — avoids composite index requirement.
        // Client-side filter for the 48h window.
        val txSnap = db.collection(COLLECTION_TRANSCRIPTS)
            .whereEqualTo("ownerUid", user.uid)
            .get().await()

        var merged = 0
        for (doc in txSnap.documents) {
            val updatedAt = doc.getLong("updatedAt") ?: 0L
            if (updatedAt >= since) {
                mergeRemoteTranscription(doc, user.uid)
                merged++
            }
        }

        val verSnap = db.collection(COLLECTION_VERSIONS)
            .whereEqualTo("ownerUid", user.uid)
            .get().await()
        for (doc in verSnap.documents) {
            val updatedAt = doc.getLong("updatedAt") ?: 0L
            if (updatedAt >= since) mergeRemoteVersion(doc)
        }

        Log.d(TAG, "downloadRemoteUpdates: merged $merged transcripts for ${user.uid}")
    }

    // ── History restoration (sign-in / reinstall) ─────────────────────────────

    /**
     * Restores recent transcription history from Firestore immediately after sign-in.
     *
     * Uses a SINGLE-FIELD Firestore query (ownerUid only) to avoid composite index
     * requirements. The timestamp filter is applied client-side.
     *
     * This is safe because:
     * - Single-field queries on ownerUid are automatically indexed by Firestore.
     * - The result set per user is bounded (we only keep recent history).
     * - Client-side filtering is applied before Room insert.
     */
    override suspend fun restoreRecentHistory(): Result<Unit> {
        val user = sessionManager.currentUser.value
        if (user == null) {
            Log.w(TAG, "restoreRecentHistory: no user in session — aborting")
            return Result.success(Unit)
        }
        if (!_isOnline.value) {
            Log.d(TAG, "restoreRecentHistory: offline — will retry when connectivity returns")
            return Result.success(Unit)
        }
        val db = firestore
        if (db == null) {
            Log.e(TAG, "restoreRecentHistory: Firestore not initialized")
            return Result.failure(IllegalStateException("Firestore unavailable"))
        }

        Log.d(TAG, "restoreRecentHistory: starting for uid=${user.uid}")
        _syncState.value = SyncState.Syncing

        return runCatching {
            val since = System.currentTimeMillis() - (RECENT_RESTORE_DAYS * 24 * 60 * 60 * 1000L)

            // ── Step 1: Query transcriptions (single-field, always indexed) ──
            Log.d(TAG, "restoreRecentHistory: querying Firestore collection=$COLLECTION_TRANSCRIPTS ownerUid=${user.uid}")
            val txSnap = db.collection(COLLECTION_TRANSCRIPTS)
                .whereEqualTo("ownerUid", user.uid)
                .get()
                .await()

            Log.d(TAG, "restoreRecentHistory: Firestore returned ${txSnap.size()} transcript docs")

            var restored = 0
            val restoredIds = mutableListOf<String>()

            for (doc in txSnap.documents) {
                val timestamp = doc.getLong("timestamp") ?: 0L
                // Client-side recency filter
                if (timestamp >= since) {
                    mergeRemoteTranscription(doc, user.uid)
                    restoredIds.add(doc.id)
                    restored++
                    Log.d(TAG, "restoreRecentHistory: merged transcript ${doc.id} timestamp=$timestamp")
                } else {
                    Log.d(TAG, "restoreRecentHistory: skipping old transcript ${doc.id} timestamp=$timestamp (since=$since)")
                }
            }

            Log.d(TAG, "restoreRecentHistory: $restored transcripts merged into Room")

            // ── Step 2: Restore versions for restored transcripts ─────────────
            if (restoredIds.isNotEmpty()) {
                Log.d(TAG, "restoreRecentHistory: fetching versions for ${restoredIds.size} transcripts")
                restoredIds.chunked(30).forEach { chunk ->
                    val verSnap = db.collection(COLLECTION_VERSIONS)
                        .whereIn("transcriptId", chunk)
                        .get()
                        .await()
                    Log.d(TAG, "restoreRecentHistory: version query returned ${verSnap.size()} docs")
                    for (doc in verSnap.documents) {
                        mergeRemoteVersion(doc)
                    }
                }
            }

            _syncState.value = SyncState.Success(System.currentTimeMillis())
            Log.d(TAG, "restoreRecentHistory: complete — $restored transcripts restored for ${user.uid}")
            Unit
        }.onFailure { ex ->
            Log.e(TAG, "restoreRecentHistory: FAILED — ${ex.javaClass.simpleName}: ${ex.message}", ex)
            _syncState.value = SyncState.Failed(ex.message ?: "Restore failed")
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
        val user = sessionManager.currentUser.value ?: return@runCatching Unit
        val db   = firestore ?: return@runCatching Unit

        val ref = db.collection(COLLECTION_PREFERENCES).document(user.uid)
        val localPrefs = hashMapOf(
            "ownerUid"                    to user.uid,
            "grammarCorrectionEnabled"    to prefs.grammarCorrectionEnabled,
            "autoEnhanceAfterTranscription" to prefs.autoEnhanceAfterTranscription,
            "defaultRewriteStyle"         to prefs.defaultRewriteStyle,
            "defaultAiProvider"           to prefs.defaultAiProvider,
            "language"                    to prefs.language,
            "theme"                       to prefs.theme,
            "updatedAt"                   to System.currentTimeMillis(),
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
        Log.d(TAG, "syncUserPreferences: done for ${user.uid}")
    }

    companion object {
        private const val TAG = "SyncManagerImpl"
        private const val COLLECTION_TRANSCRIPTS  = "transcripts"
        private const val COLLECTION_VERSIONS     = "transcriptVersions"
        private const val COLLECTION_AI_JOBS      = "aiJobs"
        private const val COLLECTION_PREFERENCES  = "userPreferences"
        private const val RECENT_HISTORY_WINDOW_MS = 48L * 60 * 60 * 1000
        private const val RECENT_RESTORE_DAYS      = 2L
    }
}
