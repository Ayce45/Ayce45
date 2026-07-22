package dev.ayce.dailydev.ui

import android.annotation.SuppressLint
import android.os.Bundle
import android.os.Message
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Connexion intégrée : l'utilisateur se connecte à app.daily.dev dans une WebView,
 * puis le cookie de session (y compris HttpOnly da2/da3, que CookieManager expose
 * contrairement à document.cookie) est capturé et validé automatiquement.
 *
 * Les logins OAuth (GitHub…) s'ouvrent via window.open() : sans support
 * multi-fenêtres la WebView affiche une page blanche, d'où la WebView popup
 * empilée dans le FrameLayout via onCreateWindow.
 *
 * daily.dev pose aussi un cookie da2 aux visiteurs anonymes : la capture n'est
 * validée qu'après un appel feed réussi, preuve que la session est authentifiée.
 */
class LoginActivity : ComponentActivity() {

    private companion object {
        const val LOGIN_URL = "https://app.daily.dev/onboarding"
        const val COOKIE_POLL_MS = 2_000L
    }

    private lateinit var container: FrameLayout
    private lateinit var webView: WebView
    private var popupWebView: WebView? = null
    private val validating = AtomicBoolean(false)
    private var captured = false

    private val captureClient = object : WebViewClient() {
        override fun onPageFinished(view: WebView?, url: String?) {
            maybeCaptureCookie()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        container = FrameLayout(this)
        webView = WebView(this)
        container.addView(
            webView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(container)

        configureWebView(webView)
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message,
            ): Boolean {
                closePopup()
                val popup = WebView(this@LoginActivity)
                configureWebView(popup)
                popup.webChromeClient = object : WebChromeClient() {
                    override fun onCloseWindow(window: WebView) {
                        closePopup()
                    }
                }
                popupWebView = popup
                container.addView(
                    popup,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
                (resultMsg.obj as WebView.WebViewTransport).webView = popup
                resultMsg.sendToTarget()
                return true
            }
        }

        onBackPressedDispatcher.addCallback(this) {
            when {
                popupWebView != null -> closePopup()
                webView.canGoBack() -> webView.goBack()
                else -> {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        }

        webView.loadUrl(LOGIN_URL)

        // Après l'OAuth en popup, la page principale se met à jour en JS sans
        // navigation : onPageFinished ne suffit pas, on sonde aussi les cookies.
        lifecycleScope.launch {
            while (isActive && !captured) {
                maybeCaptureCookie()
                delay(COOKIE_POLL_MS)
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(view: WebView) {
        with(view.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(true)
            // Certains fournisseurs OAuth rejettent l'UA WebView explicite.
            userAgentString = userAgentString.replace("; wv", "")
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)
        view.webViewClient = captureClient
    }

    private fun closePopup() {
        popupWebView?.let {
            container.removeView(it)
            it.destroy()
        }
        popupWebView = null
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
        closePopup()
        webView.destroy()
        super.onDestroy()
    }
}
