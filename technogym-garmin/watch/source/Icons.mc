import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.UserProfile;

// Icones dessinees en primitives (pas de bitmap : nettes a toutes les tailles, colorables).
// Reprend les codes visuels des activites Garmin : coeur pour la FC, coche verte = fait,
// triangle orange = en cours, cercle gris = a faire, ondes = equipement connecte.
module Icons {

    function heart(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var lobe = (r * 0.52).toNumber();
        if (lobe < 2) { lobe = 2; }
        dc.fillCircle(cx - r * 0.45, cy - r * 0.3, lobe);
        dc.fillCircle(cx + r * 0.45, cy - r * 0.3, lobe);
        dc.fillPolygon([[cx - r * 0.95, cy - r * 0.1], [cx + r * 0.95, cy - r * 0.1], [cx, cy + r]] as Array<[Numeric, Numeric]>);
    }

    function check(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(r >= 8 ? 3 : 2);
        dc.drawLine(cx - r, cy, cx - r * 0.3, cy + r * 0.7);
        dc.drawLine(cx - r * 0.3, cy + r * 0.7, cx + r, cy - r * 0.7);
        dc.setPenWidth(1);
    }

    function play(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - r * 0.7, cy - r], [cx - r * 0.7, cy + r], [cx + r, cy]] as Array<[Numeric, Numeric]>);
    }

    function circle(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, r);
        dc.setPenWidth(1);
    }

    // Equipement connecte : point + deux ondes (comme l'icone de capteur Garmin).
    function link(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy + r * 0.5, r >= 8 ? 3 : 2);
        dc.setPenWidth(2);
        dc.drawArc(cx, cy + r * 0.5, r * 0.6, Graphics.ARC_COUNTER_CLOCKWISE, 40, 140);
        dc.drawArc(cx, cy + r * 0.5, r * 1.1, Graphics.ARC_COUNTER_CLOCKWISE, 40, 140);
        dc.setPenWidth(1);
    }

    function stopwatch(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy + 1, r);
        dc.drawLine(cx, cy + 1, cx, cy + 1 - r * 0.6);
        dc.drawLine(cx, cy + 1, cx + r * 0.4, cy + 1);
        dc.drawLine(cx - 2, cy - r, cx + 3, cy - r);
        dc.setPenWidth(1);
    }

    // Icone d'etat d'un exercice live.
    function status(dc as Dc, cx as Numeric, cy as Numeric, r as Numeric, ex as Dictionary?, current as Boolean) as Void {
        var st = Live.status(ex);
        if (st.equals("done")) {
            check(dc, cx, cy, r, Graphics.COLOR_GREEN);
        } else if (st.equals("doing") || current) {
            play(dc, cx, cy, r, Graphics.COLOR_ORANGE);
        } else {
            circle(dc, cx, cy, r * 0.8, Graphics.COLOR_LT_GRAY);
        }
    }

    // Couleur de zone cardiaque, comme les jauges Garmin (gris sous la zone 1, bleu, vert, orange, rouge).
    var _zones as Array<Number>? = null;

    function zones() as Array<Number> {
        if (_zones == null) {
            var z = null;
            try {
                z = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            } catch (e) {
                z = null;
            }
            if (z == null || (z as Array).size() < 6) { z = [93, 111, 130, 148, 167, 185]; }
            _zones = z as Array<Number>;
        }
        return _zones as Array<Number>;
    }

    function hrZone(hr as Number?) as Number {
        if (hr == null || hr <= 0) { return 0; }
        var z = zones();
        var n = 0;
        for (var i = 0; i < 5; i++) {
            if (hr >= z[i]) { n = i + 1; }
        }
        return n;
    }

    function zoneColor(zone as Number) as ColorType {
        if (zone <= 0) { return Graphics.COLOR_LT_GRAY; }
        if (zone == 1) { return Graphics.COLOR_LT_GRAY; }
        if (zone == 2) { return Graphics.COLOR_BLUE; }
        if (zone == 3) { return Graphics.COLOR_GREEN; }
        if (zone == 4) { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_RED;
    }

    // Jauge de zones a 5 segments (largeur totale w), segment courant plein.
    function zoneBar(dc as Dc, x as Numeric, y as Numeric, w as Numeric, hgt as Numeric, zone as Number) as Void {
        var gap = 2;
        var seg = (w - gap * 4) / 5;
        for (var i = 1; i <= 5; i++) {
            dc.setColor(i == zone ? zoneColor(i) : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x + (i - 1) * (seg + gap), y, seg, hgt, 2);
        }
    }
}

// Icone d'etat utilisable dans un Menu2 (IconMenuItem).
class StatusIconDrawable extends WatchUi.Drawable {

    var ex as Dictionary?;
    var current as Boolean;

    function initialize(e as Dictionary?, cur as Boolean) {
        Drawable.initialize({});
        ex = e;
        current = cur;
    }

    function draw(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var r = (w < h ? w : h) * 0.28;
        Icons.status(dc, w / 2, h / 2, r, ex, current);
        if (ex != null && !Live.isDone(ex) && (ex as Dictionary).hasKey("device") && ((ex as Dictionary)["device"] as String).equals("FullConnected")) {
            Icons.link(dc, w / 2 + r * 1.2, h / 2 - r * 0.9, r * 0.45, Graphics.COLOR_GREEN);
        }
    }
}
