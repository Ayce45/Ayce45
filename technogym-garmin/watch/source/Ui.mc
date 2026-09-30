import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Aides de dessin communes.
module Ui {

    // Dessine un texte sur plusieurs lignes (coupe aux espaces), centre en x.
    function drawWrapped(dc as Dc, cx as Numeric, y as Numeric, maxWidth as Numeric, font as FontDefinition, text as String, maxLines as Number) as Number {
        var words = splitWords(text);
        var lines = [] as Array<String>;
        var current = "";
        var truncated = false;
        for (var i = 0; i < words.size(); i++) {
            var candidate = current.length() == 0 ? words[i] : current + " " + words[i];
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth || current.length() == 0) {
                current = candidate;
            } else {
                lines.add(current);
                current = words[i];
                if (lines.size() >= maxLines) { truncated = true; break; }
            }
        }
        if (current.length() > 0 && lines.size() < maxLines) { lines.add(current); }
        var lh = dc.getFontHeight(font);
        for (var i = 0; i < lines.size(); i++) {
            var line = lines[i];
            if (i == lines.size() - 1 && (truncated || dc.getTextWidthInPixels(line, font) > maxWidth)) {
                // derniere ligne : on coupe et on signale la suite par des points de suspension
                var cut = truncated ? line + "..." : line;
                while (dc.getTextWidthInPixels(cut, font) > maxWidth && line.length() > 2) {
                    line = line.substring(0, line.length() - 1);
                    cut = line + "...";
                }
                line = cut;
            }
            dc.drawText(cx, y + i * lh, font, line, Graphics.TEXT_JUSTIFY_CENTER);
        }
        return lines.size() * lh;
    }

    function splitWords(text as String) as Array<String> {
        var out = [] as Array<String>;
        var s = text;
        while (true) {
            var idx = s.find(" ");
            if (idx == null) {
                if (s.length() > 0) { out.add(s); }
                break;
            }
            var i = idx as Number;
            if (i > 0) { out.add(s.substring(0, i)); }
            s = s.substring(i + 1, s.length());
        }
        return out;
    }

    function fmtKg(v as Numeric) as String {
        var f = v.toFloat();
        if (f == f.toNumber().toFloat()) { return f.toNumber().toString(); }
        return f.format("%.1f");
    }

    function fmtClock(sec as Number) as String {
        if (sec < 0) { sec = 0; }
        return Lang.format("$1$:$2$", [(sec / 60).format("%d"), (sec % 60).format("%02d")]);
    }

    // Barre de progression circulaire simple (arc) en bas de l'ecran.
    function drawProgressArc(dc as Dc, fraction as Float, color as ColorType) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var r = (w < h ? w : h) / 2 - 3;
        dc.setPenWidth(5);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(w / 2, h / 2, r, Graphics.ARC_CLOCKWISE, 90, 90 - 359);
        if (fraction > 0.0) {
            var f = fraction > 1.0 ? 1.0 : fraction;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(w / 2, h / 2, r, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * f).toNumber());
        }
        dc.setPenWidth(1);
    }
}
