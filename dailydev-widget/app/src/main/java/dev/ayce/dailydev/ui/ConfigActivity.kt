package dev.ayce.dailydev.ui

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import dev.ayce.dailydev.R
import dev.ayce.dailydev.data.CookieStore
import dev.ayce.dailydev.data.SettingsStore
import dev.ayce.dailydev.work.RefreshScheduler
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class ConfigActivity : ComponentActivity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        // Un retour arrière doit annuler proprement le placement du widget.
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            setResult(RESULT_CANCELED, widgetResultIntent())
        }

        val hasCookie = CookieStore.isConfigured(this)
        val initialInterval = runBlocking { SettingsStore.refreshIntervalMinutes(this@ConfigActivity) }
        val initialMaxCards = runBlocking { SettingsStore.maxCards(this@ConfigActivity) }

        setContent {
            DailyDevTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    ConfigScreen(
                        hasCookie = hasCookie,
                        initialInterval = initialInterval,
                        initialMaxCards = initialMaxCards,
                        onSave = ::save,
                    )
                }
            }
        }
    }

    private fun save(cookie: String, intervalMinutes: Int, maxCards: Int) {
        lifecycleScope.launch {
            if (cookie.isNotBlank()) {
                CookieStore.set(this@ConfigActivity, cookie)
            }
            SettingsStore.save(this@ConfigActivity, intervalMinutes, maxCards)
            RefreshScheduler.reschedule(this@ConfigActivity, intervalMinutes)
            RefreshScheduler.refreshNow(this@ConfigActivity)
            if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                setResult(RESULT_OK, widgetResultIntent())
            }
            finish()
        }
    }

    private fun widgetResultIntent(): Intent =
        Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
}

private val intervalOptions = listOf(
    15 to "15 min",
    30 to "30 min",
    60 to "1 h",
    180 to "3 h",
)

@Composable
private fun ConfigScreen(
    hasCookie: Boolean,
    initialInterval: Int,
    initialMaxCards: Int,
    onSave: (cookie: String, intervalMinutes: Int, maxCards: Int) -> Unit,
) {
    var cookie by remember { mutableStateOf("") }
    var interval by remember { mutableIntStateOf(initialInterval) }
    var maxCards by remember { mutableIntStateOf(initialMaxCards) }
    val clipboard = LocalClipboardManager.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = stringResource(R.string.config_title),
            style = MaterialTheme.typography.headlineSmall,
        )

        OutlinedTextField(
            value = cookie,
            onValueChange = { cookie = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.config_cookie_label)) },
            placeholder = {
                if (hasCookie) Text(stringResource(R.string.config_cookie_saved_placeholder))
            },
            minLines = 3,
            maxLines = 6,
            textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp),
        )
        OutlinedButton(onClick = { clipboard.getText()?.text?.let { cookie = it } }) {
            Text(stringResource(R.string.config_paste))
        }
        Text(
            text = stringResource(R.string.config_cookie_help),
            style = MaterialTheme.typography.bodySmall,
        )

        Text(
            text = stringResource(R.string.config_interval_label),
            style = MaterialTheme.typography.titleMedium,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            intervalOptions.forEach { (minutes, label) ->
                if (interval == minutes) {
                    Button(onClick = {}) { Text(label) }
                } else {
                    OutlinedButton(onClick = { interval = minutes }) { Text(label) }
                }
            }
        }

        Text(
            text = stringResource(R.string.config_max_cards_label, maxCards),
            style = MaterialTheme.typography.titleMedium,
        )
        Slider(
            value = maxCards.toFloat(),
            onValueChange = { maxCards = it.toInt() },
            valueRange = 5f..20f,
            steps = 14,
        )

        Spacer(Modifier.height(8.dp))
        Button(
            onClick = { onSave(cookie.trim(), interval, maxCards) },
            modifier = Modifier.fillMaxWidth(),
            enabled = hasCookie || cookie.isNotBlank(),
        ) {
            Text(stringResource(R.string.config_save))
        }
    }
}
