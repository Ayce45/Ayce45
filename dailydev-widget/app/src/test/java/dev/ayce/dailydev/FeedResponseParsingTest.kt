package dev.ayce.dailydev

import dev.ayce.dailydev.data.api.AuthException
import dev.ayce.dailydev.data.api.DailyDevApi
import dev.ayce.dailydev.data.model.toPost
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class FeedResponseParsingTest {

    private fun fixture(name: String): String =
        checkNotNull(javaClass.classLoader?.getResourceAsStream(name)) { "fixture $name introuvable" }
            .bufferedReader().readText()

    @Test
    fun `parse une reponse feed complete`() {
        val page = DailyDevApi.parseFeed(fixture("feed_response_sample.json"))
        assertEquals(2, page.nodes.size)
        assertEquals("cursor123", page.endCursor)

        val first = page.nodes.first()
        assertEquals("p1", first.id)
        assertEquals("Why I Use a Hybrid Folder Structure", first.title)
        assertEquals(54, first.numUpvotes)
        assertEquals(6, first.numComments)
        assertEquals("Vuejs&Nuxtjs", first.source?.name)
    }

    @Test
    fun `mappe les nodes vers le domaine en ignorant les invalides`() {
        val page = DailyDevApi.parseFeed(fixture("feed_response_sample.json"))
        val posts = page.nodes.mapNotNull { it.toPost() }

        // Le second node n'a pas de permalink : écarté.
        assertEquals(1, posts.size)
        val post = posts.first()
        assertEquals("p1", post.id)
        assertEquals("https://app.daily.dev/posts/p1", post.url)
        assertEquals(54, post.upvotes)
        assertNotNull(post.imageUrl)
        assertNull(post.imageFile)
    }

    @Test
    fun `les champs inconnus sont ignores et endCursor absent donne null`() {
        val raw = """
            {"data":{"page":{"edges":[
              {"node":{"id":"x","title":"T","permalink":"https://x","futureField":42}}
            ],"pageInfo":{"hasNextPage":true}}}}
        """.trimIndent()
        val page = DailyDevApi.parseFeed(raw)
        assertEquals(1, page.nodes.size)
        assertNull(page.endCursor)
    }

    @Test
    fun `hasNextPage false donne un endCursor null meme si fourni`() {
        val raw = """
            {"data":{"page":{"edges":[],"pageInfo":{"hasNextPage":false,"endCursor":"c9"}}}}
        """.trimIndent()
        assertNull(DailyDevApi.parseFeed(raw).endCursor)
    }

    @Test
    fun `erreur UNAUTHENTICATED leve AuthException`() {
        val raw = """
            {"errors":[{"message":"unauthenticated","extensions":{"code":"UNAUTHENTICATED"}}],"data":null}
        """.trimIndent()
        assertThrows(AuthException::class.java) { DailyDevApi.parseFeed(raw) }
    }

    @Test
    fun `erreur GraphQL generique leve IOException avec le message serveur`() {
        val raw = """
            {"errors":[{"message":"Unknown argument \"version\""}],"data":null}
        """.trimIndent()
        val error = assertThrows(IOException::class.java) { DailyDevApi.parseFeed(raw) }
        assertTrue(error.message!!.contains("version"))
    }

    @Test
    fun `reponse illisible leve IOException`() {
        assertThrows(IOException::class.java) { DailyDevApi.parseFeed("<html>WAF block</html>") }
    }
}
