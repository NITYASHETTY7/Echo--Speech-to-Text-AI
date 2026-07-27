package com.echo.dictation.data.local.db

import androidx.room.Database
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Dao
import androidx.room.Query
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.RoomDatabase
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "transcriptions")
data class TranscriptionEntity(
    @PrimaryKey val id: String,
    val text: String,
    val timestamp: Long,
    val model: String,
    val audioPath: String?,
    val userId: String,
    val synced: Boolean,
    val isFavorite: Boolean = false,
    val isPinned: Boolean = false,
    val syncStatus: String = "PENDING",
    val lastSyncedAt: Long? = null,
    val remoteId: String? = null,
    val syncVersion: Int = 1,
    val updatedAt: Long = System.currentTimeMillis(),
    val deleted: Boolean = false
)

@Dao
interface TranscriptionDao {
    @Query("SELECT * FROM transcriptions WHERE deleted = 0 AND userId = :userId ORDER BY isPinned DESC, timestamp DESC LIMIT :limit")
    fun observe(limit: Int, userId: String): Flow<List<TranscriptionEntity>>

    /**
     * Observe transcriptions newer than [since] (epoch millis).
     * Pass since = 0L to return all records (Forever mode).
     */
    @Query("SELECT * FROM transcriptions WHERE deleted = 0 AND userId = :userId AND timestamp >= :since ORDER BY isPinned DESC, timestamp DESC LIMIT :limit")
    fun observeSince(limit: Int, userId: String, since: Long): Flow<List<TranscriptionEntity>>

    /** Legacy unfiltered query — used only for sync/migration. */
    @Query("SELECT * FROM transcriptions WHERE deleted = 0 ORDER BY isPinned DESC, timestamp DESC LIMIT :limit")
    fun observeAll(limit: Int): Flow<List<TranscriptionEntity>>

    @Query("SELECT * FROM transcriptions WHERE deleted = 0")
    suspend fun all(): List<TranscriptionEntity>

    @Query("SELECT * FROM transcriptions WHERE syncStatus = 'PENDING'")
    suspend fun getPendingSyncTranscriptions(): List<TranscriptionEntity>

    @Query("SELECT * FROM transcriptions WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): TranscriptionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(items: List<TranscriptionEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: TranscriptionEntity)

    @Query("UPDATE transcriptions SET isFavorite = :favorite, updatedAt = :updatedAt, syncStatus = 'PENDING' WHERE id = :id")
    suspend fun setFavorite(id: String, favorite: Boolean, updatedAt: Long = System.currentTimeMillis())

    @Query("UPDATE transcriptions SET isPinned = :pinned, updatedAt = :updatedAt, syncStatus = 'PENDING' WHERE id = :id")
    suspend fun setPinned(id: String, pinned: Boolean, updatedAt: Long = System.currentTimeMillis())

    @Query("UPDATE transcriptions SET deleted = 1, syncStatus = 'PENDING', updatedAt = :updatedAt WHERE id = :id")
    suspend fun markDeleted(id: String, updatedAt: Long = System.currentTimeMillis())

    @Query("DELETE FROM transcriptions WHERE id = :id")
    suspend fun delete(id: String)

    @Query("UPDATE transcriptions SET text = :text, updatedAt = :updatedAt WHERE id = :id")
    suspend fun updateText(id: String, text: String, updatedAt: Long = System.currentTimeMillis())
}

@Dao
interface TranscriptVersionDao {
    @Query("SELECT * FROM transcript_versions WHERE transcriptId = :transcriptId AND deleted = 0 ORDER BY createdAt ASC")
    fun observeVersions(transcriptId: String): Flow<List<TranscriptVersionEntity>>

    @Query("SELECT * FROM transcript_versions WHERE transcriptId = :transcriptId AND deleted = 0 ORDER BY createdAt DESC LIMIT 1")
    suspend fun getLatestVersion(transcriptId: String): TranscriptVersionEntity?

    @Query("SELECT versionType FROM transcript_versions WHERE transcriptId = :transcriptId AND deleted = 0 ORDER BY createdAt DESC LIMIT 1")
    suspend fun getLatestVersionType(transcriptId: String): String?

    @Query("SELECT * FROM transcript_versions WHERE syncStatus = 'PENDING'")
    suspend fun getPendingSyncVersions(): List<TranscriptVersionEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertVersion(version: TranscriptVersionEntity)

    @Query("DELETE FROM transcript_versions WHERE transcriptId = :transcriptId")
    suspend fun deleteVersionsForTranscript(transcriptId: String)
}

@Database(
    entities = [TranscriptionEntity::class, TranscriptVersionEntity::class, AIJobEntity::class, ExportHistoryEntity::class],
    version = 6,
    exportSchema = false
)
abstract class EchoDatabase : RoomDatabase() {
    abstract fun transcriptions(): TranscriptionDao
    abstract fun versions(): TranscriptVersionDao
    abstract fun aiJobs(): AIJobDao
    abstract fun exportHistory(): ExportHistoryDao
}
