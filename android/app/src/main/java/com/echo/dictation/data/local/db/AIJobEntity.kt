package com.echo.dictation.data.local.db

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import com.echo.dictation.domain.ai.AIJob
import com.echo.dictation.domain.ai.JobStatus
import com.echo.dictation.domain.ai.VersionType
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "ai_jobs")
data class AIJobEntity(
    @PrimaryKey val id: String,
    val transcriptId: String,
    val versionType: String,
    val promptTemplateId: String?,
    val provider: String,
    val model: String,
    val status: String,
    val retryCount: Int,
    val createdAt: Long,
    val startedAt: Long?,
    val completedAt: Long?,
    val processingTimeMs: Long?,
    val errorMessage: String?,
    val syncStatus: String = "PENDING",
    val lastSyncedAt: Long? = null,
    val remoteId: String? = null,
    val syncVersion: Int = 1,
    val updatedAt: Long = System.currentTimeMillis(),
    val deleted: Boolean = false
)

fun AIJobEntity.toDomain(): AIJob = AIJob(
    id = id,
    transcriptId = transcriptId,
    versionType = runCatching { VersionType.valueOf(versionType) }.getOrDefault(VersionType.Custom),
    promptTemplateId = promptTemplateId,
    provider = provider,
    model = model,
    status = runCatching { JobStatus.valueOf(status) }.getOrDefault(JobStatus.FAILED),
    retryCount = retryCount,
    createdAt = createdAt,
    startedAt = startedAt,
    completedAt = completedAt,
    processingTimeMs = processingTimeMs,
    errorMessage = errorMessage
)

fun AIJob.toEntity(): AIJobEntity = AIJobEntity(
    id = id,
    transcriptId = transcriptId,
    versionType = versionType.name,
    promptTemplateId = promptTemplateId,
    provider = provider,
    model = model,
    status = status.name,
    retryCount = retryCount,
    createdAt = createdAt,
    startedAt = startedAt,
    completedAt = completedAt,
    processingTimeMs = processingTimeMs,
    errorMessage = errorMessage
)

@Dao
interface AIJobDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertOrUpdateJob(job: AIJobEntity)

    @Query("SELECT * FROM ai_jobs WHERE id = :id LIMIT 1")
    suspend fun getJobById(id: String): AIJobEntity?

    @Query("SELECT * FROM ai_jobs WHERE transcriptId = :transcriptId ORDER BY createdAt DESC")
    fun observeJobsForTranscript(transcriptId: String): Flow<List<AIJobEntity>>

    @Query("SELECT * FROM ai_jobs WHERE transcriptId = :transcriptId ORDER BY createdAt DESC LIMIT 1")
    fun observeLatestJobForTranscript(transcriptId: String): Flow<AIJobEntity?>

    @Query("SELECT * FROM ai_jobs WHERE syncStatus = 'PENDING'")
    suspend fun getPendingSyncJobs(): List<AIJobEntity>
}
