import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// Ecran d'accueil : seance du jour (nom, date, nb exercices), etat reseau, actions.
class HomeView extends WatchUi.View {

    var status as String = "";
    var fetching as Boolean = false;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        if (!Net.configured()) {
            status = WatchUi.loadResource(Rez.Strings.NoToken) as String;
        } else if (!fetching && !Model.inProgress) {
            refresh();
        }
    }

    function refresh() as Void {
        if (Net.fetchToday(method(:onFetched))) {
            fetching = true;
            status = WatchUi.loadResource(Rez.Strings.Loading) as String;
        }
        WatchUi.requestUpdate();
    }

    function onFetched(ok as Boolean, msg as String) as Void {
        fetching = false;
        if (ok) {
            status = "";
            if (Model.pendingCount() > 0) {
                Net.sendPending(method(:onPendingSent));
            }
        } else {
            status = Model.hasWorkout() ? (WatchUi.loadResource(Rez.Strings.Offline) as String) : msg;
        }
        WatchUi.requestUpdate();
    }

    function onPendingSent(ok as Boolean, msg as String) as Void {
        status = ok ? msg : (WatchUi.loadResource(Rez.Strings.SendFailed) as String);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.12, Graphics.FONT_SMALL, WatchUi.loadResource(Rez.Strings.AppName) as String, Graphics.TEXT_JUSTIFY_CENTER);

        if (Model.hasWorkout()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.28, w * 0.82, Graphics.FONT_MEDIUM, Model.workoutTitle(), 2);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.50, Graphics.FONT_XTINY, Model.workoutDate(), Graphics.TEXT_JUSTIFY_CENTER);
            var line = Model.exerciseCount() + " " + (WatchUi.loadResource(Rez.Strings.Exercises) as String).toLower();
            if (Model.inProgress) {
                line = "En cours : " + (Model.exIndex + 1) + "/" + Model.exerciseCount();
            }
            dc.drawText(cx, h * 0.58, Graphics.FONT_TINY, line, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.70, Graphics.FONT_SMALL, WatchUi.loadResource(Rez.Strings.Start) as String, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.40, Graphics.FONT_MEDIUM, WatchUi.loadResource(Rez.Strings.NoWorkout) as String, Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (status.length() > 0) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.80, w * 0.85, Graphics.FONT_XTINY, status, 2);
        }
        var pend = Model.pendingCount();
        if (pend > 0) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.92, Graphics.FONT_XTINY, pend + " en attente", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class HomeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        return startWorkout();
    }

    function onTap(evt as ClickEvent) as Boolean {
        return startWorkout();
    }

    function startWorkout() as Boolean {
        if (!Model.hasWorkout()) {
            return false;
        }
        if (!Model.inProgress) {
            Model.startSession();
            Recording.start(Model.workoutTitle());
        } else if (!Recording.isRecording() && Recording.session == null) {
            // reprise apres redemarrage de l'app : nouvelle activite FIT
            Recording.start(Model.workoutTitle());
        }
        Flow.showCurrent(WatchUi.SLIDE_LEFT, true);
        return true;
    }

    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.AppName) as String });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Refresh) as String, null, :refresh, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Exercises) as String, null, :list, null));
        if (Model.pendingCount() > 0) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.SendPending) as String, Model.pendingCount() + "", :send, null));
        }
        if (Model.inProgress) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Discard) as String, null, :discard, null));
        }
        WatchUi.pushView(menu, new HomeMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

class HomeMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :refresh) {
            Net.fetchToday(null);
        } else if (id == :list) {
            Flow.showExerciseList();
        } else if (id == :send) {
            Net.sendPending(null);
        } else if (id == :discard) {
            Recording.discard();
            Model.resetProgress();
        }
        WatchUi.requestUpdate();
    }
}
