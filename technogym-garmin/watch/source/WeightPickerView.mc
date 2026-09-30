import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Reglage de la charge pendant une serie : UP / DOWN par pas (reglage weightStepKg), START = valider et
// memoriser pour cet exercice, BACK = annuler. Affiche les disques par cote pour une barre (reglage barKg)
// quand la charge depasse le poids de la barre : 20, 15, 10, 5, 2.5, 1.25 kg.
class WeightPickerView extends WatchUi.View {

    var kg as Float;
    var onDone as Method;   // callback(kg as Float)
    var title as String;

    function initialize(start as Float, label as String, done as Method) {
        View.initialize();
        kg = start;
        title = label;
        onDone = done;
    }

    function plates() as String {
        var bar = Model.barKg;
        if (kg <= bar + 0.01) { return ""; }
        var side = (kg - bar) / 2.0;
        var sizes = [20.0, 15.0, 10.0, 5.0, 2.5, 1.25] as Array<Float>;
        var out = "";
        for (var i = 0; i < sizes.size(); i++) {
            var n = 0;
            while (side >= sizes[i] - 0.001) { side -= sizes[i]; n++; }
            if (n > 0) { out += (out.length() > 0 ? " + " : "") + (n > 1 ? n + "x" : "") + Ui.fmtKg(sizes[i]); }
        }
        if (side > 0.01) { out += " (+" + Ui.fmtKg(side) + ")"; }
        return out;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var small = w < 300;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        Ui.drawWrapped(dc, cx, h * 0.08, w * 0.7, Graphics.FONT_XTINY, title, 1);
        dc.drawText(cx, h * 0.22, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Weight) as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        var f = small ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_THAI_HOT;
        var txt = Ui.fmtKg(kg);
        var tw = dc.getTextWidthInPixels(txt, f);
        dc.drawText(cx - w * 0.05, h * 0.42, f, txt, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w * 0.05 + tw / 2 + 4, h * 0.46, Graphics.FONT_XTINY, "kg", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var pl = plates();
        if (pl.length() > 0) {
            dc.drawText(cx, h * 0.62, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Plates) as String + " (" + (WatchUi.loadResource(Rez.Strings.Bar) as String) + " " + Ui.fmtKg(Model.barKg) + ")", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            Ui.drawWrapped(dc, cx, h * 0.68, w * 0.80, Graphics.FONT_SMALL, pl, 1);
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.83, Graphics.FONT_XTINY, "±" + Ui.fmtKg(Model.weightStep) + " · START : OK", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class WeightPickerDelegate extends WatchUi.BehaviorDelegate {

    var view as WeightPickerView;

    function initialize(v as WeightPickerView) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onPreviousPage() as Boolean { view.kg += Model.weightStep; WatchUi.requestUpdate(); return true; }
    function onNextPage() as Boolean { view.kg -= Model.weightStep; if (view.kg < 0) { view.kg = 0.0; } WatchUi.requestUpdate(); return true; }

    function onSelect() as Boolean {
        view.onDone.invoke(view.kg);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
