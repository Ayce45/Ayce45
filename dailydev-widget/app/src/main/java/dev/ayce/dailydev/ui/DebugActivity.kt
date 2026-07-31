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
        val cookie = runCatching { CookieStore.get(this) }.getOrNull()
        val cookieNames = cookie.orEmpty()
            .split(';')
            .map { it.substringBefore('=').trim() }
            .filter { it.isNotBlank() }
        val dateFormat = SimpleDateFormat("dd/MM/yyyy HH:mm:ss", Locale.FRENCH)

        return buildString {
            appendLine("=== RAPPORT DEBUG daily.dev Widget ===")
            appendLine("Version app : ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            appendLine("Android : ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT}) · ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("Généré : ${dateFormat.format(Date())}")
            appendLine()
            appendLine("--- État du feed ---")
            appendLine("Statut : ${feedState.status}")
            appendLine("Source de la requête : ${feedState.feedSource ?: "-"}")
            appendLine("Articles en cache : ${feedState.posts.size}")
            appendLine("Dernier fetch : ${if (feedState.fetchedAtEpochMs > 0) dateFormat.format(Date(feedState.fetchedAtEpochMs)) else "-"}")
            appendLine("Curseur suite : ${feedState.endCursor?.take(30) ?: "aucun"}")
            appendLine("Chargement en cours : ${feedState.loadingMore}")
            appendLine("Streak : ${feedState.streak ?: "-"}")
            appendLine("Dernière erreur : ${feedState.lastError ?: "aucune"}")
            appendLine()
            appendLine("--- 5 premiers articles ---")
            feedState.posts.take(5).forEachIndexed { index, post ->
                appendLine("${index + 1}. [${post.sourceName ?: "?"}] ${post.title.take(60)} (▲${post.upvotes} 💬${post.comments})")
            }
            if (feedState.posts.isEmpty()) appendLine("(aucun)")
            appendLine()
            appendLine("--- Session ---")
            appendLine("Cookie présent : ${!cookie.isNullOrBlank()} (${cookie?.length ?: 0} caractères)")
            appendLine("Cookies : ${cookieNames.joinToString(", ").ifBlank { "-" }}")
            appendLine()
            appendLine("--- Réglages ---")
            appendLine("Intervalle : $interval min · Articles par chargement : $maxCards")
            appendLine()
            appendLine("--- Journal des appels API ---")
            appendLine(DebugLog.read(this@DebugActivity))
            if (includeSession) {
                appendLine()
                appendLine("--- SESSION (SENSIBLE — ne partager que pour debug) ---")
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
