import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;

// Compteur de repetitions par accelerometre (25 Hz, blocs d'une seconde via Sensor.registerSensorDataListener).
// Meme algorithme que tools/reps/repcounter2.py (reference Python, evaluee sur le jeu MM-Fit, voir
// tools/reps/README.md pour les chiffres) :
//   - gravite retiree par un passe-haut lent, lissage passe-bas, par axe ;
//   - cycles pic / creux avec hysteresis adaptative, duree min 0,8 s, max 8 s, filtrage des demi-cycles ;
//   - trois detecteurs (un par axe), l'axe retenu est celui aux cycles les plus reguliers (independant de
//     l'orientation de la montre) ;
//   - a la fin de la serie, le cycle entame compte pour une repetition.
// Inspire de RecoFit (Morris & Saponas, CHI 2014).
module RepCounter {

    const RATE = 25;
    const MIN_PERIOD = 0.8;
    const MAX_PERIOD = 8.0;
    const GRAVITY_TAU = 1.5;
    const SMOOTH_TAU = 0.4;
    const MIN_AMPLITUDE = 80.0;
    const HYSTERESIS = 0.5;
    const PERIOD_GATE = 0.5;
    const MAX_DTS = 12;
    const WARMUP = 2;            // cycles reguliers consecutifs avant de compter (anti faux departs)

    var active as Boolean = false;
    var onRep as Method? = null;   // callback(reps as Number)
    var best as Number = 0;

    // etat par axe (tableaux de 3)
    var _g as Array<Float> = [0.0, 0.0, 0.0] as Array<Float>;
    var _lp as Array<Float> = [0.0, 0.0, 0.0] as Array<Float>;
    var _state as Array<Number> = [0, 0, 0] as Array<Number>;
    var _peak as Array<Float> = [0.0, 0.0, 0.0] as Array<Float>;
    var _valley as Array<Float> = [0.0, 0.0, 0.0] as Array<Float>;
    var _amp as Array<Float> = [0.0, 0.0, 0.0] as Array<Float>;
    var _period as Array<Float> = [0.0, 0.0, 0.0] as Array<Float>;
    var _lastT as Array<Float> = [-1000000.0, -1000000.0, -1000000.0] as Array<Float>;
    var _reps as Array<Number> = [0, 0, 0] as Array<Number>;
    var _armed as Array<Boolean> = [false, false, false] as Array<Boolean>;
    var _cand as Array<Number> = [0, 0, 0] as Array<Number>;
    var _dts as Array<Array<Float>> = [[] as Array<Float>, [] as Array<Float>, [] as Array<Float>] as Array<Array<Float>>;
    var _n as Number = 0;
    var _ag as Float = 0.0;
    var _al as Float = 0.0;

    function supported() as Boolean {
        return (Toybox has :Sensor) && (Sensor has :registerSensorDataListener);
    }

