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

    private const val RANKING = "POPULARITY"

    // « For you » : ne pas envoyer version ni ranking (le serveur applique ses
    // défauts : version 20, générateur de recommandation). Les supportedTypes
    // doivent être en MINUSCULES ("article", pas "Article") — sinon le générateur
    // ne matche aucun type et renvoie une page vide (confirmé en testant l'API).
    val OPERATION = """
        query FeedV2(${'$'}first: Int, ${'$'}after: String, ${'$'}supportedTypes: [String!] = ["article","share","freeform","video:youtube","collection","poll","social:twitter","live:room"]) {
          page: feedV2(first: ${'$'}first, after: ${'$'}after, supportedTypes: ${'$'}supportedTypes) {
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
                    contentHtml
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
                }
                // feedV2 : aucune variable de plus, supportedTypes a un défaut.
            }
        }
        return body.toString()
    }
}
