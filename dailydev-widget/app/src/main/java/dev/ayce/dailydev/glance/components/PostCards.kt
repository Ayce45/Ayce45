package dev.ayce.dailydev.glance.components

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.ayce.dailydev.data.model.Post
import dev.ayce.dailydev.glance.Palette
import dev.ayce.dailydev.glance.openUrl

/** Card compacte : petite vignette à gauche, titre sur 2 lignes, source. */
@Composable
fun PostCardCompact(post: Post, thumb: Bitmap?) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .background(Palette.Card)
            .cornerRadius(12.dp)
            .padding(8.dp)
            .clickable(openUrl(post.url)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (thumb != null) {
            Image(
                provider = ImageProvider(thumb),
                contentDescription = null,
                modifier = GlanceModifier.size(40.dp).cornerRadius(8.dp),
                contentScale = ContentScale.Crop,
            )
            Spacer(GlanceModifier.width(8.dp))
        }
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = post.title,
                maxLines = 2,
                style = TextStyle(
                    color = ColorProvider(Palette.TextPrimary),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
            post.sourceName?.let { name ->
                Text(
                    text = "$name · ▲ ${post.upvotes}",
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 10.sp),
                )
            }
        }
    }
}

/** Card complète : vignette 64dp, titre, logo + source, compteurs. */
@Composable
fun PostCardFull(post: Post, thumb: Bitmap?, logo: Bitmap?) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .background(Palette.Card)
            .cornerRadius(16.dp)
            .padding(10.dp)
            .clickable(openUrl(post.url)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (thumb != null) {
            Image(
                provider = ImageProvider(thumb),
                contentDescription = null,
                modifier = GlanceModifier.size(64.dp).cornerRadius(10.dp),
                contentScale = ContentScale.Crop,
            )
            Spacer(GlanceModifier.width(10.dp))
        }
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = post.title,
                maxLines = 2,
                style = TextStyle(
                    color = ColorProvider(Palette.TextPrimary),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Spacer(GlanceModifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (logo != null) {
                    Image(
                        provider = ImageProvider(logo),
                        contentDescription = null,
                        modifier = GlanceModifier.size(14.dp).cornerRadius(7.dp),
                        contentScale = ContentScale.Crop,
                    )
                    Spacer(GlanceModifier.width(4.dp))
                }
                Text(
                    text = post.sourceName ?: "",
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 10.sp),
                )
            }
            Spacer(GlanceModifier.height(2.dp))
            Text(
                text = buildMetaLine(post),
                maxLines = 1,
                style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 10.sp),
            )
        }
    }
}

private fun buildMetaLine(post: Post): String = buildString {
    append("▲ ").append(post.upvotes)
    append("  💬 ").append(post.comments)
    post.readTimeMinutes?.let { append("  ·  ").append(it).append(" min") }
}
