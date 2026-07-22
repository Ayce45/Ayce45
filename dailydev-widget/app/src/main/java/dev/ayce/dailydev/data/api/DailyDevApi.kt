package dev.ayce.dailydev.data.api

import dev.ayce.dailydev.data.model.FeedPage
import dev.ayce.dailydev.data.model.GraphQlResponse
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Cookie invalide ou expiré : réessayer ne sert à rien, l'utilisateur doit re-coller. */
class AuthException(message: String) : Exception(message)

object DailyDevApi {

    // En-têtes navigateur : l'endpoint est derrière un WAF qui rejette les clients
    // trop identifiables comme des bots.
    private const val USER_AGENT =
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/126.0.0.0 Safari/537.36"

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    suspend fun fetchFeed(cookie: String, first: Int, after: String? = null): FeedPage =
        withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url(FeedQuery.ENDPOINT)
                .header("Accept", "application/json")
                .header("Cookie", cookie)
                .header("Origin", "https://app.daily.dev")
                .header("Referer", "https://app.daily.dev/")
                .header("User-Agent", USER_AGENT)
                .post(FeedQuery.buildBody(first, after).toRequestBody("application/json".toMediaType()))
                .build()

            client.newCall(request).execute().use { response ->
                if (response.code == 401 || response.code == 403) {
                    throw AuthException("HTTP ${response.code}")
                }
                if (!response.isSuccessful) {
                    throw IOException("HTTP ${response.code}")
                }
                val raw = response.body?.string() ?: throw IOException("Réponse vide")
                parseFeed(raw)
            }
        }

    /** Séparé et sans dépendance Android pour être testable en JVM pure. */
    fun parseFeed(raw: String): FeedPage {
        val parsed = runCatching { json.decodeFromString(GraphQlResponse.serializer(), raw) }
            .getOrElse { throw IOException("Réponse GraphQL illisible", it) }
        val errors = parsed.errors.orEmpty()
        if (errors.any { it.extensions?.code == "UNAUTHENTICATED" || it.extensions?.code == "FORBIDDEN" }) {
            throw AuthException(errors.firstNotNullOfOrNull { it.message } ?: "Non authentifié")
        }
        val page = parsed.data?.page
            ?: throw IOException(errors.firstNotNullOfOrNull { it.message } ?: "Réponse sans données")
        return FeedPage(
            nodes = page.edges.map { it.node },
            endCursor = page.pageInfo?.takeIf { it.hasNextPage }?.endCursor,
        )
    }

    fun downloadBytes(url: String): ByteArray? = runCatching {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", USER_AGENT)
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return null
            response.body?.bytes()
        }
    }.getOrNull()
}
