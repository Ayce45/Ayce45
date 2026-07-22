package dev.ayce.dailydev.work

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dev.ayce.dailydev.data.FeedRepository
import dev.ayce.dailydev.data.model.FeedState

class FeedRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val state = FeedRepository.refresh(applicationContext)
        // Une erreur d'auth n'est pas retryable ; une erreur réseau l'est, un peu.
        return if (state.status == FeedState.Status.NETWORK_ERROR && runAttemptCount < 3) {
            Result.retry()
        } else {
            Result.success()
        }
    }
}
