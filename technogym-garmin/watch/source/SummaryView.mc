import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Time;

// Fin de seance : resume, puis SELECT = sauvegarde FIT (d'abord) et envoi des resultats.
class SummaryView extends WatchUi.View {

    var status as String = "";
    var phase as Number = 0;   // 0 = resume, 1 = sauve, 2 = envoye / en attente

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.12, Graphics.FONT_SMALL, WatchUi.loadResource(Rez.Strings.Summary) as String, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var dur = Model.startedAt > 0 ? Time.now().value() - Model.startedAt : 0;
        dc.drawText(cx, h * 0.28, Graphics.FONT_MEDIUM, Ui.fmtClock(dur), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.44, Graphics.FONT_TINY, Model.doneSetsCount() + " series", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.54, Graphics.FONT_TINY, Ui.fmtKg(Model.totalVolumeKg()) + " kg souleves", Graphics.TEXT_JUSTIFY_CENTER);
        if (phase == 0) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.70, Graphics.FONT_SMALL, "OK : enregistrer la séance", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.68, w * 0.86, Graphics.FONT_XTINY, status, 3);
        }
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    var view as SummaryView?;

    function initialize(v as SummaryView?) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function current() as SummaryView? {
        return view;
    }

    function onSelect() as Boolean {
        return saveAndSend();
    }

    function onTap(evt as ClickEvent) as Boolean {
        return saveAndSend();
    }

    function saveAndSend() as Boolean {
        var v = view;
        if (v != null && (v as SummaryView).phase >= 2) {
            finish();
            return true;
        }
        if (v != null && (v as SummaryView).phase == 1) {
            return true;
        }
        // 1. FIT d'abord : la seance locale ne se perd jamais
        var fitOk = Recording.save();
        var payload = Model.buildResultsPayload(fitOk);
        if (v != null) {
            (v as SummaryView).phase = 1;
            (v as SummaryView).status = fitOk ? (WatchUi.loadResource(Rez.Strings.Saved) as String) + "..." : "FIT non sauve...";
        }
        WatchUi.requestUpdate();
        // 2. puis envoi ; en echec la seance est mise en attente
        if (!Net.sendResults(payload, method(:onSent))) {
            Model.queuePending(payload);
            onSent(false, WatchUi.loadResource(Rez.Strings.SendFailed) as String);
        }
        return true;
    }

    function onSent(ok as Boolean, msg as String) as Void {
        var v = view;
        if (v != null) {
            (v as SummaryView).phase = 2;
            (v as SummaryView).status = (ok ? msg : (WatchUi.loadResource(Rez.Strings.SendFailed) as String) + " (" + msg + ")") + "  OK = quitter";
        }
        Model.inProgress = false;
        Model.resetProgress();
        WatchUi.requestUpdate();
    }

    function finish() as Void {
        // retour a l'accueil (la vue accueil est la premiere de la pile)
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onMenu() as Boolean {
        Flow.showWorkoutMenu();
        return true;
    }

    function onBack() as Boolean {
        var v = view;
        if (v != null && (v as SummaryView).phase == 0) {
            // reprendre la seance : revenir au dernier exercice
            if (Model.exIndex >= Model.exerciseCount() && Model.exerciseCount() > 0) {
                Model.exIndex = Model.exerciseCount() - 1;
                Model.setIndex = Model.setsOf(Model.currentExercise()).size() - 1;
                if (Model.setIndex < 0) { Model.setIndex = 0; }
            }
            Flow.showCurrent(WatchUi.SLIDE_RIGHT, false);
            return true;
        }
        finish();
        return true;
    }
}
