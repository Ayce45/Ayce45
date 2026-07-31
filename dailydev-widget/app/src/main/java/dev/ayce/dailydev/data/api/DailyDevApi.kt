package dev.ayce.dailydev.data.api

import dev.ayce.dailydev.data.DebugLog
import dev.ayce.dailydev.data.model.FeedPage
import dev.ayce.dailydev.data.model.GraphQlResponse
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
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

    /**
     * Tente d'abord feedV2 (le vrai « For you ») ; s'il revient vide ou en erreur
     * réseau, retombe sur la query feed classique (flat) qui a fait ses preuves —
     * le widget n'est jamais vide tant qu'une des deux répond.
     */
    suspend fun fetchFeed(cookie: String, first: Int, after: String? = null): FeedPage =
        withContext(Dispatchers.IO) {
            val primary = try {
                postGraphQl(cookie, FeedQuery.buildBody(first, after, legacy = false), "feedV2")
            } catch (e: AuthException) {
                throw e // laisser le renouvellement de session gérer
            } catch (e: IOException) {
                DebugLog.log("feedV2 KO: ${e.message?.take(150)}")
                null
            }
            if (primary != null && primary.nodes.isNotEmpty()) {
                primary.copy(source = "feedV2")
            } else {
                if (primary != null) DebugLog.log("feedV2 vide → fallback feed")
                postGraphQl(cookie, FeedQuery.buildBody(first, after, legacy = true), "feed")
                    .copy(source = "feed")
            }
        }

    private fun postGraphQl(cookie: String, body: String, label: String): FeedPage {
        val request = Request.Builder()
            .url(FeedQuery.ENDPOINT)
            .header("Accept", "application/json")
            .header("Cookie", cookie)
            .header("Origin", "https://app.daily.dev")
            .header("Referer", "https://app.daily.dev/")
            .header("User-Agent", USER_AGENT)
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

        return client.newCall(request).execute().use { response ->
            if (response.code == 401 || response.code == 403) {
                DebugLog.log("$label HTTP ${response.code} (auth)")
                throw AuthException("HTTP ${response.code}")
            }
            if (!response.isSuccessful) {
                DebugLog.log("$label HTTP ${response.code}")
                throw IOException("HTTP ${response.code}")
            }
            val raw = response.body?.string() ?: throw IOException("Réponse vide")
            try {
                val page = parseFeed(raw)
                DebugLog.log(
                    "$label OK: ${page.nodes.size} posts, suite=${page.endCursor != null}, " +
                        "1er=« ${page.nodes.firstOrNull()?.title?.take(45) ?: "-"} »"
                )
                if (page.nodes.isEmpty()) {
                    DebugLog.log("$label corps vide: ${raw.take(400)}")
                }
                page
            } catch (e: Exception) {
                DebugLog.log("$label parse KO: ${e.message?.take(120)} — corps: ${raw.take(300)}")
                throw e
            }
        }
    }

    /** Streak de lecture (🔥) — best effort, null si la requête échoue. */
    suspend fun fetchStreak(cookie: String): Int? = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url(FeedQuery.ENDPOINT)
                .header("Accept", "application/json")
                .header("Cookie", cookie)
                .header("Origin", "https://app.daily.dev")
                .header("Referer", "https://app.daily.dev/")
                .header("User-Agent", USER_AGENT)
                .post(FeedQuery.buildStreakBody().toRequestBody("application/json".toMediaType()))
                .build()
            client.newCall(request).execute().use { response ->
                val raw = response.body?.string().orEmpty()
                // Navigation null-safe : data/userStreak/current peuvent être JsonNull.
                fun obj(e: Any?) = e as? JsonObject
                val root = obj(Json.parseToJsonElement(raw))
                val streak = (obj(root?.get("data"))?.get("userStreak"))
                    .let { obj(it) }?.get("current")
                    .let { it as? JsonPrimitive }?.intOrNull
                DebugLog.log("streak: ${streak ?: "indisponible (HTTP ${response.code})"}")
                streak
            }
        }.getOrElse {
            DebugLog.log("streak KO: ${it.message?.take(100)}")
            null
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
            nodes = page.edges.mapNotNull { it.node.resolve() },
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

    /**
     * Renouvelle la session comme la webapp : GET /boot avec les cookies actuels ;
     * le serveur régénère da2 (JWT court) grâce à da3 (longue durée) via Set-Cookie.
     * Retourne la chaîne de cookies fusionnée, ou null si rien n'a été renouvelé.
     */
    suspend fun renewSession(cookie: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url("https://api.daily.dev/boot")
                .header("Accept", "application/json")
                .header("Cookie", cookie)
                .header("Origin", "https://app.daily.dev")
                .header("Referer", "https://app.daily.dev/")
                .header("User-Agent", USER_AGENT)
                .build()
            client.newCall(request).execute().use { response ->
                val setCookies = response.headers("set-cookie")
                if (!response.isSuccessful || setCookies.isEmpty()) {
                    null
                } else {
                    mergeCookies(cookie, setCookies)
                }
            }
        }.getOrNull()
    }

    /** Fusion pure (testable en JVM) des en-têtes Set-Cookie dans la chaîne Cookie existante. */
    fun mergeCookies(existing: String, setCookies: List<String>): String {
        val jar = LinkedHashMap<String, String>()
        existing.split(';').forEach { part ->
            val trimmed = part.trim()
            val eq = trimmed.indexOf('=')
            if (eq > 0) jar[trimmed.substring(0, eq)] = trimmed.substring(eq + 1)
        }
        setCookies.forEach { header ->
            val pair = header.substringBefore(';').trim()
            val eq = pair.indexOf('=')
            if (eq > 0) jar[pair.substring(0, eq)] = pair.substring(eq + 1)
        }
        return jar.entries.joinToString("; ") { "${it.key}=${it.value}" }
    }
}
