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

    // « For you » : la webapp n'envoie PAS de ranking à feedV2 (le service ML
    // choisit), mais passe columns, highlightsLimit et les types dont "highlight".
    val OPERATION = """
        query FeedV2(${'$'}first: Int, ${'$'}after: String, ${'$'}version: Int, ${'$'}columns: Int, ${'$'}highlightsLimit: Int, ${'$'}supportedTypes: [String!] = ["Article","Share","Freeform","SocialTwitter","VideoYouTube","Collection","Poll","LiveRoom","highlight"]) {
          page: feedV2(first: ${'$'}first, after: ${'$'}after, version: ${'$'}version, columns: ${'$'}columns, highlightsLimit: ${'$'}highlightsLimit, supportedTypes: ${'$'}supportedTypes) {
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

    // Fallback : query feed classique (structure à plat), utilisée si feedV2 est
    // vide. Personnalisée (feed logged-in) et triée par popularité.
    val LEGACY_OPERATION = """
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

    val STREAK_OPERATION = """
        query UserStreak {
          userStreak {
            current
          }
        }
    """.trimIndent()

    fun buildStreakBody(): String = buildJsonObject {
        put("query", STREAK_OPERATION)
    }.toString()

    fun buildBody(first: Int, after: String? = null, legacy: Boolean = false): String {
        val body = buildJsonObject {
            put("query", if (legacy) LEGACY_OPERATION else OPERATION)
            putJsonObject("variables") {
                put("first", first)
                after?.let { put("after", it) }
                if (legacy) {
                    // POPULARITY : plus proche des recommandations que le tri
                    // chronologique quand le fallback prend le relais.
                    put("ranking", RANKING)
                    put("version", 1)
                } else {
                    put("version", FEED_VERSION)
                    put("columns", 1)
                    put("highlightsLimit", 5)
                }
            }
        }
        return body.toString()
    }
}
