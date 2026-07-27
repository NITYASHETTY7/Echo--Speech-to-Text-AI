package com.echo.dictation.ai

import com.echo.dictation.domain.ai.AIJob
import com.echo.dictation.domain.ai.JobStatus
import com.echo.dictation.domain.ai.VersionType
import com.echo.dictation.domain.repository.AIJobRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class AIJobLifecycleTest {

    class FakeAIJobRepository : AIJobRepository {
        val jobs = mutableMapOf<String, AIJob>()

        override suspend fun createJob(job: AIJob): Result<Unit> {
            jobs[job.id] = job
            return Result.success(Unit)
        }

        override suspend fun updateJob(job: AIJob): Result<Unit> {
            jobs[job.id] = job
            return Result.success(Unit)
        }

        override suspend fun getJob(id: String): AIJob? = jobs[id]

        override fun observeJobsForTranscript(transcriptId: String): Flow<List<AIJob>> =
            flowOf(jobs.values.filter { it.transcriptId == transcriptId })

        override fun observeLatestJobForTranscript(transcriptId: String): Flow<AIJob?> =
            flowOf(jobs.values.filter { it.transcriptId == transcriptId }.lastOrNull())
    }

    @Test
    fun testAIJobStatusLifecycleTransitions() = runTest {
        val repository = FakeAIJobRepository()
        val jobId = UUID.randomUUID().toString()
        val transcriptId = "tx_100"

        // 1. Pending / Created
        val initialJob = AIJob(
            id = jobId,
            transcriptId = transcriptId,
            versionType = VersionType.Professional,
            status = JobStatus.PENDING,
            createdAt = System.currentTimeMillis()
        )
        repository.createJob(initialJob)
        assertEquals(JobStatus.PENDING, repository.getJob(jobId)?.status)

        // 2. Processing
        val processingJob = initialJob.copy(status = JobStatus.PROCESSING, startedAt = System.currentTimeMillis())
        repository.updateJob(processingJob)
        assertEquals(JobStatus.PROCESSING, repository.getJob(jobId)?.status)

        // 3. Completed
        val completedTime = System.currentTimeMillis()
        val completedJob = processingJob.copy(
            status = JobStatus.COMPLETED,
            completedAt = completedTime,
            processingTimeMs = 1200L
        )
        repository.updateJob(completedJob)

        val finalJob = repository.getJob(jobId)
        assertNotNull(finalJob)
        assertEquals(JobStatus.COMPLETED, finalJob?.status)
        assertEquals(1200L, finalJob?.processingTimeMs)
        assertNull(finalJob?.errorMessage)
    }

    @Test
    fun testAIJobFailureStatusTracking() = runTest {
        val repository = FakeAIJobRepository()
        val jobId = UUID.randomUUID().toString()

        val failedJob = AIJob(
            id = jobId,
            transcriptId = "tx_200",
            versionType = VersionType.Custom,
            status = JobStatus.FAILED,
            errorMessage = "API key expired"
        )
        repository.createJob(failedJob)

        val retrieved = repository.getJob(jobId)
        assertEquals(JobStatus.FAILED, retrieved?.status)
        assertEquals("API key expired", retrieved?.errorMessage)
    }
}
