package dev.ayce.dailydev.data.api

import dev.ayce.dailydev.data.model.FeedType
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * daily.dev GraphQL operations, reverse-engineered from the web app. The single
 * most fragile point: if the server returns a validation error, capture the real
 * request in DevTools and re-sync here.
 */
object FeedQuery {
    const val ENDPOINT = "https://api.daily.dev/graphql"

    private const val RANKING = "POPULARITY"

    // Post types MUST be lowercase ("article", not "Article") — otherwise the feed
    // generator matches no type and returns an empty page (confirmed against the API).
    private const val SUPPORTED_TYPES =
        """["article","share","freeform","video:youtube","collection","poll","social:twitter","live:room"]"""

    private val POST_FIELDS = """
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
    """.trimIndent()

    // "For you": feedV2, article nested under node.post. No version/ranking so the
    // server applies its defaults (version 20, recommendation generator).
    private val FEEDV2_OPERATION = """
        query FeedV2(${'$'}first: Int, ${'$'}after: String, ${'$'}supportedTypes: [String!] = $SUPPORTED_TYPES) {
          page: feedV2(first: ${'$'}first, after: ${'$'}after, supportedTypes: ${'$'}supportedTypes) {
            pageInfo { hasNextPage endCursor }
            edges {
              node {
                __typename
                ... on FeedPostItem {
                  post { $POST_FIELDS }
                }
              }
            }
          }
        }
    """.trimIndent()

    // "Popular": classic feed, flat node, ranked by popularity. Also used as the
    // fallback when feedV2 returns empty.
    private val POPULAR_OPERATION = """
        query Feed(${'$'}first: Int, ${'$'}after: String, ${'$'}ranking: Ranking, ${'$'}version: Int) {
          page: feed(first: ${'$'}first, after: ${'$'}after, ranking: ${'$'}ranking, version: ${'$'}version) {
            pageInfo { hasNextPage endCursor }
            edges { node { $POST_FIELDS } }
          }
        }
    """.trimIndent()

    // "Bookmarks": the user's reading list, flat node.
    private val BOOKMARKS_OPERATION = """
        query BookmarksFeed(${'$'}first: Int, ${'$'}after: String, ${'$'}supportedTypes: [String!] = $SUPPORTED_TYPES) {
          page: bookmarksFeed(first: ${'$'}first, after: ${'$'}after, supportedTypes: ${'$'}supportedTypes) {
            pageInfo { hasNextPage endCursor }
            edges { node { $POST_FIELDS } }
          }
        }
    """.trimIndent()

    val STREAK_OPERATION = """
        query UserStreak {
          userStreak {
            current
            lastViewAt
          }
        }
    """.trimIndent()

    private val HIDE_OPERATION = """
        mutation HidePost(${'$'}id: ID!) {
          hidePost(id: ${'$'}id) {
            _
          }
        }
    """.trimIndent()

    fun buildStreakBody(): String = buildJsonObject {
        put("query", STREAK_OPERATION)
    }.toString()

    fun buildHideBody(postId: String): String = buildJsonObject {
        put("query", HIDE_OPERATION)
        putJsonObject("variables") { put("id", postId) }
    }.toString()

    /**
     * @param fallback forces the flat "popular" feed regardless of feedType — used
     *   when feedV2 comes back empty for the For You feed.
     */
    fun buildFeedBody(
        feedType: FeedType,
        first: Int,
        after: String? = null,
        fallback: Boolean = false,
    ): String {
        val usePopular = fallback || feedType == FeedType.POPULAR
        val query = when {
            feedType == FeedType.BOOKMARKS -> BOOKMARKS_OPERATION
            usePopular -> POPULAR_OPERATION
            else -> FEEDV2_OPERATION
        }
        val body = buildJsonObject {
            put("query", query)
            putJsonObject("variables") {
                put("first", first)
                after?.let { put("after", it) }
                if (usePopular) {
                    put("ranking", RANKING)
                    put("version", 1)
                }
            }
        }
        return body.toString()
    }
}
