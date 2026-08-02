package dev.ayce.dailydev.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ayce.dailydev.BuildConfig
import dev.ayce.dailydev.R
import dev.ayce.dailydev.data.CookieStore
import dev.ayce.dailydev.data.DebugLog
import dev.ayce.dailydev.data.FeedCache
import dev.ayce.dailydev.data.SettingsStore
import dev.ayce.dailydev.work.RefreshScheduler
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.runBlocking

/**
 * Rapport de debug complet et copiable : état du feed, session, réglages et
 * journal des derniers appels API — à coller tel quel pour diagnostiquer.
 */
class DebugActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            DailyDevTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    var report by remember { mutableStateOf(buildReport()) }

                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = stringResource(R.string.debug_title),
                            style = MaterialTheme.typography.headlineSmall,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { copyToClipboard(report) }) {
                                Text(stringResource(R.string.debug_copy))
                            }
                            OutlinedButton(onClick = {
                                RefreshScheduler.refreshNow(this@DebugActivity)
                                Toast.makeText(
                                    this@DebugActivity,
                                    stringResource(R.string.debug_refresh_started),
                                    Toast.LENGTH_SHORT,
                                ).show()
                            }) {
                                Text(stringResource(R.string.debug_refresh))
                            }
                            OutlinedButton(onClick = {
                                DebugLog.clear(this@DebugActivity)
                                report = buildReport()
                            }) {
                                Text(stringResource(R.string.debug_clear))
                            }
                        }
                        OutlinedButton(
                            onClick = { copyToClipboard(buildReport(includeSession = true)) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(stringResource(R.string.debug_copy_session))
                        }
                        Text(
                            text = stringResource(R.string.debug_session_warning),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        SelectionContainer(
                            modifier = Modifier
                                .fillMaxWidth()
                                .verticalScroll(rememberScrollState()),
                        ) {
                            Text(
                                text = report,
                                style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 11.sp),
                            )
                        }
                    }
                }
            }
        }
    }

    private fun stringResource(id: Int): String = getString(id)

    private fun buildReport(includeSession: Boolean = false): String {
        val feedState = runBlocking { FeedCache.read(this@DebugActivity) }
        val interval = runBlocking { SettingsStore.refreshIntervalMinutes(this@DebugActivity) }
        val maxCards = runBlocking { SettingsStore.maxCards(this@DebugActivity) }
        val feedType = runBlocking { SettingsStore.feedType(this@DebugActivity) }
        val browser = runBlocking { SettingsStore.browserPackage(this@DebugActivity) }
        val cookie = runCatching { CookieStore.get(this) }.getOrNull()
        val cookieNames = cookie.orEmpty()
            .split(';')
            .map { it.substringBefore('=').trim() }
            .filter { it.isNotBlank() }
        val dateFormat = SimpleDateFormat("dd/MM/yyyy HH:mm:ss", Locale.ENGLISH)

        return buildString {
            appendLine("=== daily.dev Widget DEBUG REPORT ===")
            appendLine("App version: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            appendLine("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT}) · ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("Generated: ${dateFormat.format(Date())}")
            appendLine()
            appendLine("--- Feed state ---")
            appendLine("Status: ${feedState.status}")
            appendLine("Query source: ${feedState.feedSource ?: "-"}")
            appendLine("Cached articles: ${feedState.posts.size}")
            appendLine("Last fetch: ${if (feedState.fetchedAtEpochMs > 0) dateFormat.format(Date(feedState.fetchedAtEpochMs)) else "-"}")
            appendLine("Next cursor: ${feedState.endCursor?.take(30) ?: "none"}")
            appendLine("Loading more: ${feedState.loadingMore}")
            appendLine("Streak: ${feedState.streak ?: "-"} (at risk: ${feedState.streakAtRisk})")
            appendLine("Last error: ${feedState.lastError ?: "none"}")
            appendLine()
            appendLine("--- First 5 articles ---")
            feedState.posts.take(5).forEachIndexed { index, post ->
                appendLine("${index + 1}. [${post.sourceName ?: "?"}] ${post.title.take(60)} (▲${post.upvotes} 💬${post.comments})")
            }
            if (feedState.posts.isEmpty()) appendLine("(none)")
            appendLine()
            appendLine("--- Session ---")
            appendLine("Cookie present: ${!cookie.isNullOrBlank()} (${cookie?.length ?: 0} chars)")
            appendLine("Cookies: ${cookieNames.joinToString(", ").ifBlank { "-" }}")
            appendLine()
            appendLine("--- Settings ---")
            appendLine("Feed: ${feedType.label} · interval: $interval min · articles/load: $maxCards")
            appendLine("Browser: ${browser.ifBlank { "system default" }}")
            appendLine()
            appendLine("--- API call log ---")
            appendLine(DebugLog.read(this@DebugActivity))
            if (includeSession) {
                appendLine()
                appendLine("--- SESSION (SENSITIVE — only share for debugging) ---")
                appendLine("Cookie: ${cookie ?: "-"}")
            }
        }
    }

    private fun copyToClipboard(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("daily.dev widget debug", text))
        Toast.makeText(this, getString(R.string.debug_copied), Toast.LENGTH_SHORT).show()
    }
}
