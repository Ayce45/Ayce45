package dev.ayce.dailydev.data.model

/** Which daily.dev feed the widget shows. Stored by id in the settings. */
enum class FeedType(val id: String, val label: String) {
    FOR_YOU("FOR_YOU", "For you"),
    POPULAR("POPULAR", "Popular"),
    BOOKMARKS("BOOKMARKS", "Bookmarks");

    companion object {
        fun from(id: String?): FeedType = entries.firstOrNull { it.id == id } ?: FOR_YOU
    }
}
