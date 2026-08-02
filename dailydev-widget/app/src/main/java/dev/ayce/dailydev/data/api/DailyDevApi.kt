package dev.ayce.dailydev.data.api

import dev.ayce.dailydev.data.DebugLog
import dev.ayce.dailydev.data.model.FeedPage
import dev.ayce.dailydev.data.model.FeedType
import dev.ayce.dailydev.data.model.GraphQlResponse
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Invalid or expired cookie: retrying is pointless, the user must re-login. */
class AuthException(message: String) : Exception(message)

/** Reading streak: current count and the last time a post was read (ISO-8601). */
data class StreakInfo(val current: Int?, val lastViewAt: String?)

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
     * For You tries feedV2 first; if it comes back empty or with a network error it
     * falls back to the classic flat feed, so the widget is never empty as long as
     * one of them answers. Popular and Bookmarks use their own query directly.
     */
    suspend fun fetchFeed(
        cookie: String,
        first: Int,
        after: String? = null,
        feedType: FeedType = FeedType.FOR_YOU,
    ): FeedPage = withContext(Dispatchers.IO) {
        if (feedType != FeedType.FOR_YOU) {
            val label = feedType.id.lowercase()
            return@withContext postGraphQl(cookie, FeedQuery.buildFeedBody(feedType, first, after), label)
                .copy(source = label)
        }
        val primary = try {
            postGraphQl(cookie, FeedQuery.buildFeedBody(feedType, first, after), "feedV2")
        } catch (e: AuthException) {
            throw e // let session renewal handle it
        } catch (e: IOException) {
            DebugLog.log("feedV2 failed: ${e.message?.take(150)}")
            null
        }
        if (primary != null && primary.nodes.isNotEmpty()) {
            primary.copy(source = "feedV2")
        } else {
            if (primary != null) DebugLog.log("feedV2 empty -> fallback feed")
            postGraphQl(cookie, FeedQuery.buildFeedBody(feedType, first, after, fallback = true), "feed")
                .copy(source = "feed")
        }
    }

    /** Hides a post from the personalized feed (the "not interested" action). */
    suspend fun hidePost(cookie: String, postId: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val request = graphQlRequest(cookie, FeedQuery.buildHideBody(postId))
            client.newCall(request).execute().use { response ->
                DebugLog.log("hidePost $postId -> HTTP ${response.code}")
                response.isSuccessful
            }
        }.getOrElse {
            DebugLog.log("hidePost failed: ${it.message?.take(100)}")
            false
        }
    }

    private fun graphQlRequest(cookie: String, body: String): Request =
        Request.Builder()
            .url(FeedQuery.ENDPOINT)
            .header("Accept", "application/json")
            .header("Cookie", cookie)
            .header("Origin", "https://app.daily.dev")
            .header("Referer", "https://app.daily.dev/")
            .header("User-Agent", USER_AGENT)
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

    private fun postGraphQl(cookie: String, body: String, label: String): FeedPage {
        val request = graphQlRequest(cookie, body)

        return client.newCall(request).execute().use { response ->
            if (response.code == 401 || response.code == 403) {
                DebugLog.log("$label HTTP ${response.code} (auth)")
                throw AuthException("HTTP ${response.code}")
            }
            if (!response.isSuccessful) {
                DebugLog.log("$label HTTP ${response.code}")
                throw IOException("HTTP ${response.code}")
            }
            val raw = response.body?.string() ?: throw IOException("Empty response")
            try {
                val page = parseFeed(raw)
                DebugLog.log(
                    "$label OK: ${page.nodes.size} posts, more=${page.endCursor != null}, " +
                        "1st=\"${page.nodes.firstOrNull()?.title?.take(45) ?: "-"}\""
                )
                if (page.nodes.isEmpty()) {
                    DebugLog.log("$label empty body: ${raw.take(400)}")
                }
                page
            } catch (e: Exception) {
                DebugLog.log("$label parse failed: ${e.message?.take(120)} — body: ${raw.take(300)}")
                throw e
            }
        }
    }

    /** Reading streak (current + lastViewAt) — best effort, null on failure. */
    suspend fun fetchStreak(cookie: String): StreakInfo? = withContext(Dispatchers.IO) {
        runCatching {
            val request = graphQlRequest(cookie, FeedQuery.buildStreakBody())
            client.newCall(request).execute().use { response ->
                val raw = response.body?.string().orEmpty()
                // Null-safe navigation: data/userStreak fields may be JsonNull.
                fun obj(e: Any?) = e as? JsonObject
                val streakObj = obj(obj(Json.parseToJsonElement(raw))?.get("data"))
                    ?.get("userStreak").let { obj(it) }
                val current = (streakObj?.get("current") as? JsonPrimitive)?.intOrNull
                val lastViewAt = (streakObj?.get("lastViewAt") as? JsonPrimitive)?.contentOrNull
                DebugLog.log("streak: ${current ?: "unavailable (HTTP ${response.code})"}, lastViewAt=$lastViewAt")
                StreakInfo(current, lastViewAt)
            }
        }.getOrElse {
            DebugLog.log("streak failed: ${it.message?.take(100)}")
            null
        }
    }

    /** Séparé et sans dépendance Android pour être testable en JVM pure. */
    fun parseFeed(raw: String): FeedPage {
        val parsed = runCatching { json.decodeFromString(GraphQlResponse.serializer(), raw) }
            .getOrElse { throw IOException("Unreadable GraphQL response", it) }
        val errors = parsed.errors.orEmpty()
        if (errors.any { it.extensions?.code == "UNAUTHENTICATED" || it.extensions?.code == "FORBIDDEN" }) {
            throw AuthException(errors.firstNotNullOfOrNull { it.message } ?: "Not authenticated")
        }
        val page = parsed.data?.page
            ?: throw IOException(errors.firstNotNullOfOrNull { it.message } ?: "Response without data")
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
