import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// Application Connect IQ "Spotter for Technogym" : compagnon de seance Technogym.
// Au lancement : charge la seance en cache (Application.Storage), puis tente de la rafraichir
// depuis le backend. Le cache reste utilisable sans reseau.
class TgApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        Model.load();
    }

    function onStop(state as Dictionary?) as Void {
        Model.persistSession();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new HomeView(), new HomeDelegate()];
    }

    // Essai Connect IQ : pas de limite de duree (la limite est en seances, voir Model.sessionAllowed) ;
    // la boutique affiche sa page de deblocage pour les apps verrouillees.
    function getTrialDaysRemaining() as Number? {
        return null;
    }

    function onSettingsChanged() as Void {
        Model.reloadSettings();
        WatchUi.requestUpdate();
    }
}

function getApp() as TgApp {
    return Application.getApp() as TgApp;
}
