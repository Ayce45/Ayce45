package dev.ayce.dailydev.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import dev.ayce.dailydev.data.api.DailyDevApi
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Vignettes pré-téléchargées et réduites : Glance ne charge pas d'URL, et
 * RemoteViews impose un budget mémoire bitmap global — d'où le downscale agressif.
 */
object ImageCache {
    const val THUMB_MAX_WIDTH = 320
    const val THUMB_MAX_HEIGHT = 180
    const val LOGO_MAX_SIZE = 96

    private fun dir(context: Context): File =
        File(context.filesDir, "thumbs").apply { mkdirs() }

    fun fileNameFor(url: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(url.toByteArray())
        return digest.joinToString("") { "%02x".format(it) } + ".jpg"
    }

    suspend fun fetch(context: Context, url: String, maxWidth: Int, maxHeight: Int): File? =
        withContext(Dispatchers.IO) {
            val target = File(dir(context), fileNameFor(url))
            if (target.exists() && target.length() > 0) return@withContext target

            val bytes = DailyDevApi.downloadBytes(url) ?: return@withContext null
            val bitmap = decodeScaled(bytes, maxWidth, maxHeight) ?: return@withContext null
            val tmp = File(target.parentFile, target.name + ".tmp")
            runCatching {
                FileOutputStream(tmp).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
                }
                tmp.renameTo(target)
            }
            bitmap.recycle()
            if (target.exists() && target.length() > 0) target else null
        }

    fun decodeFile(path: String): Bitmap? = runCatching { BitmapFactory.decodeFile(path) }.getOrNull()

    fun evictExcept(context: Context, keepFileNames: Set<String>) {
        dir(context).listFiles()?.forEach { file ->
            if (file.name !in keepFileNames) file.delete()
        }
    }

    private fun decodeScaled(bytes: ByteArray, maxWidth: Int, maxHeight: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (bounds.outWidth / (sampleSize * 2) >= maxWidth &&
            bounds.outHeight / (sampleSize * 2) >= maxHeight
        ) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }
}
