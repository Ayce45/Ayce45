package dev.ayce.dailydev.data.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Envelope persisted to disk. On error, `posts` keeps the last successful content
 * so the widget shows stale content rather than nothing.
 */
@Serializable
data class FeedState(
    val status: Status = Status.NOT_CONFIGURED,
    val posts: List<Post> = emptyList(),
    val fetchedAtEpochMs: Long = 0L,
    val endCursor: String? = null,
    val loadingMore: Boolean = false,
    // Diagnostics shown in the debug screen.
    val feedSource: String? = null,
    val lastError: String? = null,
    // daily.dev reading streak (🔥), null if unavailable.
    val streak: Int? = null,
    // True when the streak hasn't been kept today yet (nothing read today).
    val streakAtRisk: Boolean = false,
) {
    enum class Status { OK, AUTH_ERROR, NETWORK_ERROR, NOT_CONFIGURED }
}

object FeedStateJson {
    val json: Json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        encodeDefaults = true
    }

    fun encode(state: FeedState): String = json.encodeToString(FeedState.serializer(), state)

    fun decode(raw: String): FeedState? =
        runCatching { json.decodeFromString(FeedState.serializer(), raw) }.getOrNull()
}
