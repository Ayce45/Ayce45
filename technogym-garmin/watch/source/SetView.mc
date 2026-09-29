import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.Time;

// Ecran "serie courante" pour un exercice de musculation : cible reps x charge, chrono.
// SELECT : la serie est faite -> saisie reps / charge (pre-remplie avec la cible).
class SetView extends WatchUi.View {

    var timer as Timer.Timer;
    var shownAt as Number;

    function initialize() {
        View.initialize();
        timer = new Timer.Timer();
        shownAt = Time.now().value();
    }

    function onShow() as Void {
        shownAt = Time.now().value();
        timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        timer.stop();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var ex = Model.currentExercise();
        var set = Model.currentSet();
        var sets = Model.setsOf(ex);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.08, Graphics.FONT_XTINY, (Model.exIndex + 1) + "/" + Model.exerciseCount(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var th = Ui.drawWrapped(dc, cx, h * 0.15, w * 0.84, Graphics.FONT_SMALL, Model.exerciseTitle(ex), 2);

        if (ex != null && ex.hasKey("equipment")) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.15 + th, Graphics.FONT_XTINY, ex["equipment"] as String, Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.47, Graphics.FONT_TINY, (WatchUi.loadResource(Rez.Strings.Set) as String) + " " + (Model.setIndex + 1) + "/" + sets.size(), Graphics.TEXT_JUSTIFY_CENTER);

        var target = "";
        if (set != null) {
            if (set.hasKey("reps")) { target = set["reps"].toString() + " " + (WatchUi.loadResource(Rez.Strings.Reps) as String); }
            if (set.hasKey("weight_kg")) { target += (target.length() > 0 ? " x " : "") + Ui.fmtKg(Model.num(set, "weight_kg", 0)) + " kg"; }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.56, Graphics.FONT_LARGE, target, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.76, Graphics.FONT_TINY, Ui.fmtClock(Time.now().value() - shownAt), Graphics.TEXT_JUSTIFY_CENTER);

        var done = Model.doneSetsCount();
        var total = 0;
        var exs = Model.exercises();
        for (var i = 0; i < exs.size(); i++) { total += Model.setsOf(exs[i] as Dictionary).size(); }
        Ui.drawProgressArc(dc, total > 0 ? done.toFloat() / total : 0.0, Graphics.COLOR_ORANGE);
    }
}

class SetDelegate extends WatchUi.BehaviorDelegate {

    var view as SetView;

    function initialize(v as SetView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onSelect() as Boolean {
        return openInput();
    }

    function onTap(evt as ClickEvent) as Boolean {
        return openInput();
    }

    function openInput() as Boolean {
        var set = Model.currentSet();
        var reps = Model.num(set, "reps", 10).toNumber();
        var weight = Model.num(set, "weight_kg", 0).toFloat();
        var iv = new SetInputView(reps, weight);
        WatchUi.pushView(iv, new SetInputDelegate(iv), WatchUi.SLIDE_UP);
        return true;
    }

    function onMenu() as Boolean {
        Flow.showWorkoutMenu();
        return true;
    }

    function onNextPage() as Boolean {
        Flow.showExerciseList();
        return true;
    }

    function onBack() as Boolean {
        // retour a l'accueil sans perdre la seance (elle reste "en cours")
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// Saisie des reps puis de la charge reellement faites. UP/DOWN ajustent, SELECT valide le champ.
class SetInputView extends WatchUi.View {

    var reps as Number;
    var weight as Float;
    var field as Number = 0;   // 0 = reps, 1 = charge

    function initialize(r as Number, w as Float) {
        View.initialize();
        reps = r;
        weight = w;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.10, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Done) as String, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(field == 0 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.24, Graphics.FONT_NUMBER_MEDIUM, reps.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.24 + dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM), Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Reps) as String, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(field == 1 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.54, Graphics.FONT_NUMBER_MEDIUM, Ui.fmtKg(weight), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.54 + dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM), Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Kg) as String, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.88, Graphics.FONT_XTINY, field == 0 ? "haut/bas puis OK" : "OK = valider", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function adjust(delta as Number) as Void {
        if (field == 0) {
            reps += delta;
            if (reps < 0) { reps = 0; }
            if (reps > 200) { reps = 200; }
        } else {
            weight += delta * Model.weightStep;
            if (weight < 0.0) { weight = 0.0; }
        }
        WatchUi.requestUpdate();
    }

    // Retourne true quand la saisie est complete.
    function next() as Boolean {
        if (field == 0) {
            field = 1;
            WatchUi.requestUpdate();
            return false;
        }
        return true;
    }
}

class SetInputDelegate extends WatchUi.BehaviorDelegate {

    var view as SetInputView;

    function initialize(v as SetInputView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onPreviousPage() as Boolean {   // UP
        view.adjust(1);
        return true;
    }

    function onNextPage() as Boolean {       // DOWN
        view.adjust(-1);
        return true;
    }

    function onSwipe(evt as SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP) { view.adjust(1); return true; }
        if (d == WatchUi.SWIPE_DOWN) { view.adjust(-1); return true; }
        return false;
    }

    function onSelect() as Boolean {
        return confirm();
    }

    function onTap(evt as ClickEvent) as Boolean {
        return confirm();
    }

    function confirm() as Boolean {
        if (!view.next()) { return true; }
        var ex = Model.currentExercise();
        var set = Model.currentSet();
        var rest = Model.num(set, "rest_s", 0).toNumber();
        var pos = Model.num(ex, "position", 0).toNumber();
        var finished = Model.recordSet(view.reps, view.weight, null, false);
        Recording.lap(pos, view.reps, view.weight);
        Recording.vibrate(false);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        Flow.afterSet(finished, rest);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
