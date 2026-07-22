package dev.ayce.dailydev.glance

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import dev.ayce.dailydev.data.FeedCache
import dev.ayce.dailydev.data.ImageCache
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.glance.layouts.LargeLayout
import dev.ayce.dailydev.glance.layouts.MediumLayout
import dev.ayce.dailydev.glance.layouts.SmallLayout
import dev.ayce.dailydev.work.RefreshScheduler

/** Données prêtes à rendre : bitmaps décodés en amont, Glance ne chargeant rien lui-même. */
data class RenderData(
    val state: FeedState,
    val thumbs: Map<String, Bitmap>,
    val logos: Map<String, Bitmap>,
)

class DailyDevWidget : GlanceAppWidget() {

    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(220.dp, 180.dp)
        val LARGE = DpSize(220.dp, 320.dp)

        // Plafond dur pour rester sous le budget bitmap RemoteViews.
        const val MAX_RENDERED_POSTS = 10
    }

    override val sizeMode: SizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val state = FeedCache.read(context)
        val posts = state.posts.take(MAX_RENDERED_POSTS)
        val thumbs = buildMap {
            posts.forEach { post ->
                post.imageFile?.let { path ->
                    ImageCache.decodeFile(path)?.let { put(post.id, it) }
                }
            }
        }
        val logos = buildMap {
            posts.forEach { post ->
                post.sourceLogoFile?.let { path ->
                    ImageCache.decodeFile(path)?.let { put(post.id, it) }
                }
            }
        }
        val render = RenderData(state.copy(posts = posts), thumbs, logos)

        provideContent {
            WidgetContent(render)
        }
    }
}

@Composable
private fun WidgetContent(render: RenderData) {
    val size = LocalSize.current
    when {
        size.height >= DailyDevWidget.LARGE.height -> LargeLayout(render)
        size.width >= DailyDevWidget.MEDIUM.width -> MediumLayout(render)
        else -> SmallLayout(render)
    }
}

class DailyDevWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyDevWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        RefreshScheduler.ensureScheduled(context)
        RefreshScheduler.refreshNow(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        RefreshScheduler.cancel(context)
    }
}
