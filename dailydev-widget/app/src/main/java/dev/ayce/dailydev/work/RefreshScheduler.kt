package dev.ayce.dailydev.work

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import dev.ayce.dailydev.data.SettingsStore
import java.util.concurrent.TimeUnit

object RefreshScheduler {
    private const val PERIODIC_WORK = "feed_refresh"
    private const val ONE_SHOT_WORK = "feed_refresh_now"

    private val networkConstraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()

    /** Idempotent (KEEP) : appelé depuis App.onCreate et le placement du widget. */
    fun ensureScheduled(context: Context) {
        enqueuePeriodic(context, SettingsStore.DEFAULT_INTERVAL_MINUTES, ExistingPeriodicWorkPolicy.KEEP)
    }

    /** Remplace la planification quand l'utilisateur change l'intervalle. */
    fun reschedule(context: Context, intervalMinutes: Int) {
        enqueuePeriodic(context, intervalMinutes, ExistingPeriodicWorkPolicy.UPDATE)
    }

    fun refreshNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<FeedRefreshWorker>()
            .setConstraints(networkConstraints)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(ONE_SHOT_WORK, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_WORK)
    }

    private fun enqueuePeriodic(context: Context, intervalMinutes: Int, policy: ExistingPeriodicWorkPolicy) {
        val interval = maxOf(15, intervalMinutes).toLong()
        val request = PeriodicWorkRequestBuilder<FeedRefreshWorker>(interval, TimeUnit.MINUTES)
            .setConstraints(networkConstraints)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(PERIODIC_WORK, policy, request)
    }
}
