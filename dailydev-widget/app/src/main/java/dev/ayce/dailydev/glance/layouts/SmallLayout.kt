package dev.ayce.dailydev.glance.layouts

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.glance.Palette
import dev.ayce.dailydev.glance.RenderData
import dev.ayce.dailydev.glance.components.AuthErrorCard
import dev.ayce.dailydev.glance.components.EmptyCard
import dev.ayce.dailydev.glance.components.NotConfiguredCard
import dev.ayce.dailydev.glance.openUrl

/** 2x2 : une seule card héro. */
@Composable
fun SmallLayout(render: RenderData) {
    val state = render.state
    when {
        state.status == FeedState.Status.NOT_CONFIGURED -> NotConfiguredCard()
        state.status == FeedState.Status.AUTH_ERROR -> AuthErrorCard()
        state.posts.isEmpty() -> EmptyCard()
        else -> {
            val post = state.posts.first()
            Column(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .background(Palette.Card)
                    .cornerRadius(20.dp)
                    .padding(10.dp)
                    .clickable(openUrl(post.url)),
            ) {
                render.thumbs[post.id]?.let { thumb ->
                    Image(
                        provider = ImageProvider(thumb),
                        contentDescription = null,
                        modifier = GlanceModifier.fillMaxWidth().height(52.dp).cornerRadius(10.dp),
                        contentScale = ContentScale.Crop,
                    )
                    Spacer(GlanceModifier.height(6.dp))
                }
                Text(
                    text = post.title,
                    maxLines = 2,
                    style = TextStyle(
                        color = ColorProvider(Palette.TextPrimary),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Spacer(GlanceModifier.defaultWeight())
                Text(
                    text = listOfNotNull(post.sourceName, "▲ ${post.upvotes}").joinToString(" · "),
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 10.sp),
                )
            }
        }
    }
}
