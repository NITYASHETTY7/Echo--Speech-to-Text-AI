package com.echo.dictation.domain.repository

import com.echo.dictation.domain.ai.AIJob
import kotlinx.coroutines.flow.Flow

interface AIJobRepository {
    suspend fun createJob(job: AIJob): Result<Unit>
    suspend fun updateJob(job: AIJob): Result<Unit>
    suspend fun getJob(id: String): AIJob?
    fun observeJobsForTranscript(transcriptId: String): Flow<List<AIJob>>
    fun observeLatestJobForTranscript(transcriptId: String): Flow<AIJob?>
}
