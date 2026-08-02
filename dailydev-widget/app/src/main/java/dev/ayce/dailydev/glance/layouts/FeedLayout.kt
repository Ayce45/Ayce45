package dev.ayce.dailydev.glance.layouts

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.background
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import dev.ayce.dailydev.data.FeedRepository
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.glance.Palette
import dev.ayce.dailydev.glance.RenderData
import dev.ayce.dailydev.glance.components.AuthErrorCard
import dev.ayce.dailydev.glance.components.EmptyCard
import dev.ayce.dailydev.glance.components.HeaderBar
import dev.ayce.dailydev.glance.components.LoadMoreCard
import dev.ayce.dailydev.glance.components.NotConfiguredCard
import dev.ayce.dailydev.glance.components.PostCardLarge

/**
 * Scrollable feed of cards, daily.dev-mobile style. In 2 columns each LazyColumn
 * item is a row of two fixed-height cards — a real RemoteViews grid would force a
 * uniform row height and clip cards. "Load more" paginates as a full-width item.
 */
@Composable
fun FeedLayout(render: RenderData, columns: Int) {
    val state = render.state
    when {
        state.status == FeedState.Status.NOT_CONFIGURED -> NotConfiguredCard()
        state.status == FeedState.Status.AUTH_ERROR -> AuthErrorCard()
        state.posts.isEmpty() -> EmptyCard()
        else -> Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(Palette.Background)
                .cornerRadius(20.dp)
                .padding(6.dp),
        ) {
            HeaderBar(state)
            Spacer(GlanceModifier.height(2.dp))
            LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                if (columns >= 2) {
                    items(
                        state.posts.chunked(2),
                        itemId = { it.first().id.hashCode().toLong() },
                    ) { pair ->
                        Row(modifier = GlanceModifier.fillMaxWidth()) {
                            pair.forEach { post ->
                                Box(modifier = GlanceModifier.defaultWeight().padding(3.dp)) {
                                    PostCardLarge(
                                        post = post,
                                        thumb = render.thumbs[post.id],
                                        logo = render.logos[post.id],
                                        browserPackage = render.browserPackage,
                                        uniform = true,
                                    )
                                }
                            }
                            if (pair.size == 1) {
                                Spacer(GlanceModifier.defaultWeight())
                            }
                        }
                    }
                } else {
                    items(state.posts, itemId = { it.id.hashCode().toLong() }) { post ->
                        Column(modifier = GlanceModifier.padding(3.dp)) {
                            PostCardLarge(
                                post = post,
                                thumb = render.thumbs[post.id],
                                logo = render.logos[post.id],
                                browserPackage = render.browserPackage,
                            )
                        }
                    }
                }
                if (state.endCursor != null && state.posts.size < FeedRepository.MAX_TOTAL_POSTS) {
                    item {
                        Column(modifier = GlanceModifier.padding(3.dp)) {
                            LoadMoreCard(loading = state.loadingMore)
                        }
                    }
                }
            }
        }
    }
}
