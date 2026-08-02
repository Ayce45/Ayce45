package dev.ayce.dailydev.ui

import android.app.Activity
import android.os.Bundle
import dev.ayce.dailydev.appScope
import dev.ayce.dailydev.data.FeedRepository
import kotlinx.coroutines.launch

/**
 * Target of the "not interested" (✕) button. Invisible activity — the reliable
 * way to run an action from a RemoteViews list — that hides the post and closes.
 */
class HideActivity : Activity() {
    companion object {
        const val EXTRA_POST_ID = "post_id"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val postId = intent?.getStringExtra(EXTRA_POST_ID)
        if (!postId.isNullOrBlank()) {
            val appContext = applicationContext
            appScope.launch { FeedRepository.hidePost(appContext, postId) }
        }
        finish()
    }
}
