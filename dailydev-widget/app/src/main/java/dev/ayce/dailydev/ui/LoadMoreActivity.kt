package dev.ayce.dailydev.ui

import android.app.Activity
import android.os.Bundle
import dev.ayce.dailydev.appScope
import dev.ayce.dailydev.data.FeedRepository
import kotlinx.coroutines.launch

/**
 * Cible du bouton « Charger plus » du widget. Les clics actionRunCallback sont
 * peu fiables dans les listes RemoteViews selon les launchers ; lancer une
 * activité invisible (Theme.NoDisplay) emprunte le même chemin que le tap sur
 * une card, qui fonctionne partout.
 */
class LoadMoreActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appContext = applicationContext
        appScope.launch { FeedRepository.loadMore(appContext) }
        finish()
    }
}
