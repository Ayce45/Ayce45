package dev.ayce.dailydev.data

import android.content.Context
import dev.ayce.dailydev.data.model.FeedState
import dev.ayce.dailydev.data.model.FeedStateJson
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Cache disque du feed : le widget rend toujours depuis ce fichier, jamais depuis le réseau. */
object FeedCache {
    private const val FILE_NAME = "feed_cache.json"

    private fun file(context: Context) = File(context.filesDir, FILE_NAME)

    suspend fun read(context: Context): FeedState = withContext(Dispatchers.IO) {
        val cacheFile = file(context)
        if (!cacheFile.exists()) return@withContext FeedState()
        runCatching { FeedStateJson.decode(cacheFile.readText()) }.getOrNull() ?: FeedState()
    }

    suspend fun write(context: Context, state: FeedState) = withContext(Dispatchers.IO) {
        val cacheFile = file(context)
        val tmp = File(cacheFile.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(FeedStateJson.encode(state))
        if (!tmp.renameTo(cacheFile)) {
            cacheFile.writeText(FeedStateJson.encode(state))
            tmp.delete()
        }
    }
}
