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

        // equipement en grand (1 ligne), nom de l'exercice en petit (2 lignes), puis les series
        dc.setColor(flash > 0 && cursor < 0 ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var y = h * 0.245;
        y += Ui.drawWrapped(dc, cx, y, w * 0.84, small ? Graphics.FONT_SMALL : Graphics.FONT_MEDIUM, Live.headline(ex), 1);
        var sub = Live.title(ex);
        if (!sub.equals(Live.headline(ex))) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            y += Ui.drawWrapped(dc, cx, y, w * 0.86, Graphics.FONT_XTINY, sub, 2);
        }
        y += h * 0.01;
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, y, w * 0.86, small ? Graphics.FONT_SMALL : Graphics.FONT_MEDIUM, Live.setsText(ex), 1);

        // separateur puis FC (gauche) et suivant (droite) comme deux champs bas
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.18, h * 0.655, w * 0.82, h * 0.655);
        drawHrField(dc, cx, h * 0.755, Graphics.FONT_NUMBER_MEDIUM);

        // en bas : seulement l'evenement du moment (exercice validé, séance démarrée), 6 s, puis rien.
        // La page suit d'elle-meme l'exercice courant ; le suivant est sur la page Séance.
        if (flash > 0 && Live.lastEvent.length() > 0 && status.length() == 0) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.855, w * 0.60, Graphics.FONT_XTINY, Live.lastEvent, 1);
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

    // ---- page 2 : seance. Grille 4 champs a la Garmin en haut, champ "Suivant" au centre-bas.
    function drawSummary(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var small = w < 300;
        if (!Live.hasSession()) {
            drawTimer(dc, h * 0.085);
            Icons.circle(dc, cx, h * 0.30, h * 0.06, Graphics.COLOR_DK_GRAY);
            Icons.link(dc, cx, h * 0.30 - h * 0.02, h * 0.035, Graphics.COLOR_LT_GRAY);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.40, w * 0.78, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.NoLiveSession) as String, 3);
            drawHrField(dc, cx, h * 0.76, Graphics.FONT_NUMBER_MEDIUM);
            return;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, h * 0.06, w * 0.6, Graphics.FONT_XTINY, Live.hasSession() ? Live.sessionName() : (WatchUi.loadResource(Rez.Strings.NoLiveShort) as String), 1);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.10, h * 0.395, w * 0.90, h * 0.395);
        dc.drawLine(cx, h * 0.15, cx, h * 0.62);
        dc.drawLine(w * 0.16, h * 0.635, w * 0.84, h * 0.635);
        var kcal = Live.caloriesDone();
        var vf = small ? Graphics.FONT_TINY : Graphics.FONT_NUMBER_MILD;
        drawFieldF(dc, cx - w * 0.21, h * 0.265, "DURÉE", Ui.fmtClock(Live.elapsedSeconds()), Graphics.COLOR_WHITE, vf);
        drawFieldF(dc, cx + w * 0.21, h * 0.265, "EXERCICES", Live.doneCount() + "/" + Live.totalCount(), Graphics.COLOR_GREEN, vf);
        drawFieldF(dc, cx - w * 0.21, h * 0.505, "MOVEs", Live.movesDone().toString(), Graphics.COLOR_ORANGE, vf);
        drawFieldF(dc, cx + w * 0.21, h * 0.505, "KCAL", kcal > 0 ? kcal.toString() : "--", Graphics.COLOR_WHITE, vf);

        // champ Suivant : premier exercice non fait apres le courant ; sinon fin de seance
        var nxt = null;
        var exs = Live.exercises();
        var i = Live.currentIndex();
        if (i >= 0) {
            var cur = Live.exerciseAt(i);
            if (cur != null && !Live.isDone(cur)) {
                for (var k = i + 1; k < exs.size(); k++) {
                    if (!Live.isDone(exs[k] as Dictionary)) { nxt = exs[k] as Dictionary; break; }
                }
            }
        }
        var complete = Live.totalCount() > 0 && Live.doneCount() >= Live.totalCount();
        var lh = dc.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.665, Graphics.FONT_XTINY, complete ? "SÉANCE" : "SUIVANT", Graphics.TEXT_JUSTIFY_CENTER);
        if (complete) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.665 + lh, w * 0.70, Graphics.FONT_SMALL, WatchUi.loadResource(Rez.Strings.SessionDone) as String, 2);
        } else if (nxt != null) {
            // equipement en grand, puis "exercice · series" en petit
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var used = Ui.drawWrapped(dc, cx, h * 0.665 + lh, w * 0.72, Graphics.FONT_SMALL, Live.headline(nxt), 1);
            var line2 = Live.title(nxt).equals(Live.headline(nxt)) ? Live.setsText(nxt) : Live.title(nxt) + (Live.setsText(nxt).length() > 0 ? " · " + Live.setsText(nxt) : "");
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.665 + lh + used, w * 0.62, Graphics.FONT_XTINY, line2, 1);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.665 + lh, Graphics.FONT_XTINY, "--", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawFieldF(dc as Dc, cx as Numeric, cy as Numeric, label as String, value as String, color as ColorType, font as FontDefinition) as Void {
        var lh = dc.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - lh * 0.85, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + lh * 0.45, font, value, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

    // START : actions sur l'exercice affiche (comme le bouton Lap / Serie des activites Garmin)
    function onSelect() as Boolean {
        var exs = Live.exercises();
        if (exs.size() == 0) { return onMenu(); }
        var i = view.shownIndex();
        var ex = Live.exerciseAt(i);
        var menu = new WatchUi.Menu2({ :title => Live.headline(ex) });
        var connected = ex != null && ex.hasKey("device") && (ex["device"] as String).equals("FullConnected");
        if (!Live.isDone(ex)) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.FreeStart) as String, Live.setsText(ex), :free, null));
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.RestNow) as String, restHint(ex), :rest, null));
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.MarkDone) as String, connected ? (WatchUi.loadResource(Rez.Strings.MarkDoneHintMachine) as String) : null, :mark, null));
        }
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Sheet) as String, null, :sheet, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Exercises) as String, Live.doneCount() + "/" + Live.totalCount(), :list, null));
        WatchUi.pushView(menu, new LiveActionDelegate(view, i), WatchUi.SLIDE_UP);
        return true;
    }

    function restHint(ex as Dictionary?) as String {
        if (ex == null || !ex.hasKey("target_sets")) { return "60 s"; }
        var ts = ex["target_sets"] as Array;
        if (ts.size() == 0) { return "60 s"; }
        var r = Model.num(ts[0] as Dictionary, "rest_s", 0).toNumber();
        return (r > 0 ? r : 60) + " s";
    }

    // Liste des exercices (icones d'etat), choisir = fiche
    function showList() as Void {
        var exs = Live.exercises();
        var menu = new WatchUi.Menu2({ :title => Live.sessionName() });
        var cur = Live.currentIndex();
        for (var i = 0; i < exs.size(); i++) {
            var ex = exs[i] as Dictionary;
            var sub = Live.setsText(ex);
            if (Live.isDone(ex)) { sub = (WatchUi.loadResource(Rez.Strings.Done) as String) + (sub.length() > 0 ? "  " + sub : ""); }
            menu.addItem(new WatchUi.IconMenuItem(Live.fullTitle(ex), sub, i, new StatusIconDrawable(ex, i == cur), null));
        }
        WatchUi.pushView(menu, new LiveListDelegate(view), WatchUi.SLIDE_UP);
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

class LiveActionDelegate extends WatchUi.Menu2InputDelegate {

    var view as LiveView;
    var index as Number;

    function initialize(v as LiveView, i as Number) {
        Menu2InputDelegate.initialize();
        view = v;
        index = i;
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :free) {
            var fv = new FreeExerciseView(index, view, false);
            WatchUi.pushView(fv, new FreeExerciseDelegate(fv), WatchUi.SLIDE_UP);
        } else if (id == :rest) {
            var rv = new FreeExerciseView(index, view, true);
            WatchUi.pushView(rv, new FreeExerciseDelegate(rv), WatchUi.SLIDE_UP);
        } else if (id == :mark) {
            var ex = Live.exerciseAt(index);
            var pos = ex != null ? Model.num(ex, "position", 0).toNumber() : 0;
            view.status = WatchUi.loadResource(Rez.Strings.Marking) as String;
            if (!Net.markDone(pos, method(:onMarked))) { view.status = "Hors ligne"; }
        } else if (id == :sheet) {
            var dv = new DetailView(index, view);
            WatchUi.pushView(dv, new DetailDelegate(dv), WatchUi.SLIDE_LEFT);
        } else if (id == :list) {
            new LiveDelegate(view).showList();
        }
        WatchUi.requestUpdate();
    }

    function onMarked(ok as Boolean, msg as String) as Void {
        view.status = ok ? (WatchUi.loadResource(Rez.Strings.ExerciseDone) as String) : msg;
        view.cursor = -1;
        if (ok) { Recording.vibrate(true); view.poll(); }
        WatchUi.requestUpdate();
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
            var dv = new DetailView(id as Number, view);
            WatchUi.pushView(dv, new DetailDelegate(dv), WatchUi.SLIDE_LEFT);
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
