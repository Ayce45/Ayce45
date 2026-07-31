package dev.ayce.dailydev.data

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Journal circulaire sur disque, alimenté par l'API et le repository, affiché
 * dans l'écran de debug pour diagnostiquer sans adb (rapport copiable).
 */
object DebugLog {
    private const val FILE_NAME = "debug_log.txt"
    private const val MAX_LINES = 150

    @Volatile
    private var appContext: Context? = null

    fun install(context: Context) {
        appContext = context.applicationContext
    }

    @Synchronized
    fun log(message: String) {
        val context = appContext ?: return
        runCatching {
            val file = File(context.filesDir, FILE_NAME)
            val stamp = SimpleDateFormat("dd/MM HH:mm:ss", Locale.FRENCH).format(Date())
            val lines = (readLines(file) + "[$stamp] $message").takeLast(MAX_LINES)
            file.writeText(lines.joinToString("\n"))
        }
    }

    fun read(context: Context): String {
        val file = File(context.filesDir, FILE_NAME)
        val content = runCatching { file.readText() }.getOrDefault("")
        return content.ifBlank { "(journal vide)" }
    }

    fun clear(context: Context) {
        File(context.filesDir, FILE_NAME).delete()
    }

    private fun readLines(file: File): List<String> =
        runCatching { file.readLines() }.getOrDefault(emptyList())
}
