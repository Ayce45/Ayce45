package dev.ayce.dailydev.data.api

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * Requête GraphQL du feed personnalisé, rétro-ingéniée depuis la webapp daily.dev.
 * C'est le point le plus susceptible de casser : si le serveur renvoie une erreur
 * de validation, capturer la vraie requête via DevTools (voir README) et la
 * resynchroniser ici.
 */
object FeedQuery {
    const val ENDPOINT = "https://api.daily.dev/graphql"

    // Version d'algorithme de feed envoyée par la webapp ; ajuster si besoin.
    private const val FEED_VERSION = 1
    private const val RANKING = "TIME"

    val OPERATION = """
        query Feed(${'$'}first: Int, ${'$'}after: String, ${'$'}ranking: Ranking, ${'$'}version: Int) {
          page: feed(first: ${'$'}first, after: ${'$'}after, ranking: ${'$'}ranking, version: ${'$'}version) {
            pageInfo {
              hasNextPage
              endCursor
            }
            edges {
              node {
                id
                title
                image
                permalink
                commentsPermalink
                createdAt
                readTime
                numUpvotes
                numComments
                source {
                  id
                  name
                  image
                }
              }
            }
          }
        }
    """.trimIndent()

    fun buildBody(first: Int, after: String? = null): String {
        val body = buildJsonObject {
            put("query", OPERATION)
            putJsonObject("variables") {
                put("first", first)
                after?.let { put("after", it) }
                put("ranking", RANKING)
                put("version", FEED_VERSION)
            }
        }
        return body.toString()
    }
}
