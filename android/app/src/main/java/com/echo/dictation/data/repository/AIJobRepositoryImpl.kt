package com.echo.dictation.data.repository

import com.echo.dictation.data.local.db.AIJobDao
import com.echo.dictation.data.local.db.toDomain
import com.echo.dictation.data.local.db.toEntity
import com.echo.dictation.domain.ai.AIJob
import com.echo.dictation.domain.repository.AIJobRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AIJobRepositoryImpl @Inject constructor(
    private val aiJobDao: AIJobDao,
) : AIJobRepository {

    override suspend fun createJob(job: AIJob): Result<Unit> = runCatching {
        aiJobDao.insertOrUpdateJob(job.toEntity())
    }

    override suspend fun updateJob(job: AIJob): Result<Unit> = runCatching {
        aiJobDao.insertOrUpdateJob(job.toEntity())
    }

    override suspend fun getJob(id: String): AIJob? =
        aiJobDao.getJobById(id)?.toDomain()

    override fun observeJobsForTranscript(transcriptId: String): Flow<List<AIJob>> =
        aiJobDao.observeJobsForTranscript(transcriptId).map { list -> list.map { it.toDomain() } }

    override fun observeLatestJobForTranscript(transcriptId: String): Flow<AIJob?> =
        aiJobDao.observeLatestJobForTranscript(transcriptId).map { it?.toDomain() }
}
