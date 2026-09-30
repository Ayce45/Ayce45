import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.System;

// Ecran live : ou j'en suis dans la seance geree depuis la salle, frequence cardiaque, chrono.
//   UP / DOWN : parcourir les exercices (le courant est repris automatiquement au prochain evenement)
//   START     : menu (terminer et sauver l'activite, mode guide, actualiser)
//   BACK      : quitter l'ecran (l'activite continue en arriere-plan de l'app tant qu'elle tourne)
class LiveView extends WatchUi.View {

    const POLL_S = 10;       // interrogation du backend (lui-meme en cache 15 s sur Technogym)
    const HR_FLUSH_S = 30;   // envoi des echantillons cardio

    var timer as Timer.Timer? = null;
    var tick as Number = 0;
    var cursor as Number = -1;     // -1 = suivre l'exercice courant
    var status as String = "";
    var flash as Number = 0;       // secondes restantes de surbrillance d'un evenement

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        if (timer == null) {
            timer = new Timer.Timer();
            (timer as Timer.Timer).start(method(:onTick), 1000, true);
        }
        poll();
    }

    function onHide() as Void {
        if (timer != null) {
            (timer as Timer.Timer).stop();
            timer = null;
        }
    }

    function onTick() as Void {
        tick++;
        Live.sampleHr();
        if (flash > 0) { flash--; }
        if (tick % POLL_S == 0) { poll(); }
        if (tick % HR_FLUSH_S == 0) { Live.flushHr(); }
        WatchUi.requestUpdate();
    }

    function poll() as Void {
        if (!Net.configured()) {
            status = WatchUi.loadResource(Rez.Strings.NoToken) as String;
            return;
        }
        if (Net.fetchCurrent(method(:onLive))) {
            if (Live.state == null) { status = WatchUi.loadResource(Rez.Strings.Loading) as String; }
        }
    }

    function onLive(ok as Boolean, events as Number) as Void {
        if (ok) {
            status = "";
            if (events != 0) {
                flash = 6;
                cursor = -1;
                Recording.vibrate(events > 0);
            }
        } else {
            status = Live.lastError;
        }
        WatchUi.requestUpdate();
    }

    function shownIndex() as Number {
        return cursor >= 0 ? cursor : Live.currentIndex();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var xt = dc.getFontHeight(Graphics.FONT_XTINY);

        // bandeau haut (etroit sur ecran rond) : chrono + numero de l'exercice affiche
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var head = Ui.fmtClock(Live.elapsedSeconds());
        if (Live.hasSession()) { head += "   " + (shownIndex() + 1) + "/" + Live.exercises().size(); }
        dc.drawText(cx, h * 0.06, Graphics.FONT_XTINY, head, Graphics.TEXT_JUSTIFY_CENTER);

        // ligne du bas : evenement / erreur, sinon exercice suivant
        var footer = "";
        var footerColor = Graphics.COLOR_DK_GRAY;
        if (status.length() > 0) {
            footer = status;
            footerColor = Graphics.COLOR_YELLOW;
        } else if (flash > 0 && Live.lastEvent.length() > 0) {
            footer = Live.lastEvent;
            footerColor = Graphics.COLOR_YELLOW;
        }

        if (!Live.hasSession()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.20, w * 0.80, Graphics.FONT_SMALL, WatchUi.loadResource(Rez.Strings.NoLiveSession) as String, 3);
        } else {
            var i = shownIndex();
            var ex = Live.exerciseAt(i);
            var exs = Live.exercises();
            // statut de l'exercice (vocabulaire Technogym)
            var stColor = Live.isDone(ex) ? Graphics.COLOR_GREEN : (Live.status(ex).equals("doing") ? Graphics.COLOR_ORANGE : Graphics.COLOR_LT_GRAY);
            dc.setColor(stColor, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.14, w * 0.66, Graphics.FONT_XTINY, Live.sourceText(ex), 1);
            // nom (2 lignes max)
            dc.setColor(flash > 0 && cursor < 0 ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var y = h * 0.22;
            var used = Ui.drawWrapped(dc, cx, y, w * 0.86, Graphics.FONT_SMALL, Live.title(ex), 2);
            y += used;
            // machine (seulement si le nom tient sur une ligne)
            var eq = Live.equipment(ex);
            if (used <= dc.getFontHeight(Graphics.FONT_SMALL) && eq.length() > 0 && !eq.equals(Live.title(ex))) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                Ui.drawWrapped(dc, cx, y, w * 0.86, Graphics.FONT_XTINY, eq, 1);
                y += xt;
            }
            // series (faites si l'exercice est fait, sinon prescrites)
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, y, w * 0.86, Graphics.FONT_SMALL, Live.setsText(ex), 1);
            // progression de la seance + MOVEs
            var prog = Live.doneCount() + "/" + Live.totalCount() + " " + (WatchUi.loadResource(Rez.Strings.DoneShort) as String);
            var mv = Live.movesDone();
            if (mv > 0) { prog += "   " + mv + " " + (WatchUi.loadResource(Rez.Strings.Moves) as String); }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.585, w * 0.90, Graphics.FONT_XTINY, prog, 1);
            // suivant
            if (footer.length() == 0) {
                for (var k = i + 1; k < exs.size(); k++) {
                    if (!Live.isDone(exs[k] as Dictionary)) { footer = (WatchUi.loadResource(Rez.Strings.NextExercise) as String) + Live.title(exs[k] as Dictionary); break; }
                }
                if (footer.length() == 0 && Live.totalCount() > 0 && Live.doneCount() >= Live.totalCount()) { footer = WatchUi.loadResource(Rez.Strings.SessionDone) as String; }
            }
            Ui.drawProgressArc(dc, Live.totalCount() > 0 ? Live.doneCount().toFloat() / Live.totalCount() : 0.0, Graphics.COLOR_GREEN);
        }
        drawHr(dc, cx, h * 0.74, w, h);
        if (footer.length() > 0) {
            dc.setColor(footerColor, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.84, w * 0.68, Graphics.FONT_XTINY, footer, 1);
        }
    }

    function drawHr(dc as Dc, cx as Number, y as Numeric, w as Number, h as Number) as Void {
        var hr = Live.hr;
        var txt = (hr == null) ? "--" : (hr as Number).toString();
        var f = Graphics.FONT_NUMBER_MEDIUM;
        var tw = dc.getTextWidthInPixels(txt, f);
        var uw = dc.getTextWidthInPixels(" bpm", Graphics.FONT_XTINY);
        var x0 = cx - (tw + uw) / 2;
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, y, f, txt, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(x0 + tw, y, Graphics.FONT_XTINY, " bpm", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (Live.hrMax > 0 && w >= 360) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0 - 8, y, Graphics.FONT_XTINY, "max " + Live.hrMax, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}

class LiveDelegate extends WatchUi.BehaviorDelegate {

    var view as LiveView;

    function initialize(v as LiveView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onNextPage() as Boolean {
        var n = Live.exercises().size();
        if (n == 0) { return false; }
        view.cursor = (view.shownIndex() + 1) % n;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        var n = Live.exercises().size();
        if (n == 0) { return false; }
        view.cursor = (view.shownIndex() + n - 1) % n;
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        var menu = new WatchUi.Menu2({ :title => Live.hasSession() ? Live.sessionName() : (WatchUi.loadResource(Rez.Strings.ShortName) as String) });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Refresh) as String, null, :refresh, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.FollowCurrent) as String, null, :follow, null));
        if (Model.hasWorkout()) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.GuidedMode) as String, WatchUi.loadResource(Rez.Strings.GuidedModeHint) as String, :guided, null));
        }
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.FinishLive) as String, Live.hrAvg() > 0 ? "FC moyenne " + Live.hrAvg() + " bpm" : null, :finish, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Discard) as String, null, :discard, null));
        WatchUi.pushView(menu, new LiveMenuDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        // l'activite continue ; l'ecran d'accueil propose de la reprendre
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

class LiveMenuDelegate extends WatchUi.Menu2InputDelegate {

    var view as LiveView;

    function initialize(v as LiveView) {
        Menu2InputDelegate.initialize();
        view = v;
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :refresh) {
            view.poll();
        } else if (id == :follow) {
            view.cursor = -1;
        } else if (id == :guided) {
            if (!Model.inProgress) { Model.startSession(); }
            Net.fetchLive(null);
            Flow.showCurrent(WatchUi.SLIDE_LEFT, true);
        } else if (id == :finish) {
            Live.flushHr();
            var saved = Recording.save();
            Model.liveMode = false;
            Model.startedAt = 0;
            view.status = saved ? (WatchUi.loadResource(Rez.Strings.Saved) as String) : "Aucune activité à enregistrer";
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (id == :discard) {
            Recording.discard();
            Model.liveMode = false;
            Model.startedAt = 0;
            Live.reset();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        WatchUi.requestUpdate();
    }
}
