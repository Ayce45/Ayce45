import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.System;

// Exercice libre (poids libres, etirements, ou n'importe quel exercice fait sans equipement connecte) :
// la montre enchaine les series prescrites par le programme Technogym.
//   serie : compteur de repetitions (prerempli avec la cible ; UP / DOWN pour ajuster), charge cible,
//           START = serie faite -> un lap dans l'activite, puis
//   repos : compte a rebours du repos prescrit (RestTime du programme, 60 s sinon), vibration a la fin,
//           START = passer le repos, UP / DOWN = +15 s / -15 s ;
//   fin   : l'exercice est marque terminé dans la seance Technogym (POST /live/mark) et la page live
//           revient a l'exercice suivant.
// Mode repos seul (restOnly) : pour un exercice sur equipement, START lance juste la recuperation.
class FreeExerciseView extends WatchUi.View {

    var index as Number;
    var live as LiveView;
    var restOnly as Boolean;
    var sets as Array = [];
    var setIdx as Number = 0;
    var reps as Number = 0;
    var weight as Float = 0.0;
    var duration as Number = 0;
    var resting as Boolean = false;
    var restLeft as Number = 0;
    var restTotal as Number = 0;
    var timer as Timer.Timer? = null;
    var finishing as Boolean = false;
    var status as String = "";
    var autoCount as Boolean = false;   // comptage par accelerometre actif sur cette serie
    var autoReps as Number = 0;         // repetitions detectees
    var manual as Boolean = false;      // l'utilisateur a corrige a la main : on ne touche plus au compteur

    function initialize(i as Number, lv as LiveView, rest as Boolean) {
        View.initialize();
        index = i;
        live = lv;
        restOnly = rest;
        var ex = Live.exerciseAt(i);
        if (ex != null && ex.hasKey("target_sets")) { sets = ex["target_sets"] as Array; }
        if (sets.size() == 0) { sets = [{ "reps" => 10 }]; }
        loadTarget();
        if (restOnly) { startRest(); }
    }

    function ex() as Dictionary? { return Live.exerciseAt(index); }

    function currentSet() as Dictionary {
        var i = setIdx < sets.size() ? setIdx : sets.size() - 1;
        return sets[i] as Dictionary;
    }

    function loadTarget() as Void {
        var st = currentSet();
        reps = Model.autoReps && RepCounter.supported() ? 0 : Model.num(st, "reps", 0).toNumber();
        weight = Model.num(st, "weight_kg", 0).toFloat();
        duration = Model.num(st, "duration_s", 0).toNumber();
    }

    function restSeconds() as Number {
        var r = Model.num(currentSet(), "rest_s", 0).toNumber();
        return r > 0 ? r : 60;
    }

    function onShow() as Void {
        if (timer == null) {
            timer = new Timer.Timer();
            (timer as Timer.Timer).start(method(:onTick), 1000, true);
        }
        if (!resting && !restOnly) { startCounting(); }
    }

    function onHide() as Void {
        if (timer != null) { (timer as Timer.Timer).stop(); timer = null; }
        RepCounter.stop();
        autoCount = false;
    }

    // Comptage automatique : l'accelerometre compte, l'affichage suit ; UP / DOWN corrigent et figent.
    function startCounting() as Void {
        autoReps = 0;
        manual = false;
        autoCount = Model.autoReps && RepCounter.start(method(:onRep));
    }

    function onRep(n as Number) as Void {
        autoReps = n;
        if (!manual) {
            reps = n;
            if (n == Model.num(currentSet(), "reps", 0).toNumber()) { Recording.vibrate(false); }  // cible atteinte
        }
        WatchUi.requestUpdate();
    }

    function onTick() as Void {
        Live.sampleHr();
        if (resting) {
            restLeft--;
            if (restLeft <= 3 && restLeft > 0) { Recording.vibrate(false); }
            if (restLeft <= 0) {
                resting = false;
                Recording.vibrate(true);
                if (restOnly) {
                    WatchUi.popView(WatchUi.SLIDE_DOWN);
                    return;
                }
                setIdx++;
                if (setIdx >= sets.size()) { finish(); return; }
                loadTarget();
                startCounting();
            }
        }
        WatchUi.requestUpdate();
    }

    function startRest() as Void {
        RepCounter.stop();
        autoCount = false;
        restTotal = restSeconds();
        restLeft = restTotal;
        resting = true;
    }

    // START pendant une serie : serie faite (le cycle entame par l'accelerometre compte)
    function validateSet() as Void {
        if (autoCount && !manual) {
            var n = RepCounter.finalReps();
            if (n > 0) { reps = n; }
        }
        var e = ex();
        Recording.lap(e != null ? Model.num(e, "position", 0).toNumber() : 0, reps, weight);
        Recording.vibrate(false);
        if (setIdx >= sets.size() - 1) {
            finish();
            return;
        }
        startRest();
        WatchUi.requestUpdate();
    }

    // START pendant le repos : on passe a la serie suivante
    function skipRest() as Void {
        resting = false;
        if (restOnly) { WatchUi.popView(WatchUi.SLIDE_DOWN); return; }
        setIdx++;
        if (setIdx >= sets.size()) { finish(); return; }
        loadTarget();
        startCounting();
        WatchUi.requestUpdate();
    }

