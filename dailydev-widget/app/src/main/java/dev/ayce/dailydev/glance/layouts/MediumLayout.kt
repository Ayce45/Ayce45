package dev.ayce.dailydev.glance.layouts

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.glance.Palette
import dev.ayce.dailydev.glance.RenderData
import dev.ayce.dailydev.glance.components.AuthErrorCard
import dev.ayce.dailydev.glance.components.EmptyCard
import dev.ayce.dailydev.glance.components.HeaderBar
import dev.ayce.dailydev.glance.components.NotConfiguredCard
import dev.ayce.dailydev.glance.components.PostCardCompact

/** 4x2 / 3x3 : header + jusqu'à 3 cards compactes, sans scroll. */
@Composable
fun MediumLayout(render: RenderData) {
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
            state.posts.take(3).forEach { post ->
                PostCardCompact(post, render.thumbs[post.id])
                Spacer(GlanceModifier.height(4.dp))
            }
        }
    }
}
