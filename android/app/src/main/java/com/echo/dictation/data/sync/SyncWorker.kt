package com.echo.dictation.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.echo.dictation.domain.sync.SyncManager
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * Background WorkManager worker that triggers cloud synchronization.
 *
 * Uses @HiltWorker + @AssistedInject so Hilt can inject [SyncManager] into
 * the worker — the standard CoroutineWorker constructor pattern is not
 * compatible with Hilt without this factory approach.
 */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val syncManager: SyncManager,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        Log.d(TAG, "SyncWorker triggered background synchronization")
        val result = syncManager.triggerSync()
        return if (result.isSuccess) {
            Result.success()
        } else {
            Log.w(TAG, "SyncWorker failed — scheduling retry")
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "SyncWorker"
        const val WORK_NAME = "echo_periodic_cloud_sync"

        fun schedulePeriodicSync(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val syncRequest = PeriodicWorkRequestBuilder<SyncWorker>(1, TimeUnit.HOURS)
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                syncRequest,
            )
            Log.d(TAG, "Scheduled periodic WorkManager sync (1h interval, network required)")
        }
    }
}
