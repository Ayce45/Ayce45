package dev.ayce.dailydev.glance.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.Alignment
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.ayce.dailydev.R
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.glance.Palette
import dev.ayce.dailydev.glance.RefreshAction

@Composable
fun HeaderBar(state: FeedState) {
    val context = LocalContext.current
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "daily.dev",
            style = TextStyle(
                color = ColorProvider(Palette.TextPrimary),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
        if (state.status == FeedState.Status.NETWORK_ERROR) {
            Spacer(GlanceModifier.width(6.dp))
            Text(
                text = context.getString(R.string.badge_offline),
                style = TextStyle(color = ColorProvider(Palette.Accent), fontSize = 10.sp),
            )
        }
        Spacer(GlanceModifier.defaultWeight())
        Text(
            text = relativeTime(state.fetchedAtEpochMs),
            style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 10.sp),
        )
        Spacer(GlanceModifier.width(6.dp))
        Image(
            provider = ImageProvider(R.drawable.ic_refresh),
            contentDescription = context.getString(R.string.refresh_content_description),
            modifier = GlanceModifier.size(16.dp).clickable(actionRunCallback<RefreshAction>()),
        )
    }
}

private fun relativeTime(epochMs: Long): String {
    if (epochMs <= 0) return ""
    val minutes = ((System.currentTimeMillis() - epochMs) / 60_000).coerceAtLeast(0)
    return when {
        minutes < 1 -> "à l'instant"
        minutes < 60 -> "il y a $minutes min"
        else -> "il y a ${minutes / 60} h"
    }
}
