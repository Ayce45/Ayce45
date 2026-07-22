package dev.ayce.dailydev.glance.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.ayce.dailydev.R
import dev.ayce.dailydev.glance.Palette
import dev.ayce.dailydev.glance.RefreshAction
import dev.ayce.dailydev.ui.ConfigActivity
import dev.ayce.dailydev.ui.LoginActivity

@Composable
private fun MessageCard(text: String, action: Action) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(Palette.Card)
            .cornerRadius(20.dp)
            .padding(16.dp)
            .clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            maxLines = 4,
            style = TextStyle(
                color = ColorProvider(Palette.TextPrimary),
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

@Composable
fun NotConfiguredCard() {
    MessageCard(
        text = LocalContext.current.getString(R.string.state_not_configured),
        action = actionStartActivity<ConfigActivity>(),
    )
}

@Composable
fun AuthErrorCard() {
    // Rouvre la WebView : si la session y est encore vivante, le cookie se
    // recapture et l'écran se referme sans re-login.
    MessageCard(
        text = LocalContext.current.getString(R.string.state_auth_error),
        action = actionStartActivity<LoginActivity>(),
    )
}

@Composable
fun EmptyCard() {
    MessageCard(
        text = LocalContext.current.getString(R.string.state_empty),
        action = actionRunCallback<RefreshAction>(),
    )
}
