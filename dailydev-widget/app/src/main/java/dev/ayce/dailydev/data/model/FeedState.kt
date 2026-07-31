package dev.ayce.dailydev.data.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Enveloppe persistée sur disque. En cas d'erreur, `posts` conserve le dernier
 * contenu réussi pour que le widget affiche du contenu périmé plutôt que rien.
 */
@Serializable
data class FeedState(
    val status: Status = Status.NOT_CONFIGURED,
    val posts: List<Post> = emptyList(),
    val fetchedAtEpochMs: Long = 0L,
    val endCursor: String? = null,
    val loadingMore: Boolean = false,
    // Diagnostic affiché dans l'écran de configuration.
    val feedSource: String? = null,
    val lastError: String? = null,
    // Streak de lecture daily.dev (🔥), null si indisponible.
    val streak: Int? = null,
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
