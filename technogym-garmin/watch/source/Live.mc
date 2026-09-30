import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Mode live : la seance est pilotee depuis la salle (bornes, machines, app Technogym) ; la montre
// affiche ou on en est (GET /live, seance courante Technogym), enregistre une activite Musculation
// (capteur cardio actif, diffusion systeme possible) et remonte la frequence cardiaque au backend.
module Live {

    var state as Dictionary? = null;      // derniere reponse GET /live
    var stateAt as Number = 0;            // epoch s de la derniere reponse
    var lastError as String = "";
    var polls as Number = 0;

    // frequence cardiaque
    var hr as Number? = null;             // derniere valeur du capteur
    var hrBuffer as Array = [];           // [[t, bpm], ...] en attente d'envoi
    var hrSent as Number = 0;             // echantillons acceptes par le backend
    var hrMax as Number = 0;
    var _hrSum as Number = 0;
    var _hrN as Number = 0;

    // suivi des changements pour vibrer / poser un lap quand une machine termine un exercice
    var _doneKnown as Dictionary = {} as Dictionary;   // position -> true
    var lastEvent as String = "";

    function hasSession() as Boolean {
        return state != null && (state as Dictionary).hasKey("has_current_workout")
            && ((state as Dictionary)["has_current_workout"] as Boolean);
    }

    function sessionName() as String {
        if (state == null) { return ""; }
        var s = state as Dictionary;
        var n = s.hasKey("name") ? (s["name"] as String) : "";
        return n.length() > 0 ? n : "Séance";
    }

    function exercises() as Array {
        if (state == null || !(state as Dictionary).hasKey("exercises")) { return [] as Array; }
        return (state as Dictionary)["exercises"] as Array;
    }

    function doneCount() as Number { return _num("done_count", 0); }

    // MOVEs (unite d'activite Technogym) deja gagnes sur la seance, d'apres doneMove des exercices faits.
    function movesDone() as Number {
        var exs = exercises();
        var n = 0;
        for (var i = 0; i < exs.size(); i++) {
            n += Model.num(exs[i] as Dictionary, "done_move", 0).toNumber();
        }
        return n;
    }
    function totalCount() as Number { return _num("total_count", 0); }

    function _num(key as String, dflt as Number) as Number {
        if (state == null || !(state as Dictionary).hasKey(key)) { return dflt; }
        var v = (state as Dictionary)[key];
        if (v instanceof Number) { return v as Number; }
        if (v instanceof Float) { return (v as Float).toNumber(); }
        return dflt;
    }

    // Index (dans exercises()) de l'exercice courant : "doing", sinon premier non fait.
    function currentIndex() as Number {
        var exs = exercises();
        var pos = _num("current_position", -1);
        for (var i = 0; i < exs.size(); i++) {
            if (Model.num(exs[i] as Dictionary, "position", -2) == pos) { return i; }
        }
        for (var i = 0; i < exs.size(); i++) {
            if (!isDone(exs[i] as Dictionary)) { return i; }
        }
        return exs.size() > 0 ? exs.size() - 1 : -1;
    }

    function exerciseAt(i as Number) as Dictionary? {
        var exs = exercises();
        if (i < 0 || i >= exs.size()) { return null; }
        return exs[i] as Dictionary;
    }

    function status(ex as Dictionary?) as String {
        if (ex == null || !ex.hasKey("status")) { return "todo"; }
        return ex["status"] as String;
    }

    function isDone(ex as Dictionary?) as Boolean { return status(ex).equals("done"); }

    function title(ex as Dictionary?) as String {
        if (ex == null) { return ""; }
        if (ex.hasKey("short_name") && (ex["short_name"] as String).length() > 0) { return ex["short_name"] as String; }
        if (ex.hasKey("name")) { return ex["name"] as String; }
        return "Exercice";
    }

    function equipment(ex as Dictionary?) as String {
        if (ex == null || !ex.hasKey("equipment")) { return ""; }
        return ex["equipment"] as String;
    }

    // "4 x 10 x 80 kg" / "10 min" / "3 x 30 s" a partir des series (faites si dispo, sinon prescrites).
    function setsText(ex as Dictionary?) as String {
        if (ex == null) { return ""; }
        var key = (isDone(ex) && ex.hasKey("sets") && (ex["sets"] as Array).size() > 0) ? "sets" : "target_sets";
        if (!ex.hasKey(key)) { return ""; }
        var sets = ex[key] as Array;
        if (sets.size() == 0) { return ""; }
        var s0 = sets[0] as Dictionary;
        var same = true;
        for (var i = 1; i < sets.size(); i++) {
            var si = sets[i] as Dictionary;
            if (Model.num(si, "reps", -1) != Model.num(s0, "reps", -1) || Model.num(si, "weight_kg", -1) != Model.num(s0, "weight_kg", -1)
                || Model.num(si, "duration_s", -1) != Model.num(s0, "duration_s", -1)) { same = false; }
        }
        if (same) {
            return sets.size() + " x " + oneSet(s0);
        }
        var out = "";
        for (var i = 0; i < sets.size() && i < 5; i++) {
            out += (i > 0 ? "  " : "") + oneSet(sets[i] as Dictionary);
        }
        return out;
    }

