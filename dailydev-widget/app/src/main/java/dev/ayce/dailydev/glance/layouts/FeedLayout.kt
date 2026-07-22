package dev.ayce.dailydev.glance.layouts

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.background
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
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
 * Layout principal : liste scrollable de grandes cards façon extension Chrome,
 * avec « Charger plus » en dernier item tant qu'il reste des pages.
 */
@Composable
fun FeedLayout(render: RenderData) {
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
                .padding(8.dp),
        ) {
            HeaderBar(state)
            Spacer(GlanceModifier.height(4.dp))
            LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                items(state.posts, itemId = { it.id.hashCode().toLong() }) { post ->
                    Column {
                        PostCardLarge(
                            post = post,
                            thumb = render.thumbs[post.id],
                            logo = render.logos[post.id],
                        )
                        Spacer(GlanceModifier.height(6.dp))
                    }
                }
                if (state.endCursor != null && state.posts.size < FeedRepository.MAX_TOTAL_POSTS) {
                    item {
                        LoadMoreCard()
                    }
                }
            }
        }
    }
}
