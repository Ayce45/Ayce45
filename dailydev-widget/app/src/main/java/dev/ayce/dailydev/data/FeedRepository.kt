package dev.ayce.dailydev.data

import android.content.Context
import androidx.glance.appwidget.updateAll
import dev.ayce.dailydev.data.api.AuthException
import dev.ayce.dailydev.data.api.DailyDevApi
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.data.model.Post
import dev.ayce.dailydev.data.model.toPost
import dev.ayce.dailydev.glance.DailyDevWidget
import java.io.File

object FeedRepository {

    /** Plafond dur d'articles cumulés : budget mémoire bitmap des RemoteViews. */
    const val MAX_TOTAL_POSTS = 30

    /**
     * Fetch → prefetch des images → écriture cache → rafraîchissement du widget.
     * Ne lève jamais : les erreurs deviennent un statut dans FeedState.
     */
    suspend fun refresh(context: Context): FeedState {
        val previous = FeedCache.read(context)
        // Une lecture Keystore qui échoue est transitoire : ne surtout pas
        // conclure « non configuré », garder l'état précédent tel quel.
        val cookieRead = runCatching { CookieStore.get(context) }
        val cookie = cookieRead.getOrNull()

        val state = when {
            cookieRead.isFailure -> previous
            cookie.isNullOrBlank() -> FeedState(FeedState.Status.NOT_CONFIGURED)
            else -> try {
                val pageSize = SettingsStore.maxCards(context)
                val page = fetchWithSessionRefresh(context, cookie, pageSize)
                val posts = prefetchImages(context, page.nodes.mapNotNull { it.toPost() })
                evictUnusedImages(context, posts)
                FeedState(
                    status = FeedState.Status.OK,
                    posts = posts,
                    fetchedAtEpochMs = System.currentTimeMillis(),
                    endCursor = page.endCursor,
                )
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

    /** Page suivante du feed, ajoutée à la suite du cache (bouton « Charger plus »). */
    suspend fun loadMore(context: Context) {
        val current = FeedCache.read(context)
        val cookie = CookieStore.get(context) ?: return
        val cursor = current.endCursor ?: return
        if (current.posts.size >= MAX_TOTAL_POSTS) return

        try {
            val page = fetchWithSessionRefresh(context, cookie, SettingsStore.maxCards(context), cursor)
            val knownIds = current.posts.mapTo(mutableSetOf()) { it.id }
            val fresh = page.nodes.mapNotNull { it.toPost() }.filter { it.id !in knownIds }
            val merged = (current.posts + prefetchImages(context, fresh)).take(MAX_TOTAL_POSTS)
            evictUnusedImages(context, merged)
            FeedCache.write(
                context,
                current.copy(
                    status = FeedState.Status.OK,
                    posts = merged,
                    endCursor = if (merged.size >= MAX_TOTAL_POSTS) null else page.endCursor,
                ),
            )
            DailyDevWidget().updateAll(context)
        } catch (e: AuthException) {
            FeedCache.write(context, current.copy(status = FeedState.Status.AUTH_ERROR))
            DailyDevWidget().updateAll(context)
        } catch (e: Exception) {
            // Chargement optionnel : en cas d'échec réseau on garde la liste actuelle.
        }
    }

    /** Tente le fetch ; sur session expirée, la renouvelle via /boot et retente une fois. */
    private suspend fun fetchWithSessionRefresh(
        context: Context,
        cookie: String,
        first: Int,
        after: String? = null,
    ) = try {
        DailyDevApi.fetchFeed(cookie, first, after)
    } catch (e: AuthException) {
        val renewed = DailyDevApi.renewSession(cookie) ?: throw e
        CookieStore.set(context, renewed)
        DailyDevApi.fetchFeed(renewed, first, after)
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
