package dev.ayce.dailydev.data.model

import kotlinx.serialization.Serializable

@Serializable
data class GraphQlResponse(
    val data: FeedData? = null,
    val errors: List<GraphQlError>? = null,
)

@Serializable
data class GraphQlError(
    val message: String? = null,
    val extensions: GraphQlErrorExtensions? = null,
)

@Serializable
data class GraphQlErrorExtensions(
    val code: String? = null,
)

@Serializable
data class FeedData(
    val page: FeedConnection? = null,
)

@Serializable
data class FeedConnection(
    val edges: List<FeedEdge> = emptyList(),
    val pageInfo: PageInfo? = null,
)

@Serializable
data class PageInfo(
    val endCursor: String? = null,
    val hasNextPage: Boolean = false,
)

/** Une page de feed prête à consommer : nodes + curseur de pagination (null si fin). */
data class FeedPage(
    val nodes: List<PostNode>,
    val endCursor: String?,
)

@Serializable
data class FeedEdge(
    val node: FeedNode,
)

/**
 * Gère les deux formes de réponse : feedV2 imbrique l'article sous `post`, la
 * query feed classique met les champs directement sur le node.
 */
@Serializable
data class FeedNode(
    val post: PostNode? = null,
    val id: String? = null,
    val title: String? = null,
    val image: String? = null,
    val permalink: String? = null,
    val commentsPermalink: String? = null,
    val createdAt: String? = null,
    val readTime: Int? = null,
    val numUpvotes: Int? = null,
    val numComments: Int? = null,
    val source: SourceNode? = null,
) {
    fun resolve(): PostNode? = post ?: id?.let {
        PostNode(
            id = it,
            title = title,
            image = image,
            permalink = permalink,
            commentsPermalink = commentsPermalink,
            createdAt = createdAt,
            readTime = readTime,
            numUpvotes = numUpvotes,
            numComments = numComments,
            source = source,
        )
    }
}

@Serializable
data class PostNode(
    val id: String,
    val title: String? = null,
    val image: String? = null,
    val permalink: String? = null,
    val commentsPermalink: String? = null,
    val createdAt: String? = null,
    val readTime: Int? = null,
    val numUpvotes: Int? = null,
    val numComments: Int? = null,
    val source: SourceNode? = null,
)

@Serializable
data class SourceNode(
    val id: String? = null,
    val name: String? = null,
    val image: String? = null,
)

fun PostNode.toPost(): Post? {
    val postTitle = title?.trim().orEmpty()
    val url = permalink ?: return null
    if (postTitle.isEmpty()) return null
    return Post(
        id = id,
        title = postTitle,
        url = url,
        commentsUrl = commentsPermalink,
        sourceName = source?.name,
        upvotes = numUpvotes ?: 0,
        comments = numComments ?: 0,
        readTimeMinutes = readTime,
        createdAt = createdAt,
        imageUrl = image,
        sourceLogoUrl = source?.image,
    )
}
