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
     * Restores only recent history (last 48h) from Firestore immediately after
     * sign-in or on first launch after reinstall. Never blocks the UI.
     */
    suspend fun restoreRecentHistory(): Result<Unit>
}
