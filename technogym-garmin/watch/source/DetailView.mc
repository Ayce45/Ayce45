import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Fiche d'un exercice : visuel Technogym (image de l'exercice ou de l'equipement), nom, equipement,
// muscles travailles, series. START = suivre cet exercice sur la page Exercice, UP / DOWN = image
// exercice / equipement, BACK = retour a la liste.
class DetailView extends WatchUi.View {

    var index as Number;
    var live as LiveView;
    var bitmap as WatchUi.BitmapResource or Graphics.BitmapReference or Null = null;
    var which as Number = 0;       // 0 = exercice, 1 = equipement
    var loading as Boolean = false;
    var failed as Boolean = false;

    function initialize(i as Number, lv as LiveView) {
        View.initialize();
        index = i;
        live = lv;
    }

    function onShow() as Void {
        loadImage();
    }

    function ex() as Dictionary? {
        return Live.exerciseAt(index);
    }

    function imageUrl() as String {
        var e = ex();
        if (e == null) { return ""; }
        var key = which == 1 ? "equipment_picture_url" : "picture_url";
        if (e.hasKey(key) && (e[key] as String).length() > 0) { return e[key] as String; }
        var other = which == 1 ? "picture_url" : "equipment_picture_url";
        return e.hasKey(other) ? e[other] as String : "";
    }

    function loadImage() as Void {
        var url = imageUrl();
        bitmap = null;
        failed = false;
        if (url.length() == 0 || !(Communications has :makeImageRequest)) { return; }
        var w = System.getDeviceSettings().screenWidth;
        var h = System.getDeviceSettings().screenHeight;
        loading = true;
        try {
            Communications.makeImageRequest(url, null, { :maxWidth => (w * 0.62).toNumber(), :maxHeight => (h * 0.42).toNumber() }, method(:onImage));
        } catch (e) {
            loading = false;
            failed = true;
        }
    }

    function onImage(code as Number, data as WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void {
        loading = false;
        if (code == 200 && data != null) {
            bitmap = data;
        } else {
            failed = true;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var e = ex();
        if (e == null) { return; }

        // visuel (ou cadre vide pendant le chargement)
        var imgTop = h * 0.08;
        var imgH = h * 0.42;
        if (bitmap != null) {
            var bm = bitmap;
            var bw = (bm as WatchUi.BitmapResource).getWidth();
            var bh = (bm as WatchUi.BitmapResource).getHeight();
            dc.drawBitmap(cx - bw / 2, imgTop + (imgH - bh) / 2, bm);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(cx - w * 0.31, imgTop, w * 0.62, imgH, 8);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, imgTop + imgH / 2, Graphics.FONT_XTINY, loading ? "..." : (failed ? "Visuel indisponible" : ""), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        // etat en haut a gauche du visuel
        Icons.status(dc, w * 0.14, imgTop + 8, 6, e, index == Live.currentIndex());

        var y = imgTop + imgH + h * 0.02;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        y += Ui.drawWrapped(dc, cx, y, w * 0.86, Graphics.FONT_SMALL, Live.headline(e), 1);
        if (!Live.title(e).equals(Live.headline(e))) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            y += Ui.drawWrapped(dc, cx, y, w * 0.86, Graphics.FONT_XTINY, Live.title(e), 1);
        }
        var eq = "";
        var muscles = "";
        if (e.hasKey("muscles")) {
            var ms = e["muscles"] as Array;
            for (var i = 0; i < ms.size() && i < 3; i++) { muscles += (i > 0 ? ", " : "") + (ms[i] as String); }
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (which == 1 && eq.length() > 0) {
            y += Ui.drawWrapped(dc, cx, y, w * 0.80, Graphics.FONT_XTINY, eq, 1);
        } else if (muscles.length() > 0) {
            y += Ui.drawWrapped(dc, cx, y, w * 0.80, Graphics.FONT_XTINY, muscles, 1);
        } else if (eq.length() > 0) {
            y += Ui.drawWrapped(dc, cx, y, w * 0.80, Graphics.FONT_XTINY, eq, 1);
        }
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, y, w * 0.70, Graphics.FONT_SMALL, Live.setsText(e), 1);
    }
}

class DetailDelegate extends WatchUi.BehaviorDelegate {

    var view as DetailView;

    function initialize(v as DetailView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onNextPage() as Boolean {
        view.which = (view.which + 1) % 2;
        view.loadImage();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        return onNextPage();
    }

    // START : suivre cet exercice sur la page Exercice
    function onSelect() as Boolean {
        view.live.cursor = view.index == Live.currentIndex() ? -1 : view.index;
        view.live.page = 0;
        WatchUi.popView(WatchUi.SLIDE_DOWN);   // fiche (la liste s'est deja retiree en ouvrant la fiche)
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