    function finish() as Void {
        if (finishing) { return; }
        finishing = true;
        resting = false;
        RepCounter.stop();
        autoCount = false;
        status = WatchUi.loadResource(Rez.Strings.Marking) as String;
        var e = ex();
        var pos = e != null ? Model.num(e, "position", 0).toNumber() : 0;
        if (!Net.markDone(pos, method(:onMarked))) { onMarked(false, "Hors ligne"); }
        WatchUi.requestUpdate();
    }

    function onMarked(ok as Boolean, msg as String) as Void {
        Recording.vibrate(true);
        live.status = ok ? (WatchUi.loadResource(Rez.Strings.ExerciseDone) as String) : msg;
        live.cursor = -1;
        live.page = 0;
        live.poll();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var small = w < 300;
        var e = ex();
        var lh = dc.getFontHeight(Graphics.FONT_XTINY);

        // en-tete : equipement / famille, exercice, serie n/N
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var y = h * 0.06;
        y += Ui.drawWrapped(dc, cx, y, w * 0.60, Graphics.FONT_XTINY, Live.headline(e), 1);
        if (!Live.title(e).equals(Live.headline(e))) {
            y += Ui.drawWrapped(dc, cx, y, w * 0.78, Graphics.FONT_XTINY, Live.title(e), 1);
        }
        if (!restOnly) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, (WatchUi.loadResource(Rez.Strings.SetLabel) as String) + " " + (setIdx + 1) + "/" + sets.size(), Graphics.TEXT_JUSTIFY_CENTER);
            y += lh;
        }

        if (resting) {
            // repos : compte a rebours en grand, arc, prochaine serie
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.36, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.RestLabel) as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(cx, h * 0.52, small ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_THAI_HOT, Ui.fmtClock(restLeft), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            Ui.drawProgressArc(dc, restTotal > 0 ? (restTotal - restLeft).toFloat() / restTotal : 0.0, Graphics.COLOR_BLUE);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            if (!restOnly && setIdx + 1 < sets.size()) {
                var nx = sets[setIdx + 1] as Dictionary;
                Ui.drawWrapped(dc, cx, h * 0.70, w * 0.70, Graphics.FONT_XTINY, (WatchUi.loadResource(Rez.Strings.NextExercise) as String) + Live.oneSet(nx), 1);
            }
            dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.SkipRestHint) as String, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // serie : repetitions en grand (ou duree), charge
            if (duration > 0 && reps == 0) {
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 0.48, small ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_THAI_HOT, Ui.fmtClock(duration), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                var f = small ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_THAI_HOT;
                var txt = reps.toString();
                var tw = dc.getTextWidthInPixels(txt, f);
                dc.drawText(cx - lh, h * 0.47, f, txt, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx - lh + tw / 2 + 4, h * 0.47 + lh * 0.4, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Reps) as String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                var target = Model.num(currentSet(), "reps", 0).toNumber();
                var tag = autoCount && !manual ? (WatchUi.loadResource(Rez.Strings.AutoCount) as String) + " · " : "";
                dc.drawText(cx, h * 0.585, Graphics.FONT_XTINY, tag + (WatchUi.loadResource(Rez.Strings.Target) as String) + " " + target, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                if (weight > 0) {
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(cx, h * 0.69, Graphics.FONT_SMALL, Ui.fmtKg(weight) + " kg", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                }
            }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.SetDoneHint) as String, Graphics.TEXT_JUSTIFY_CENTER);
        }
        // FC discrete en bas
        var hr = Live.hr;
        if (hr != null) {
            Icons.heart(dc, cx - lh * 1.1, h * 0.905, lh * 0.28, Graphics.COLOR_RED);
            dc.setColor(Icons.zoneColor(Icons.hrZone(hr)), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + lh * 0.2, h * 0.905, Graphics.FONT_XTINY, (hr as Number).toString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (status.length() > 0) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.86, w * 0.6, Graphics.FONT_XTINY, status, 1);
        }
    }
}

class FreeExerciseDelegate extends WatchUi.BehaviorDelegate {

    var view as FreeExerciseView;

    function initialize(v as FreeExerciseView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onSelect() as Boolean {
        if (view.finishing) { return true; }
        if (view.resting) { view.skipRest(); } else { view.validateSet(); }
        return true;
    }

    function onPreviousPage() as Boolean {   // UP
        if (view.resting) { view.restLeft += 15; view.restTotal += 15; } else { view.reps++; view.manual = true; }
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {       // DOWN
        if (view.resting) { view.restLeft -= 15; if (view.restLeft < 1) { view.restLeft = 1; } } else if (view.reps > 0) { view.reps--; view.manual = true; }
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => Live.headline(view.ex()) });
        if (!view.restOnly) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.FinishExercise) as String, null, :finish, null));
        }
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Cancel) as String, null, :cancel, null));
        WatchUi.pushView(menu, new FreeExerciseMenuDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class FreeExerciseMenuDelegate extends WatchUi.Menu2InputDelegate {

    var view as FreeExerciseView;

    function initialize(v as FreeExerciseView) {
        Menu2InputDelegate.initialize();
        view = v;
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :finish) {
            view.finish();
        } else if (id == :cancel) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}
