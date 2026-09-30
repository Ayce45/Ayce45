import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.System;

// Ecran live organise comme une activite Garmin : plusieurs pages de donnees, UP / DOWN pour changer
// de page, START pour la liste des exercices, appui long UP pour le menu, BACK pour sortir.
//   page 0  Exercice : progression, exercice en cours (icone d'etat), series, FC
//   page 1  Cardio   : FC en grand coloree par zone, jauge de zones, moyenne, max
//   page 2  Seance   : grille 4 champs (duree, exercices, MOVEs, kcal)
class LiveView extends WatchUi.View {

    const POLL_S = 10;       // interrogation du backend (lui-meme en cache 15 s sur Technogym)
    const HR_FLUSH_S = 30;   // envoi des echantillons cardio
    const PAGES = 3;

    var timer as Timer.Timer? = null;
    var tick as Number = 0;
    var page as Number = 0;
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
                page = 0;
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

    // ------------------------------------------------------------------ dessin
    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (page == 1) {
            drawCardio(dc);
        } else if (page == 2) {
            drawSummary(dc);
        } else {
            drawExercise(dc);
        }
        drawPageDots(dc);
        if (status.length() > 0) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, dc.getWidth() / 2, dc.getHeight() * 0.86, dc.getWidth() * 0.66, Graphics.FONT_XTINY, status, 1);
        }
    }

    // Chrono en haut avec icone chronometre, comme le champ "Temps" des activites.
    function drawTimer(dc as Dc, y as Numeric) as Void {
        var cx = dc.getWidth() / 2;
        var t = Ui.fmtClock(Live.elapsedSeconds());
        var tw = dc.getTextWidthInPixels(t, Graphics.FONT_XTINY);
        var r = dc.getFontHeight(Graphics.FONT_XTINY) * 0.28;
        Icons.stopwatch(dc, cx - tw / 2 - r * 1.6, y, r, Graphics.COLOR_LT_GRAY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + r * 0.8, y, Graphics.FONT_XTINY, t, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // FC avec coeur, valeur coloree par zone. Retourne la largeur dessinee.
    function drawHrField(dc as Dc, cx as Numeric, cy as Numeric, font as FontDefinition) as Void {
        var hr = Live.hr;
        var txt = (hr == null) ? "--" : (hr as Number).toString();
        var tw = dc.getTextWidthInPixels(txt, font);
        var fh = dc.getFontHeight(font);
        var r = fh * 0.22;
        var x0 = cx - (tw + r * 2.6) / 2;
        var zone = Icons.hrZone(hr);
        Icons.heart(dc, x0 + r, cy, r, hr == null ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_RED);
        dc.setColor(hr == null ? Graphics.COLOR_LT_GRAY : Icons.zoneColor(zone), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + r * 2.6, cy, font, txt, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawPageDots(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var x = w * 0.96;
        var cy = h / 2;
        for (var i = 0; i < PAGES; i++) {
            dc.setColor(i == page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, cy + (i - 1) * 9, i == page ? 3 : 2);
        }
    }

    // ---- page 0 : exercice
    function drawExercise(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var small = w < 300;
        drawTimer(dc, h * 0.085);

        if (!Live.hasSession()) {
            Icons.circle(dc, cx, h * 0.30, h * 0.06, Graphics.COLOR_DK_GRAY);
            Icons.link(dc, cx, h * 0.30 - h * 0.02, h * 0.035, Graphics.COLOR_LT_GRAY);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.40, w * 0.78, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.NoLiveSession) as String, 3);
            drawHrField(dc, cx, h * 0.76, Graphics.FONT_NUMBER_MEDIUM);
            return;
        }

        var i = shownIndex();
        var ex = Live.exerciseAt(i);
        var exs = Live.exercises();
        var cur = (i == Live.currentIndex());

        // etat : icone + numero, equipement connecte signale par les ondes
        var iy = h * 0.19;
        var ir = small ? 7 : 11;
        var num = (i + 1) + "/" + exs.size();
        var nw = dc.getTextWidthInPixels(num, Graphics.FONT_XTINY);
        var connected = (ex != null && !Live.isDone(ex) && ex.hasKey("device") && (ex["device"] as String).equals("FullConnected"));
        var total = ir * 2 + 6 + nw + (connected ? ir * 2.4 : 0);
        var x = cx - total / 2;
        Icons.status(dc, x + ir, iy, ir, ex, cur);
        x += ir * 2 + 6;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, iy, Graphics.FONT_XTINY, num, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (connected) {
            Icons.link(dc, x + nw + ir * 1.4, iy - ir * 0.4, ir * 0.7, Graphics.COLOR_GREEN);
        }

        // nom (2 lignes), equipement si place, series
        dc.setColor(flash > 0 && cursor < 0 ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var y = h * 0.26;
        var used = Ui.drawWrapped(dc, cx, y, w * 0.84, Graphics.FONT_SMALL, Live.title(ex), 2);
        y += used;
        var eq = Live.equipment(ex);
        if (used <= dc.getFontHeight(Graphics.FONT_SMALL) && eq.length() > 0 && !eq.equals(Live.title(ex))) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, y, w * 0.84, Graphics.FONT_XTINY, eq, 1);
            y += dc.getFontHeight(Graphics.FONT_XTINY);
        }
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, y, w * 0.86, small ? Graphics.FONT_SMALL : Graphics.FONT_MEDIUM, Live.setsText(ex), 1);

        // separateur puis FC (gauche) et suivant (droite) comme deux champs bas
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.18, h * 0.655, w * 0.82, h * 0.655);
        drawHrField(dc, cx, h * 0.755, Graphics.FONT_NUMBER_MEDIUM);

        var footer = "";
        var color = Graphics.COLOR_LT_GRAY;
        if (flash > 0 && Live.lastEvent.length() > 0) {
            footer = Live.lastEvent;
            color = Graphics.COLOR_YELLOW;
        } else {
            for (var k = i + 1; k < exs.size(); k++) {
                if (!Live.isDone(exs[k] as Dictionary)) { footer = (WatchUi.loadResource(Rez.Strings.NextExercise) as String) + Live.title(exs[k] as Dictionary); break; }
            }
            if (footer.length() == 0 && Live.totalCount() > 0 && Live.doneCount() >= Live.totalCount()) { footer = WatchUi.loadResource(Rez.Strings.SessionDone) as String; }
        }
        if (footer.length() > 0 && status.length() == 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.855, w * 0.60, Graphics.FONT_XTINY, footer, 1);
        }
        Ui.drawProgressArc(dc, Live.totalCount() > 0 ? Live.doneCount().toFloat() / Live.totalCount() : 0.0, Graphics.COLOR_GREEN);
    }

    // ---- page 1 : cardio
    function drawCardio(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        drawTimer(dc, h * 0.085);
        var hr = Live.hr;
        var zone = Icons.hrZone(hr);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.19, Graphics.FONT_XTINY, "FRÉQ. CARDIAQUE", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        drawHrField(dc, cx, h * 0.36, w < 300 ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_THAI_HOT);
        Icons.zoneBar(dc, w * 0.22, h * 0.50, w * 0.56, h * 0.03, zone);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.575, Graphics.FONT_XTINY, zone > 0 ? "ZONE " + zone : "bpm", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.15, h * 0.64, w * 0.85, h * 0.64);
        dc.drawLine(cx, h * 0.64, cx, h * 0.90);
        drawField(dc, cx - w * 0.17, h * 0.77, "MOY", Live.hrAvg() > 0 ? Live.hrAvg().toString() : "--", Graphics.COLOR_WHITE);
        drawField(dc, cx + w * 0.17, h * 0.77, "MAX", Live.hrMax > 0 ? Live.hrMax.toString() : "--", Graphics.COLOR_WHITE);
    }

    // ---- page 2 : seance (grille 4 champs a la Garmin)
    function drawSummary(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, h * 0.06, w * 0.6, Graphics.FONT_XTINY, Live.hasSession() ? Live.sessionName() : (WatchUi.loadResource(Rez.Strings.NoLiveShort) as String), 1);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.12, h * 0.50, w * 0.88, h * 0.50);
        dc.drawLine(cx, h * 0.16, cx, h * 0.86);
        var kcal = Live.caloriesDone();
        drawField(dc, cx - w * 0.2, h * 0.33, "DURÉE", Ui.fmtClock(Live.elapsedSeconds()), Graphics.COLOR_WHITE);
        drawField(dc, cx + w * 0.2, h * 0.33, "EXERCICES", Live.doneCount() + "/" + Live.totalCount(), Graphics.COLOR_GREEN);
        drawField(dc, cx - w * 0.2, h * 0.68, "MOVEs", Live.movesDone().toString(), Graphics.COLOR_ORANGE);
        drawField(dc, cx + w * 0.2, h * 0.68, "KCAL", kcal > 0 ? kcal.toString() : "--", Graphics.COLOR_WHITE);
    }

    // Champ a la Garmin : etiquette petite au-dessus, valeur en chiffres.
    function drawField(dc as Dc, cx as Numeric, cy as Numeric, label as String, value as String, color as ColorType) as Void {
        var lh = dc.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - lh * 0.9, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + lh * 0.5, Graphics.FONT_NUMBER_MILD, value, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class LiveDelegate extends WatchUi.BehaviorDelegate {

    var view as LiveView;

    function initialize(v as LiveView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    // UP / DOWN : pages, comme les ecrans de donnees d'une activite
    function onNextPage() as Boolean {
        view.page = (view.page + 1) % view.PAGES;
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        view.page = (view.page + view.PAGES - 1) % view.PAGES;
        WatchUi.requestUpdate();
        return true;
    }

    // START : liste des exercices (icones d'etat), choisir = afficher cet exercice
    function onSelect() as Boolean {
        var exs = Live.exercises();
        if (exs.size() == 0) { return onMenu(); }
        var menu = new WatchUi.Menu2({ :title => Live.sessionName() });
        var cur = Live.currentIndex();
        for (var i = 0; i < exs.size(); i++) {
            var ex = exs[i] as Dictionary;
            var sub = Live.setsText(ex);
            if (Live.isDone(ex)) { sub = (WatchUi.loadResource(Rez.Strings.Done) as String) + (sub.length() > 0 ? "  " + sub : ""); }
            menu.addItem(new WatchUi.IconMenuItem(Live.title(ex), sub, i, new StatusIconDrawable(ex, i == cur), null));
        }
        WatchUi.pushView(menu, new LiveListDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }

    // appui long UP : options
    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.ShortName) as String });
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
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

class LiveListDelegate extends WatchUi.Menu2InputDelegate {

    var view as LiveView;

    function initialize(v as LiveView) {
        Menu2InputDelegate.initialize();
        view = v;
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id instanceof Number) {
            view.cursor = (id as Number) == Live.currentIndex() ? -1 : id as Number;
            view.page = 0;
        }
        WatchUi.requestUpdate();
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
            view.page = 0;
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