    function oneSet(st as Dictionary) as String {
        if (st.hasKey("reps")) {
            var t = st["reps"].toString();
            if (st.hasKey("weight_kg")) { t += " x " + Ui.fmtKg(Model.num(st, "weight_kg", 0)) + " kg"; }
            return t;
        }
        if (st.hasKey("duration_s")) {
            var d = Model.num(st, "duration_s", 0).toNumber();
            return d >= 120 ? (d / 60) + " min" : d + " s";
        }
        return "";
    }

    function sourceText(ex as Dictionary?) as String {
        if (ex == null) { return ""; }
        var dev = ex.hasKey("device") ? (ex["device"] as String) : "";
        if (isDone(ex)) {
            var src = ex.hasKey("source") ? (ex["source"] as String) : "";
            return src.equals("machine") ? "Terminé sur équipement" : "Terminé";
        }
        if (status(ex).equals("doing")) { return "En cours"; }
        return dev.equals("FullConnected") ? "Équipement connecté" : "À faire";
    }

    function elapsedSeconds() as Number {
        if (Model.startedAt > 0) { return Time.now().value() - Model.startedAt; }
        return 0;
    }

    // Applique une reponse GET /live. Retourne le nombre d'exercices nouvellement faits.
    function apply(data as Dictionary) as Number {
        polls++;
        var newlyDone = 0;
        var exs = data.hasKey("exercises") ? data["exercises"] as Array : [] as Array;
        for (var i = 0; i < exs.size(); i++) {
            var e = exs[i] as Dictionary;
            var pos = Model.num(e, "position", 0).toNumber();
            if (isDone(e) && !_doneKnown.hasKey(pos)) {
                _doneKnown[pos] = true;
                if (state != null) {
                    // pas au premier chargement : c'est un vrai evenement de la salle
                    newlyDone++;
                    lastEvent = title(e) + " : terminé";
                    var sets = e.hasKey("sets") ? (e["sets"] as Array) : [] as Array;
                    var reps = null;
                    var w = null;
                    if (sets.size() > 0) {
                        var s0 = sets[0] as Dictionary;
                        if (s0.hasKey("reps")) { reps = Model.num(s0, "reps", 0).toNumber(); }
                        if (s0.hasKey("weight_kg")) { w = Model.num(s0, "weight_kg", 0).toFloat(); }
                    }
                    Recording.lap(pos, reps, w);
                }
            }
        }
        var wasOpen = hasSession();
        state = data;
        stateAt = Time.now().value();
        lastError = "";
        if (!wasOpen && hasSession()) {
            lastEvent = "Séance démarrée";
            if (Model.startedAt == 0) { Model.startedAt = Time.now().value(); }
            if (newlyDone == 0 && state != null) { newlyDone = -1; } // signal "ouverture"
        }
        return newlyDone;
    }

    function reset() as Void {
        state = null;
        stateAt = 0;
        _doneKnown = {} as Dictionary;
        hrBuffer = [] as Array;
        hrSent = 0;
        hrMax = 0;
        _hrSum = 0;
        _hrN = 0;
        lastEvent = "";
        polls = 0;
    }

    // Lit le capteur du poignet (actif pendant l'enregistrement) ; appele chaque seconde.
    function sampleHr() as Void {
        var info = Activity.getActivityInfo();
        var v = (info != null) ? info.currentHeartRate : null;
        hr = v;
        if (v != null && v > 0) {
            var b = v as Number;
            if (b > hrMax) { hrMax = b; }
            _hrSum += b;
            _hrN++;
            hrBuffer.add([Time.now().value(), b]);
            if (hrBuffer.size() > 600) { hrBuffer = hrBuffer.slice(hrBuffer.size() - 600, null); }
        }
    }

    function hrAvg() as Number { return _hrN > 0 ? _hrSum / _hrN : 0; }

    // Vide le tampon vers le backend (POST /live/hr). Les echantillons sont remis en tampon en cas d'echec.
    function flushHr() as Boolean {
        if (hrBuffer.size() == 0 || !hasSession()) { return false; }
        var batch = hrBuffer;
        hrBuffer = [] as Array;
        var s = state as Dictionary;
        var payload = {
            "workout_id" => s.hasKey("workout_id") ? s["workout_id"] : "",
            "id_cr" => s.hasKey("id_cr") ? s["id_cr"] : null,
            "date" => s.hasKey("date") ? s["date"] : "",
            "samples" => batch
        } as Dictionary;
        if (!Net.sendHr(payload)) {
            hrBuffer = batch.addAll(hrBuffer);
            return false;
        }
        return true;
    }

    function hrFailed(batch as Dictionary) as Void {
        if (batch.hasKey("samples")) {
            var again = batch["samples"] as Array;
            if (again.size() + hrBuffer.size() <= 600) { hrBuffer = again.addAll(hrBuffer); }
        }
    }
}
