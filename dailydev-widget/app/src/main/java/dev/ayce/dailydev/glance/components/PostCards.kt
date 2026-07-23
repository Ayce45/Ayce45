package dev.ayce.dailydev.glance.components

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.ayce.dailydev.R
import dev.ayce.dailydev.data.model.Post
import dev.ayce.dailydev.glance.Palette
import dev.ayce.dailydev.glance.openUrl
import dev.ayce.dailydev.ui.LoadMoreActivity
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Card fidèle à la webapp mobile daily.dev : logo rond de la source, titre en
 * gras, « Aujourd'hui · 5 min de lecture », grande image, ▲ / 💬 en pied.
 *
 * En mode 2 colonnes (`uniform`), hauteur fixe : les RemoteViews n'alignent
 * proprement les rangées que si les deux cards font la même taille.
 */
@Composable
fun PostCardLarge(post: Post, thumb: Bitmap?, logo: Bitmap?, uniform: Boolean = false) {
    var modifier = GlanceModifier
        .fillMaxWidth()
        .background(Palette.Card)
        .cornerRadius(20.dp)
        .padding(12.dp)
        .clickable(openUrl(post.url))
    if (uniform) {
        modifier = modifier.height(230.dp)
    }
    Column(modifier = modifier) {
        if (logo != null) {
            Image(
                provider = ImageProvider(logo),
                contentDescription = post.sourceName,
                modifier = GlanceModifier.size(24.dp).cornerRadius(12.dp),
                contentScale = ContentScale.Crop,
            )
            Spacer(GlanceModifier.height(8.dp))
        }
        Text(
            text = post.title,
            maxLines = if (uniform) 2 else 3,
            style = TextStyle(
                color = ColorProvider(Palette.TextPrimary),
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
        Spacer(GlanceModifier.height(4.dp))
        Text(
            text = dateAndReadTime(post),
            maxLines = 1,
            style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 10.sp),
        )
        if (thumb != null) {
            Spacer(GlanceModifier.height(8.dp))
            Image(
                provider = ImageProvider(thumb),
                contentDescription = null,
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .height(if (uniform) 90.dp else 100.dp)
                    .cornerRadius(12.dp),
                contentScale = ContentScale.Crop,
            )
        }
        if (uniform) {
            Spacer(GlanceModifier.defaultWeight())
        }
        if (post.upvotes > 0 || post.comments > 0) {
            Spacer(GlanceModifier.height(8.dp))
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "▲ ${post.upvotes}",
                    style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 11.sp),
                )
                Spacer(GlanceModifier.defaultWeight())
                Text(
                    text = "💬 ${post.comments}",
                    style = TextStyle(color = ColorProvider(Palette.TextSecondary), fontSize = 11.sp),
                )
            }
        }
    }
}

/** Dernier item de la liste : va chercher la page suivante du feed. */
@Composable
fun LoadMoreCard(loading: Boolean) {
    var modifier = GlanceModifier
        .fillMaxWidth()
        .background(Palette.Card)
        .cornerRadius(20.dp)
        .padding(14.dp)
    if (!loading) {
        modifier = modifier.clickable(actionStartActivity<LoadMoreActivity>())
    }
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = LocalContext.current.getString(
                if (loading) R.string.load_more_loading else R.string.load_more
            ),
            style = TextStyle(
                color = ColorProvider(if (loading) Palette.TextSecondary else Palette.Accent),
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

private fun dateAndReadTime(post: Post): String {
    val date = post.createdAt?.let { raw ->
        runCatching {
            val day = Instant.parse(raw).atZone(ZoneId.systemDefault()).toLocalDate()
            when (day) {
                LocalDate.now() -> "Aujourd'hui"
                LocalDate.now().minusDays(1) -> "Hier"
                else -> DateTimeFormatter.ofPattern("d MMM", Locale.FRENCH).format(day)
            }
        }.getOrNull()
    }
    return listOfNotNull(
        date,
        post.readTimeMinutes?.let { "$it min de lecture" },
    ).joinToString(" · ")
}
