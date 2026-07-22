package dev.ayce.dailydev.data

import android.content.Context
import dev.ayce.dailydev.data.api.AuthException
import dev.ayce.dailydev.data.api.DailyDevApi
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.data.model.toPost
import dev.ayce.dailydev.glance.DailyDevWidget
import java.io.File
import androidx.glance.appwidget.updateAll

object FeedRepository {

    /**
     * Fetch → prefetch des images → écriture cache → rafraîchissement du widget.
     * Ne lève jamais : les erreurs deviennent un statut dans FeedState.
     */
    suspend fun refresh(context: Context): FeedState {
        val previous = FeedCache.read(context)
        val cookie = CookieStore.get(context)

        val state = when {
            cookie.isNullOrBlank() -> FeedState(FeedState.Status.NOT_CONFIGURED)
            else -> try {
                val maxCards = SettingsStore.maxCards(context)
                val nodes = DailyDevApi.fetchFeed(cookie, maxCards)
                val posts = nodes.mapNotNull { it.toPost() }.map { post ->
                    val thumb = post.imageUrl?.let {
                        ImageCache.fetch(context, it, ImageCache.THUMB_MAX_WIDTH, ImageCache.THUMB_MAX_HEIGHT)
                    }
                    val logo = post.sourceLogoUrl?.let {
                        ImageCache.fetch(context, it, ImageCache.LOGO_MAX_SIZE, ImageCache.LOGO_MAX_SIZE)
                    }
                    post.copy(imageFile = thumb?.absolutePath, sourceLogoFile = logo?.absolutePath)
                }
                val keep = posts
                    .flatMap { listOfNotNull(it.imageFile, it.sourceLogoFile) }
                    .map { File(it).name }
                    .toSet()
                ImageCache.evictExcept(context, keep)
                FeedState(FeedState.Status.OK, posts, System.currentTimeMillis())
            } catch (e: AuthException) {
                previous.copy(status = FeedState.Status.AUTH_ERROR)
            } catch (e: Exception) {
                previous.copy(status = FeedState.Status.NETWORK_ERROR)
            }
        }

        FeedCache.write(context, state)
        DailyDevWidget().updateAll(context)
        return state
    }
}
