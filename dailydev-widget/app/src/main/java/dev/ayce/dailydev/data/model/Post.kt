package dev.ayce.dailydev.data.model

import kotlinx.serialization.Serializable

/**
 * Article du feed, aplati pour le rendu widget. Les chemins de fichiers pointent
 * vers des vignettes déjà téléchargées et réduites (Glance ne charge pas d'URL).
 */
@Serializable
data class Post(
    val id: String,
    val title: String,
    val url: String,
    val commentsUrl: String? = null,
    val sourceName: String? = null,
    val upvotes: Int = 0,
    val comments: Int = 0,
    val readTimeMinutes: Int? = null,
    val createdAt: String? = null,
    val imageUrl: String? = null,
    val sourceLogoUrl: String? = null,
    val imageFile: String? = null,
    val sourceLogoFile: String? = null,
)
