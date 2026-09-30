import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.Time;

// Compte a rebours generique (repos ou bloc a duree : cardio, etirement).
class CountdownView extends WatchUi.View {

    var total as Number;
    var remaining as Number;
    var timer as Timer.Timer;
    var running as Boolean = false;
    var title as String;
    var subtitle as String;
    var color as ColorType;
    var endAt as Number = 0;
    var onFinish as Method?;   // appele une fois a zero

    function initialize(seconds as Number, t as String, sub as String, c as ColorType) {
        View.initialize();
        total = seconds;
        remaining = seconds;
        title = t;
        subtitle = sub;
        color = c;
        timer = new Timer.Timer();
    }

    function onShow() as Void {
        if (!running) {
            endAt = Time.now().value() + remaining;
            running = true;
        }
        timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        timer.stop();
    }

    function onTick() as Void {
        if (!running) { return; }
        remaining = endAt - Time.now().value();
        if (remaining <= 0) {
            remaining = 0;
            running = false;
            timer.stop();
            Recording.vibrate(true);
            if (onFinish != null) { (onFinish as Method).invoke(); }
        }
        WatchUi.requestUpdate();
    }

    function addSeconds(n as Number) as Void {
        endAt += n;
        remaining = endAt - Time.now().value();
        if (remaining < 0) { remaining = 0; }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.14, Graphics.FONT_SMALL, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.30, Graphics.FONT_NUMBER_HOT, Ui.fmtClock(remaining), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, h * 0.66, w * 0.84, Graphics.FONT_XTINY, subtitle, 2);
        Ui.drawProgressArc(dc, total > 0 ? (total - remaining).toFloat() / total : 1.0, color);
    }
}

// Repos entre deux series : vibre a la fin, puis passe a la serie suivante.
class RestView extends CountdownView {

    function initialize(seconds as Number) {
        var next = Model.currentExercise();
        var set = Model.currentSet();
        var sub = Model.exerciseTitle(next);
        if (set != null && set.hasKey("reps")) {
            sub += " : " + set["reps"].toString() + " x " + Ui.fmtKg(Model.num(set, "weight_kg", 0)) + " kg";
        } else if (set != null && set.hasKey("duration_s")) {
            sub += " : " + set["duration_s"].toString() + " s";
        }
        CountdownView.initialize(seconds, WatchUi.loadResource(Rez.Strings.Rest) as String, "Suite : " + sub, Graphics.COLOR_BLUE);
        onFinish = method(:goNext);
    }

    function goNext() as Void {
        Flow.showCurrent(WatchUi.SLIDE_LEFT, false);
    }
}

class RestDelegate extends WatchUi.BehaviorDelegate {

    var view as RestView;

    function initialize(v as RestView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onSelect() as Boolean {
        view.running = false;
        view.timer.stop();
        Flow.showCurrent(WatchUi.SLIDE_LEFT, false);
        return true;
    }

    function onTap(evt as ClickEvent) as Boolean {
        return onSelect();
    }

    function onPreviousPage() as Boolean {
        view.addSeconds(15);
        return true;
    }

    function onNextPage() as Boolean {
        view.addSeconds(-15);
        return true;
    }

    function onMenu() as Boolean {
        Flow.showWorkoutMenu();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// Bloc a duree (cardio, etirement) : SELECT lance le compte a rebours, fin -> serie enregistree.
class TimedSetView extends WatchUi.View {

    var countdown as CountdownView? = null;
    var started as Boolean = false;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        if (countdown != null) {
            (countdown as CountdownView).onUpdate(dc);
            return;
        }
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
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.47, Graphics.FONT_TINY, "Série " + (Model.setIndex + 1) + "/" + sets.size(), Graphics.TEXT_JUSTIFY_CENTER);
        var target = "";
        if (set != null) {
            if (set.hasKey("duration_s")) { target = Ui.fmtClock(Model.num(set, "duration_s", 0).toNumber()); }
            var extra = "";
            if (set.hasKey("power_w")) { extra = Ui.fmtKg(Model.num(set, "power_w", 0)) + " W"; }
            if (set.hasKey("level")) { extra = "Niveau " + Ui.fmtKg(Model.num(set, "level", 0)); }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.56, Graphics.FONT_LARGE, target, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.70, Graphics.FONT_TINY, extra, Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (Model.machineDone(ex)) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, "Terminé sur l'équipement", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 0.87, Graphics.FONT_XTINY, "OK : exercice suivant", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, "OK : démarrer", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function onShowLive() as Void {
        Net.fetchLive(null);
    }

    function startCountdown() as Void {
        var set = Model.currentSet();
        var secs = Model.num(set, "duration_s", 60).toNumber();
        var sub = Model.exerciseTitle(Model.currentExercise());
        var cd = new CountdownView(secs, "Série " + (Model.setIndex + 1), sub, Graphics.COLOR_GREEN);
        cd.onFinish = method(:onBlockDone);
        countdown = cd;
        cd.onShow();
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        if (countdown != null) { (countdown as CountdownView).onHide(); }
    }

    function onShow() as Void {
        if (countdown != null) { (countdown as CountdownView).onShow(); }
        Net.fetchLive(null);
    }

    function onBlockDone() as Void {
        finishBlock(false);
    }

    function finishBlock(skipped as Boolean) as Void {
        var set = Model.currentSet();
        var ex = Model.currentExercise();
        var dur = Model.num(set, "duration_s", 0).toNumber();
        var rest = Model.num(set, "rest_s", 0).toNumber();
        var pos = Model.num(ex, "position", 0).toNumber();
        if (countdown != null) { (countdown as CountdownView).onHide(); }
        countdown = null;
        var finished = Model.recordSet(null, null, skipped ? null : dur, skipped);
        Recording.lap(pos, null, null);
        Flow.afterSet(finished, rest);
    }
}

class TimedSetDelegate extends WatchUi.BehaviorDelegate {

    var view as TimedSetView;

    function initialize(v as TimedSetView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onSelect() as Boolean {
        if (view.countdown == null && Model.machineDone(Model.currentExercise())) {
            var finished = Model.acceptMachineExercise();
            Flow.afterSet(finished, 0);
            return true;
        }
        if (view.countdown == null) {
            view.startCountdown();
        } else {
            // SELECT pendant le bloc : le terminer maintenant
            view.finishBlock(false);
        }
        return true;
    }

    function onTap(evt as ClickEvent) as Boolean {
        return onSelect();
    }

    function onPreviousPage() as Boolean {
        if (view.countdown != null) { (view.countdown as CountdownView).addSeconds(30); return true; }
        return false;
    }

    function onNextPage() as Boolean {
        if (view.countdown != null) { (view.countdown as CountdownView).addSeconds(-30); return true; }
        Flow.showExerciseList();
        return true;
    }

    function onMenu() as Boolean {
        Flow.showWorkoutMenu();
        return true;
    }

    function onBack() as Boolean {
        if (view.countdown != null) {
            view.finishBlock(true);
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
