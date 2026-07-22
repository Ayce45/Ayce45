package dev.ayce.dailydev

import android.app.Application
import dev.ayce.dailydev.work.RefreshScheduler

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        RefreshScheduler.ensureScheduled(this)
    }
}
