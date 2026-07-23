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

    // Feed personnalisé « For you » = opération FeedV2 (champ feedV2), version 15,
    // classement POPULARITY — valeurs de la webapp daily.dev (packages/shared feed.ts
    // + feature flag feed_version). L'article est imbriqué sous node.post.
    private const val FEED_VERSION = 15
    private const val RANKING = "POPULARITY"

    val OPERATION = """
        query FeedV2(${'$'}first: Int, ${'$'}after: String, ${'$'}ranking: Ranking, ${'$'}version: Int, ${'$'}supportedTypes: [String!] = ["Article","Share","Freeform","VideoYouTube","Collection"]) {
          page: feedV2(first: ${'$'}first, after: ${'$'}after, ranking: ${'$'}ranking, version: ${'$'}version, supportedTypes: ${'$'}supportedTypes) {
            pageInfo {
              hasNextPage
              endCursor
            }
            edges {
              node {
                __typename
                ... on FeedPostItem {
                  post {
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
