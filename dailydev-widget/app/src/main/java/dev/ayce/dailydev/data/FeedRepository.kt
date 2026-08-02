package dev.ayce.dailydev.data

import android.content.Context
import androidx.glance.appwidget.updateAll
import dev.ayce.dailydev.data.api.AuthException
import dev.ayce.dailydev.data.api.DailyDevApi
import dev.ayce.dailydev.data.api.StreakInfo
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.data.model.FeedType
import dev.ayce.dailydev.data.model.Post
import dev.ayce.dailydev.data.model.toPost
import dev.ayce.dailydev.glance.DailyDevWidget
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

object FeedRepository {

    /** Hard cap on accumulated posts: RemoteViews bitmap memory budget. */
    const val MAX_TOTAL_POSTS = 30

    /**
     * Fetch -> prefetch images -> write cache -> refresh the widget.
     * Never throws: errors become a status in FeedState.
     */
    suspend fun refresh(context: Context): FeedState {
        val previous = FeedCache.read(context)
        // A failing Keystore read is transient: never conclude "not configured",
        // keep the previous state as-is.
        val cookieRead = runCatching { CookieStore.get(context) }
        val cookie = cookieRead.getOrNull()

        val state = when {
            cookieRead.isFailure -> previous
            cookie.isNullOrBlank() -> FeedState(FeedState.Status.NOT_CONFIGURED)
            else -> try {
                val pageSize = SettingsStore.maxCards(context)
                val feedType = SettingsStore.feedType(context)
                val page = fetchWithSessionRefresh(context, cookie, pageSize, feedType = feedType)
                val posts = prefetchImages(context, page.nodes.mapNotNull { it.toPost() })
                evictUnusedImages(context, posts)
                val streakInfo = DailyDevApi.fetchStreak(cookie)
                FeedState(
                    status = FeedState.Status.OK,
                    posts = posts,
                    fetchedAtEpochMs = System.currentTimeMillis(),
                    endCursor = page.endCursor,
                    feedSource = page.source,
                    streak = streakInfo?.current ?: previous.streak,
                    streakAtRisk = streakInfo?.let { isStreakAtRisk(it) } ?: previous.streakAtRisk,
                )
            } catch (e: AuthException) {
                previous.copy(status = FeedState.Status.AUTH_ERROR, lastError = e.message)
            } catch (e: Exception) {
                previous.copy(status = FeedState.Status.NETWORK_ERROR, lastError = e.toString())
            }
        }

        DebugLog.log(
            "refresh done: ${state.status} · ${state.posts.size} posts · " +
                "source=${state.feedSource ?: "-"} · streak=${state.streak ?: "-"} · atRisk=${state.streakAtRisk}"
        )
        FeedCache.write(context, state)
        DailyDevWidget().updateAll(context)
        return state
    }

    /** Next page of the feed, appended to the cache (the "Load more" button). */
    suspend fun loadMore(context: Context) {
        val current = FeedCache.read(context)
        val cookie = CookieStore.get(context) ?: return
        val cursor = current.endCursor ?: return
        if (current.posts.size >= MAX_TOTAL_POSTS || current.loadingMore) return

        FeedCache.write(context, current.copy(loadingMore = true))
        DailyDevWidget().updateAll(context)

        try {
            val feedType = SettingsStore.feedType(context)
            val page = fetchWithSessionRefresh(context, cookie, SettingsStore.maxCards(context), cursor, feedType)
            val knownIds = current.posts.mapTo(mutableSetOf()) { it.id }
            val fresh = page.nodes.mapNotNull { it.toPost() }.filter { it.id !in knownIds }
            val merged = (current.posts + prefetchImages(context, fresh)).take(MAX_TOTAL_POSTS)
            evictUnusedImages(context, merged)
            FeedCache.write(
                context,
                current.copy(
                    status = FeedState.Status.OK,
                    posts = merged,
                    loadingMore = false,
                    endCursor = if (merged.size >= MAX_TOTAL_POSTS) null else page.endCursor,
                ),
            )
            DailyDevWidget().updateAll(context)
        } catch (e: AuthException) {
            FeedCache.write(context, current.copy(status = FeedState.Status.AUTH_ERROR, loadingMore = false))
            DailyDevWidget().updateAll(context)
        } catch (e: Exception) {
            // Network failure: keep the current list, just leave the "loading" state.
            FeedCache.write(context, current.copy(loadingMore = false))
            DailyDevWidget().updateAll(context)
        }
    }

    /** "Not interested": hide the post on daily.dev and drop it from the widget. */
    suspend fun hidePost(context: Context, postId: String) {
        val cookie = CookieStore.get(context) ?: return
        runCatching { DailyDevApi.hidePost(cookie, postId) }
        val current = FeedCache.read(context)
        FeedCache.write(context, current.copy(posts = current.posts.filterNot { it.id == postId }))
        DailyDevWidget().updateAll(context)
    }

    /** Streak at risk when nothing was read today (last read date is before today). */
    private fun isStreakAtRisk(info: StreakInfo): Boolean {
        val current = info.current ?: return false
        if (current <= 0) return false
        val lastViewDate = info.lastViewAt?.let { raw ->
            runCatching {
                Instant.parse(raw).atZone(ZoneId.systemDefault()).toLocalDate()
            }.getOrNull()
        } ?: return false
        return lastViewDate.isBefore(LocalDate.now())
    }

    /** Tries the fetch; on expired session, renews via /boot and retries once. */
    private suspend fun fetchWithSessionRefresh(
        context: Context,
        cookie: String,
        first: Int,
        after: String? = null,
        feedType: FeedType = FeedType.FOR_YOU,
    ) = try {
        DailyDevApi.fetchFeed(cookie, first, after, feedType)
    } catch (e: AuthException) {
        DebugLog.log("session expired -> renewing via /boot")
        val renewed = DailyDevApi.renewSession(cookie) ?: throw e
        DebugLog.log("session renewed via /boot")
        CookieStore.set(context, renewed)
        DailyDevApi.fetchFeed(renewed, first, after, feedType)
    }

    private suspend fun prefetchImages(context: Context, posts: List<Post>): List<Post> =
        posts.map { post ->
            val thumb = post.imageUrl?.let {
                ImageCache.fetch(context, it, ImageCache.THUMB_MAX_WIDTH, ImageCache.THUMB_MAX_HEIGHT)
            }
            val logo = post.sourceLogoUrl?.let {
                ImageCache.fetch(context, it, ImageCache.LOGO_MAX_SIZE, ImageCache.LOGO_MAX_SIZE)
            }
            post.copy(imageFile = thumb?.absolutePath, sourceLogoFile = logo?.absolutePath)
        }

    private fun evictUnusedImages(context: Context, posts: List<Post>) {
        val keep = posts
            .flatMap { listOfNotNull(it.imageFile, it.sourceLogoFile) }
            .map { File(it).name }
            .toSet()
        ImageCache.evictExcept(context, keep)
    }
}
