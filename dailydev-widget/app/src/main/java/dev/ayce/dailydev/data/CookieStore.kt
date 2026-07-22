package dev.ayce.dailydev.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Le cookie de session (da2/da3) est un identifiant porteur : stocké chiffré via
 * Keystore. Migration possible plus tard vers DataStore + Keystore manuel si
 * security-crypto est retiré.
 */
object CookieStore {
    private const val PREFS_NAME = "secure_prefs"
    private const val KEY_COOKIE = "cookie"

    private fun prefs(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun get(context: Context): String? = prefs(context).getString(KEY_COOKIE, null)

    fun set(context: Context, cookie: String) {
        prefs(context).edit().putString(KEY_COOKIE, cookie.trim()).apply()
    }

    fun isConfigured(context: Context): Boolean = !get(context).isNullOrBlank()
}