    function start(callback as Method?) as Boolean {
        if (!supported()) { return false; }
        reset();
        onRep = callback;
        _ag = 1.0 / (1.0 + GRAVITY_TAU * RATE);
        _al = 1.0 / (1.0 + SMOOTH_TAU * RATE);
        try {
            Sensor.registerSensorDataListener(new Lang.Method(RepCounter, :onData), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => RATE }
            });
            active = true;
        } catch (e) {
            active = false;
        }
        return active;
    }

    function stop() as Void {
        if (!active) { return; }
        try {
            Sensor.unregisterSensorDataListener();
        } catch (e) {
        }
        active = false;
        onRep = null;
    }

    function reset() as Void {
        for (var i = 0; i < 3; i++) {
            _g[i] = 0.0; _lp[i] = 0.0; _state[i] = 0; _peak[i] = 0.0; _valley[i] = 0.0;
            _amp[i] = 0.0; _period[i] = 0.0; _lastT[i] = -1000000.0; _reps[i] = 0;
            _armed[i] = WARMUP == 0; _cand[i] = 0;
            _dts[i] = [] as Array<Float>;
        }
        _n = 0;
        best = 0;
    }

    // Repetitions de l'axe retenu.
    function reps() as Number {
        return _reps[best];
    }

    // A la fin de la serie : le cycle entame mais pas referme compte pour une repetition.
    function finalReps() as Number {
        var i = best;
        var thr = HYSTERESIS * _amp[i];
        if (thr < MIN_AMPLITUDE) { thr = MIN_AMPLITUDE; }
        var pending = (_armed[i] && _state[i] == 1 && _peak[i] - _valley[i] > thr) ? 1 : 0;
        return _reps[i] + pending;
    }

    function _regularity(i as Number) as Number {
        var d = _dts[i];
        if (d.size() < 2) { return d.size(); }
        // mediane par tri simple (12 valeurs max)
        var s = [] as Array<Float>;
        for (var k = 0; k < d.size(); k++) { s.add(d[k]); }
        for (var a = 1; a < s.size(); a++) {
            var v = s[a]; var b = a - 1;
            while (b >= 0 && s[b] > v) { s[b + 1] = s[b]; b--; }
            s[b + 1] = v;
        }
        var med = s[s.size() / 2];
        var n = 0;
        for (var k = 0; k < d.size(); k++) {
            var diff = d[k] - med;
            if (diff < 0) { diff = -diff; }
            if (diff <= 0.35 * med) { n++; }
        }
        return n;
    }

    function _push(i as Number, m as Float, t as Float) as Void {
        _lp[i] += _al * (m - _lp[i]);
        var v = _lp[i];
        var thr = HYSTERESIS * _amp[i];
        if (thr < MIN_AMPLITUDE) { thr = MIN_AMPLITUDE; }
        if (_state[i] == 0) {
            if (v > _peak[i]) { _peak[i] = v; }
            if (_peak[i] - v > thr * 0.5 && _peak[i] > _valley[i] + thr) {
                _state[i] = 1;
                _valley[i] = v;
            }
        } else {
            if (v < _valley[i]) { _valley[i] = v; }
            if (v - _valley[i] > thr * 0.5 && _peak[i] - _valley[i] > thr) {
                var dt = t - _lastT[i];
                var amp = _peak[i] - _valley[i];
                var gated = _period[i] > 0 && dt < PERIOD_GATE * _period[i];
                if (dt >= MIN_PERIOD && !gated) {
                    if (dt <= MAX_PERIOD || _lastT[i] < 0) {
                        if (_armed[i]) {
                            _reps[i]++;
                        } else {
                            // chauffe : WARMUP cycles consecutifs de periode coherente, puis on compte retroactivement
                            var diff = dt - _period[i];
                            if (diff < 0) { diff = -diff; }
                            var ok = _lastT[i] > 0 && dt <= MAX_PERIOD && (_period[i] == 0.0 || diff <= 0.5 * _period[i]);
                            _cand[i] = (ok || _lastT[i] < 0) ? _cand[i] + 1 : 1;
                            if (_cand[i] >= WARMUP) {
                                _armed[i] = true;
                                _reps[i] = _cand[i];
                            }
                        }
                        if (_lastT[i] > 0 && dt <= MAX_PERIOD) {
                            _dts[i].add(dt);
                            if (_dts[i].size() > MAX_DTS) { _dts[i] = _dts[i].slice(1, null); }
                            _period[i] = (_period[i] == 0.0) ? dt : 0.6 * _period[i] + 0.4 * dt;
                        }
                    } else if (!_armed[i]) {
                        _cand[i] = 0;   // long silence pendant la chauffe : on repart
                    }
                    _amp[i] = (_amp[i] == 0.0) ? amp : 0.7 * _amp[i] + 0.3 * amp;
                    _lastT[i] = t;
                }
                _state[i] = 0;
                _peak[i] = v;
            }
        }
    }

    function onData(data as Sensor.SensorData) as Void {
        var acc = data.accelerometerData;
        if (acc == null) { return; }
        var xs = acc.x;
        var ys = acc.y;
        var zs = acc.z;
        var before = reps();
        for (var k = 0; k < xs.size(); k++) {
            _n++;
            var t = _n.toFloat() / RATE;
            var raw = [xs[k].toFloat(), ys[k].toFloat(), zs[k].toFloat()] as Array<Float>;
            if (_n == 1) { _g = [raw[0], raw[1], raw[2]] as Array<Float>; }
            for (var i = 0; i < 3; i++) {
                _g[i] += _ag * (raw[i] - _g[i]);
                _push(i, raw[i] - _g[i], t);
            }
        }
        // axe retenu : regularite des cycles puis amplitude
        var bi = 0;
        var br = _regularity(0);
        for (var i = 1; i < 3; i++) {
            var r = _regularity(i);
            if (r > br || (r == br && _amp[i] > _amp[bi])) { bi = i; br = r; }
        }
        best = bi;
        if (reps() != before && onRep != null) { (onRep as Method).invoke(reps()); }
    }
}
