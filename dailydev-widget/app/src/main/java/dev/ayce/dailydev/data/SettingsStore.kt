package dev.ayce.dailydev.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dev.ayce.dailydev.data.model.FeedType
import kotlinx.coroutines.flow.first

private val Context.settingsDataStore by preferencesDataStore(name = "settings")

object SettingsStore {
    const val DEFAULT_INTERVAL_MINUTES = 30
    const val DEFAULT_MAX_CARDS = 10

    // Browser preference sentinels (otherwise a concrete package name).
    const val BROWSER_DEFAULT = ""
    const val BROWSER_ASK = "ASK"

    private val KEY_INTERVAL = intPreferencesKey("refresh_interval_minutes")
    private val KEY_MAX_CARDS = intPreferencesKey("max_cards")
    private val KEY_FEED_TYPE = stringPreferencesKey("feed_type")
    private val KEY_BROWSER = stringPreferencesKey("browser_package")

    suspend fun refreshIntervalMinutes(context: Context): Int =
        context.settingsDataStore.data.first()[KEY_INTERVAL] ?: DEFAULT_INTERVAL_MINUTES

    suspend fun maxCards(context: Context): Int =
        context.settingsDataStore.data.first()[KEY_MAX_CARDS] ?: DEFAULT_MAX_CARDS

    suspend fun feedType(context: Context): FeedType =
        FeedType.from(context.settingsDataStore.data.first()[KEY_FEED_TYPE])

    /** "" = system default, "ASK" = show chooser, otherwise a package name. */
    suspend fun browserPackage(context: Context): String =
        context.settingsDataStore.data.first()[KEY_BROWSER] ?: BROWSER_DEFAULT

    suspend fun save(
        context: Context,
        intervalMinutes: Int,
        maxCards: Int,
        feedType: FeedType,
        browserPackage: String,
    ) {
        context.settingsDataStore.edit { prefs ->
            prefs[KEY_INTERVAL] = intervalMinutes
            prefs[KEY_MAX_CARDS] = maxCards
            prefs[KEY_FEED_TYPE] = feedType.id
            prefs[KEY_BROWSER] = browserPackage
        }
    }
}
