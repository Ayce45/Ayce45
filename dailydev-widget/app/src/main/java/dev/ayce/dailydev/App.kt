package dev.ayce.dailydev

import android.app.Application
import dev.ayce.dailydev.work.RefreshScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Scope lié au processus : pour du travail qui doit survivre à la fermeture d'une activité. */
val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        RefreshScheduler.ensureScheduled(this)
    }
}
