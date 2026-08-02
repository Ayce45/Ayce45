package dev.ayce.dailydev.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.glance.GlanceId
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionStartActivity
import dev.ayce.dailydev.data.SettingsStore
import dev.ayce.dailydev.ui.HideActivity
import dev.ayce.dailydev.work.RefreshScheduler

/**
 * Opens an article, honoring the chosen browser: system default, an explicit
 * chooser, or a specific package (a browser, or the daily.dev app).
 */
fun openUrl(url: String, browserPackage: String): Action {
    val view = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val intent = when (browserPackage) {
        SettingsStore.BROWSER_DEFAULT -> view
        SettingsStore.BROWSER_ASK ->
            Intent.createChooser(view, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        else -> view.setPackage(browserPackage)
    }
    return actionStartActivity(intent)
}

fun hideAction(context: Context, postId: String): Action =
    actionStartActivity(
        Intent(context, HideActivity::class.java)
            .putExtra(HideActivity.EXTRA_POST_ID, postId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )

class RefreshAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        RefreshScheduler.refreshNow(context)
    }
}
