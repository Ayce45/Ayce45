package dev.ayce.dailydev.ui

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.lifecycle.lifecycleScope
import dev.ayce.dailydev.R
import dev.ayce.dailydev.data.CookieStore
import dev.ayce.dailydev.data.api.AuthException
import dev.ayce.dailydev.data.api.DailyDevApi
import dev.ayce.dailydev.work.RefreshScheduler
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.launch

/**
 * Connexion intégrée : l'utilisateur se connecte à app.daily.dev dans une WebView,
 * puis le cookie de session (y compris HttpOnly da2/da3, que CookieManager expose
 * contrairement à document.cookie) est capturé et validé automatiquement.
 *
 * daily.dev pose aussi un cookie da2 aux visiteurs anonymes : la capture n'est
 * validée qu'après un appel feed réussi, preuve que la session est authentifiée.
 */
class LoginActivity : ComponentActivity() {

    private lateinit var webView: WebView
    private val validating = AtomicBoolean(false)
    private var captured = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this)
        setContentView(webView)

        with(webView.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            // Certains fournisseurs OAuth rejettent l'UA WebView explicite.
            userAgentString = userAgentString.replace("; wv", "")
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                maybeCaptureCookie()
            }
        }

        onBackPressedDispatcher.addCallback(this) {
            if (webView.canGoBack()) {
                webView.goBack()
            } else {
                isEnabled = false
                onBackPressedDispatcher.onBackPressed()
            }
        }

        webView.loadUrl("https://app.daily.dev/")
    }

    private fun maybeCaptureCookie() {
        if (captured || !validating.compareAndSet(false, true)) return

        val cookie = CookieManager.getInstance().getCookie("https://app.daily.dev")
        if (cookie.isNullOrBlank() || !cookie.contains("da2=")) {
            validating.set(false)
            return
        }

        lifecycleScope.launch {
            val loggedIn = try {
                DailyDevApi.fetchFeed(cookie, 1)
                true
            } catch (e: AuthException) {
                false
            } catch (e: Exception) {
                false
            }
            validating.set(false)
            if (loggedIn && !captured) {
                captured = true
                CookieStore.set(this@LoginActivity, cookie)
                CookieManager.getInstance().flush()
                RefreshScheduler.ensureScheduled(this@LoginActivity)
                RefreshScheduler.refreshNow(this@LoginActivity)
                Toast.makeText(
                    this@LoginActivity,
                    getString(R.string.login_success),
                    Toast.LENGTH_LONG,
                ).show()
                setResult(RESULT_OK)
                finish()
            }
        }
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }
}
