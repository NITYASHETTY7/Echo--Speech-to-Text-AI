package com.echo.dictation.domain.sync

import kotlinx.coroutines.flow.StateFlow

sealed interface SyncState {
    data object Idle : SyncState
    data object Syncing : SyncState
    data class Success(val lastSyncedAt: Long = System.currentTimeMillis()) : SyncState
    data class Failed(val message: String) : SyncState
    data object Offline : SyncState
    data class Conflict(val details: String) : SyncState
}

enum class LocalSyncStatus {
    PENDING,
    SYNCED,
    FAILED,
    CONFLICT
}

interface SyncManager {
    val syncState: StateFlow<SyncState>
    val isOnline: StateFlow<Boolean>

    suspend fun triggerSync(): Result<Unit>
    suspend fun uploadPendingChanges(): Result<Unit>
    suspend fun downloadRemoteUpdates(): Result<Unit>
    suspend fun syncUserPreferences(): Result<Unit>
    /**
     * Full restore from Firestore for the signed-in user.
     * Downloads ALL transcripts with no time filter so reinstall + login
     * always recovers the complete history.
     * Non-blocking — callers should launch this in a background scope.
     */
    suspend fun restoreRecentHistory(): Result<Unit>
}
