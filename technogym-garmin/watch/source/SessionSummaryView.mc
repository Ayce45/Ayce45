import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Ecran de fin de seance, comme le recapitulatif d'une activite Garmin : duree, exercices terminés, MOVEs,
// kcal, FC moyenne / max, volume souleve sur la montre. START = enregistrer l'activite et quitter ;
// menu (appui long UP) : fermer aussi la seance cote Technogym ; BACK = revenir a la seance.
class SessionSummaryView extends WatchUi.View {

    var live as LiveView;
    var status as String = "";

    function initialize(lv as LiveView) {
        View.initialize();
        live = lv;
    }

    function field(dc as Dc, cx as Numeric, cy as Numeric, label as String, value as String, color as ColorType, font as FontDefinition) as Void {
        var lh = dc.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - lh * 0.8, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + lh * 0.45, font, value, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var small = w < 300;
        var vf = small ? Graphics.FONT_TINY : Graphics.FONT_NUMBER_MILD;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, h * 0.05, w * 0.7, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.SessionSummary) as String, 1);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.10, h * 0.385, w * 0.90, h * 0.385);
        dc.drawLine(w * 0.10, h * 0.62, w * 0.90, h * 0.62);
        dc.drawLine(cx, h * 0.14, cx, h * 0.84);
        field(dc, cx - w * 0.21, h * 0.26, "DURÉE", Ui.fmtClock(Live.elapsedSeconds()), Graphics.COLOR_WHITE, vf);
        field(dc, cx + w * 0.21, h * 0.26, "EXERCICES", Live.doneCount() + "/" + Live.totalCount(), Graphics.COLOR_GREEN, vf);
        field(dc, cx - w * 0.21, h * 0.50, "MOVEs", Live.movesDone().toString(), Graphics.COLOR_ORANGE, vf);
        var kcal = Live.caloriesDone();
        field(dc, cx + w * 0.21, h * 0.50, "KCAL", kcal > 0 ? kcal.toString() : "--", Graphics.COLOR_WHITE, vf);
        var fc = Live.hrAvg() > 0 ? Live.hrAvg() + "/" + Live.hrMax : "--";
        field(dc, cx - w * 0.21, h * 0.73, "FC MOY/MAX", fc, Icons.zoneColor(Icons.hrZone(Live.hrAvg() > 0 ? Live.hrAvg() : null)), small ? Graphics.FONT_TINY : Graphics.FONT_SMALL);
        var vol = Model.liveVolumeKg > 0 ? (Model.liveVolumeKg >= 1000 ? (Model.liveVolumeKg / 1000).format("%.1f") + " t" : Model.liveVolumeKg.toNumber() + " kg") : "--";
        field(dc, cx + w * 0.21, h * 0.73, WatchUi.loadResource(Rez.Strings.Volume) as String, vol, Graphics.COLOR_WHITE, small ? Graphics.FONT_TINY : Graphics.FONT_SMALL);
        dc.setColor(status.length() > 0 ? Graphics.COLOR_YELLOW : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, h * 0.875, w * 0.62, Graphics.FONT_XTINY, status.length() > 0 ? status : (WatchUi.loadResource(Rez.Strings.SaveAndQuit) as String), 1);
    }
}

class SessionSummaryDelegate extends WatchUi.BehaviorDelegate {

    var view as SessionSummaryView;

    function initialize(v as SessionSummaryView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    // START : enregistre l'activite FIT et revient a l'accueil
    function onSelect() as Boolean {
        Live.flushHr();
        var saved = Recording.save();
        Model.liveMode = false;
        Model.startedAt = 0;
        Model.resetLiveStats();
        view.live.status = saved ? (WatchUi.loadResource(Rez.Strings.Saved) as String) : "Aucune activité à enregistrer";
        WatchUi.popView(WatchUi.SLIDE_DOWN);   // resume
        WatchUi.popView(WatchUi.SLIDE_RIGHT);  // live -> accueil
        return true;
    }

    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.SessionSummary) as String });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.CloseTechnogym) as String, Live.hasSession() ? Live.sessionName() : null, :close, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Discard) as String, null, :discard, null));
        WatchUi.pushView(menu, new SessionSummaryMenuDelegate(view), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class SessionSummaryMenuDelegate extends WatchUi.Menu2InputDelegate {

    var view as SessionSummaryView;

    function initialize(v as SessionSummaryView) {
        Menu2InputDelegate.initialize();
        view = v;
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :close) {
            view.status = WatchUi.loadResource(Rez.Strings.Marking) as String;
            if (!Net.closeSession(method(:onClosed))) { view.status = "Hors ligne"; }
        } else if (id == :discard) {
            Recording.discard();
            Model.liveMode = false;
            Model.startedAt = 0;
            Model.resetLiveStats();
            Live.reset();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        WatchUi.requestUpdate();
    }

    function onClosed(ok as Boolean, msg as String) as Void {
        view.status = ok ? (WatchUi.loadResource(Rez.Strings.Closed) as String) : msg;
        if (ok) { Recording.vibrate(true); }
        WatchUi.requestUpdate();
    }
}
