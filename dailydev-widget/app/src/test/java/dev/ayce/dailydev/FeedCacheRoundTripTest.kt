package dev.ayce.dailydev

import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.data.model.FeedStateJson
import dev.ayce.dailydev.data.model.Post
import org.junit.Assert.assertEquals
import org.junit.Test

class FeedCacheRoundTripTest {

    @Test
    fun `un FeedState survit a un aller-retour JSON`() {
        val state = FeedState(
            status = FeedState.Status.OK,
            posts = listOf(
                Post(
                    id = "p1",
                    title = "Titre",
                    url = "https://app.daily.dev/posts/p1",
                    commentsUrl = "https://app.daily.dev/posts/p1#c",
                    sourceName = "Vuejs&Nuxtjs",
                    upvotes = 54,
                    comments = 6,
                    readTimeMinutes = 5,
                    createdAt = "2026-07-20T10:00:00.000Z",
                    imageUrl = "https://img.example/p1.png",
                    imageFile = "/data/thumbs/abc.jpg",
                ),
            ),
            fetchedAtEpochMs = 1_753_000_000_000,
            endCursor = "cursor123",
        )

        val decoded = FeedStateJson.decode(FeedStateJson.encode(state))
        assertEquals(state, decoded)
    }

    @Test
    fun `un JSON corrompu retombe sur null`() {
        assertEquals(null, FeedStateJson.decode("{not json"))
    }

    @Test
    fun `un statut inconnu ne crashe pas grace au defaut`() {
        // coerceInputValues remplace l'enum inconnu par la valeur par défaut.
        val decoded = FeedStateJson.decode(
            """{"status":"SOMETHING_NEW","posts":[],"fetchedAtEpochMs":0}"""
        )
        assertEquals(FeedState.Status.NOT_CONFIGURED, decoded?.status)
    }
}
