package dev.ayce.dailydev.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

private val Context.settingsDataStore by preferencesDataStore(name = "settings")

object SettingsStore {
    const val DEFAULT_INTERVAL_MINUTES = 30
    const val DEFAULT_MAX_CARDS = 10

    private val KEY_INTERVAL = intPreferencesKey("refresh_interval_minutes")
    private val KEY_MAX_CARDS = intPreferencesKey("max_cards")

    suspend fun refreshIntervalMinutes(context: Context): Int =
        context.settingsDataStore.data.first()[KEY_INTERVAL] ?: DEFAULT_INTERVAL_MINUTES

    suspend fun maxCards(context: Context): Int =
        context.settingsDataStore.data.first()[KEY_MAX_CARDS] ?: DEFAULT_MAX_CARDS

    suspend fun save(context: Context, intervalMinutes: Int, maxCards: Int) {
        context.settingsDataStore.edit { prefs ->
            prefs[KEY_INTERVAL] = intervalMinutes
            prefs[KEY_MAX_CARDS] = maxCards
        }
    }
}
