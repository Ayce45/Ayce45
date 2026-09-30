import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Etat global de l'application : seance, progression, resultats, cache.
//
// Cles de stockage (Application.Storage) :
//   "workout"        seance telechargee (format GET /workout/today, champs nuls omis)
//   "workoutFetched" horodatage du telechargement
//   "session"        seance en cours (index exercice / serie + resultats), pour reprise apres arret
//   "pending"        resultats sauves localement mais pas encore envoyes au backend
module Model {

    var workout as Dictionary? = null;        // seance courante
    var fetchedAt as Number = 0;              // epoch s
    var lastError as String = "";
    var online as Boolean = false;

    // progression
    var exIndex as Number = 0;
    var setIndex as Number = 0;
    var results as Array = [];                // [{"position"=>..,"name"=>..,"sets"=>[{reps,weight_kg,duration_s,rest_s,skipped}]}]
    var undoStack as Array = [];              // [[exIndex, setIndex]] pour annuler
    var startedAt as Number = 0;
    var inProgress as Boolean = false;
    var liveMode as Boolean = false;          // activite live en cours (ecran LiveView)

    // reglages
    var backendUrl as String = "";
    var discoveryUrl as String = "";
    var pairToken as String = "";
    var autoStartRest as Boolean = true;
    var vibrateOnRestEnd as Boolean = true;
    var weightStep as Float = 2.5;

    function reloadSettings() as Void {
        backendUrl = _prop("backendUrl", "") as String;
        discoveryUrl = _prop("discoveryUrl", "") as String;
        pairToken = _prop("pairToken", "") as String;
        autoStartRest = _prop("autoStartRest", true) as Boolean;
        vibrateOnRestEnd = _prop("vibrateOnRestEnd", true) as Boolean;
        var ws = _prop("weightStepKg", 2.5);
        weightStep = (ws instanceof Number) ? (ws as Number).toFloat() : ((ws instanceof Float) ? ws as Float : 2.5);
        if (backendUrl.length() > 0 && backendUrl.substring(backendUrl.length() - 1, backendUrl.length()).equals("/")) {
            backendUrl = backendUrl.substring(0, backendUrl.length() - 1);
        }
    }

    function _prop(key as String, dflt as Object) as Object? {
        var v = null;
        try {
            v = Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        return (v == null) ? dflt : v;
    }

    function load() as Void {
        reloadSettings();
        var w = Storage.getValue("workout");
        if (w instanceof Dictionary) {
            workout = w as Dictionary;
        }
        var f = Storage.getValue("workoutFetched");
        if (f instanceof Number) { fetchedAt = f as Number; }
        var s = Storage.getValue("session");
        if (s instanceof Dictionary) {
            var sd = s as Dictionary;
            if (sd.hasKey("results") && sd["results"] instanceof Array) {
                results = sd["results"] as Array;
                exIndex = sd.hasKey("exIndex") ? sd["exIndex"] as Number : 0;
                setIndex = sd.hasKey("setIndex") ? sd["setIndex"] as Number : 0;
                startedAt = sd.hasKey("startedAt") ? sd["startedAt"] as Number : 0;
                inProgress = sd.hasKey("inProgress") ? sd["inProgress"] as Boolean : false;
            }
        }
    }

    function setWorkout(w as Dictionary) as Void {
        var changed = (workout == null) || !(workout as Dictionary).hasKey("id") || !(w.hasKey("id") && (w["id"] as String).equals((workout as Dictionary)["id"] as String));
        workout = w;
        fetchedAt = Time.now().value();
        Storage.setValue("workout", w);
        Storage.setValue("workoutFetched", fetchedAt);
        if (changed && !inProgress) {
            resetProgress();
        }
    }

    function hasWorkout() as Boolean {
        return workout != null && (workout as Dictionary).hasKey("exercises") && ((workout as Dictionary)["exercises"] as Array).size() > 0;
    }

    function exercises() as Array {
        if (!hasWorkout()) { return []; }
        return (workout as Dictionary)["exercises"] as Array;
    }

    function exerciseCount() as Number {
        return exercises().size();
    }

    function exercise(i as Number) as Dictionary? {
        var ex = exercises();
        if (i < 0 || i >= ex.size()) { return null; }
        return ex[i] as Dictionary;
    }

    function currentExercise() as Dictionary? {
        return exercise(exIndex);
    }

    function setsOf(ex as Dictionary?) as Array {
        if (ex == null || !ex.hasKey("sets")) { return []; }
        return ex["sets"] as Array;
    }

    function currentSet() as Dictionary? {
        var sets = setsOf(currentExercise());
        if (setIndex < 0 || setIndex >= sets.size()) { return null; }
        return sets[setIndex] as Dictionary;
    }

    function exerciseKind(ex as Dictionary?) as String {
        if (ex == null || !ex.hasKey("kind")) { return "strength"; }
        return ex["kind"] as String;
    }

    function exerciseTitle(ex as Dictionary?) as String {
        if (ex == null) { return ""; }
        if (ex.hasKey("short_name") && (ex["short_name"] as String).length() > 0) { return ex["short_name"] as String; }
        return ex.hasKey("name") ? ex["name"] as String : "";
    }

    function num(d as Dictionary?, key as String, dflt as Numeric) as Numeric {
        if (d == null || !d.hasKey(key) || d[key] == null) { return dflt; }
        var v = d[key];
        if (v instanceof Number || v instanceof Float || v instanceof Long || v instanceof Double) { return v as Numeric; }
        return dflt;
    }

    // ------------------------------------------------------------------ progression
    function resetProgress() as Void {
        exIndex = 0;
        setIndex = 0;
        results = [];
        undoStack = [];
        startedAt = 0;
        inProgress = false;
        Storage.deleteValue("session");
    }

    function startSession() as Void {
        if (!inProgress) {
            resetProgress();
            startedAt = Time.now().value();
            inProgress = true;
        }
        persistSession();
    }

    function persistSession() as Void {
        if (!inProgress) { return; }
        Storage.setValue("session", {
            "exIndex" => exIndex, "setIndex" => setIndex, "results" => results,
            "startedAt" => startedAt, "inProgress" => inProgress
        });
    }

    function _resultFor(ex as Dictionary) as Dictionary {
        var pos = num(ex, "position", 0);
        for (var i = 0; i < results.size(); i++) {
            var r = results[i] as Dictionary;
            if ((r["position"] as Number) == pos) { return r; }
        }
        var r = {
            "position" => pos,
            "name" => ex.hasKey("name") ? ex["name"] : "",
            "physical_activity_id" => ex.hasKey("physical_activity_id") ? ex["physical_activity_id"] : "",
            "sets" => []
        };
        results.add(r);
        return r;
    }

    // Enregistre la serie courante puis avance. Retourne true si la seance est finie.
    function recordSet(reps as Number?, weight as Float?, duration as Number?, skipped as Boolean) as Boolean {
        var ex = currentExercise();
        if (ex == null) { return true; }
        var target = currentSet();
        var entry = {} as Dictionary;
        if (reps != null) { entry["reps"] = reps; }
        if (weight != null) { entry["weight_kg"] = weight; }
        if (duration != null) { entry["duration_s"] = duration; }
        if (target != null && target.hasKey("rest_s")) { entry["rest_s"] = target["rest_s"]; }
        if (skipped) { entry["skipped"] = true; }
        entry["completed_at"] = Time.now().value();
        (_resultFor(ex)["sets"] as Array).add(entry);
        undoStack.add([exIndex, setIndex]);
        return advance();
    }

    // Passe a la serie suivante (ou exercice suivant). Retourne true si fin de seance.
    function advance() as Boolean {
        var sets = setsOf(currentExercise());
        setIndex++;
        if (setIndex >= sets.size() || sets.size() == 0) {
            setIndex = 0;
            exIndex++;
        }
        persistSession();
        return exIndex >= exerciseCount();
    }

    function skipExercise() as Boolean {
        var ex = currentExercise();
        if (ex != null) {
            var sets = setsOf(ex);
            for (var i = setIndex; i < sets.size(); i++) {
                (_resultFor(ex)["sets"] as Array).add({"skipped" => true});
            }
        }
        setIndex = 0;
        exIndex++;
        persistSession();
        return exIndex >= exerciseCount();
    }

    function jumpTo(i as Number) as Void {
        if (i >= 0 && i < exerciseCount()) {
            exIndex = i;
            setIndex = 0;
            persistSession();
        }
    }

    function undoLast() as Boolean {
        if (undoStack.size() == 0) { return false; }
        var last = undoStack[undoStack.size() - 1] as Array;
        undoStack = undoStack.slice(0, undoStack.size() - 1);
        exIndex = last[0] as Number;
        setIndex = last[1] as Number;
        var ex = currentExercise();
        if (ex != null) {
            var sets = _resultFor(ex)["sets"] as Array;
            if (sets.size() > 0) {
                _resultFor(ex)["sets"] = sets.slice(0, sets.size() - 1);
            }
        }
        persistSession();
        return true;
    }

    function isLastSet() as Boolean {
        var sets = setsOf(currentExercise());
        return (exIndex >= exerciseCount() - 1) && (setIndex >= sets.size() - 1);
    }

    function doneSetsCount() as Number {
        var n = 0;
        for (var i = 0; i < results.size(); i++) {
            var sets = (results[i] as Dictionary)["sets"] as Array;
            for (var j = 0; j < sets.size(); j++) {
                var s = sets[j] as Dictionary;
                if (!(s.hasKey("skipped") && s["skipped"] == true)) { n++; }
            }
        }
        return n;
    }

    function totalVolumeKg() as Float {
        var v = 0.0;
        for (var i = 0; i < results.size(); i++) {
            var sets = (results[i] as Dictionary)["sets"] as Array;
            for (var j = 0; j < sets.size(); j++) {
                var s = sets[j] as Dictionary;
                if (s.hasKey("reps") && s.hasKey("weight_kg")) {
                    v += (s["reps"] as Number) * (num(s, "weight_kg", 0.0) as Numeric).toFloat();
                }
            }
        }
        return v;
    }

    function exerciseDone(i as Number) as Boolean {
        var ex = exercise(i);
        if (ex == null) { return false; }
        var pos = num(ex, "position", 0);
        for (var k = 0; k < results.size(); k++) {
            var r = results[k] as Dictionary;
            if ((r["position"] as Number) == pos) {
                return (r["sets"] as Array).size() >= setsOf(ex).size();
            }
        }
        return false;
    }

    // ------------------------------------------------------------------ live (machines -> montre)
    var live as Dictionary? = null;          // reponse GET /workout/{id}/live
    var liveAt as Number = 0;

    // Fusionne l'etat des machines. Retourne true si un exercice vient d'etre marque fait par une machine.
    function applyLive(data as Dictionary) as Boolean {
        var before = machineDoneCount();
        live = data;
        liveAt = Time.now().value();
        return machineDoneCount() > before;
    }

    function liveExercise(position as Number) as Dictionary? {
        if (live == null || !(live as Dictionary).hasKey("exercises")) { return null; }
        var exs = (live as Dictionary)["exercises"] as Array;
        for (var i = 0; i < exs.size(); i++) {
            var e = exs[i] as Dictionary;
            if (num(e, "position", -1) == position) { return e; }
        }
        return null;
    }

    function machineDone(ex as Dictionary?) as Boolean {
        if (ex == null) { return false; }
        var le = liveExercise(num(ex, "position", -1).toNumber());
        return le != null && le.hasKey("status") && (le["status"] as String).equals("done");
    }

    function machineDoneCount() as Number {
        var n = 0;
        var exs = exercises();
        for (var i = 0; i < exs.size(); i++) {
            if (machineDone(exs[i] as Dictionary)) { n++; }
        }
        return n;
    }

    // Texte court des series enregistrees par la machine ("10x80 10x80 10x80").
    function machineSetsText(ex as Dictionary?) as String {
        if (ex == null) { return ""; }
        var le = liveExercise(num(ex, "position", -1).toNumber());
        if (le == null || !le.hasKey("sets")) { return ""; }
        var sets = le["sets"] as Array;
        var out = "";
        for (var i = 0; i < sets.size() && i < 6; i++) {
            var st = sets[i] as Dictionary;
            var part = "";
            if (st.hasKey("reps")) { part = st["reps"].toString(); }
            if (st.hasKey("weight_kg")) { part += "x" + num(st, "weight_kg", 0).toNumber(); }
            if (part.length() == 0 && st.hasKey("duration_s")) { part = st["duration_s"].toString() + "s"; }
            if (part.length() > 0) { out += (out.length() > 0 ? " " : "") + part; }
        }
        return out;
    }

    // Copie les series machine de l'exercice courant dans les resultats (source machine) et avance.
    function acceptMachineExercise() as Boolean {
        var ex = currentExercise();
        if (ex == null) { return true; }
        var le = liveExercise(num(ex, "position", -1).toNumber());
        var r = _resultFor(ex);
        var sets = [] as Array;
        if (le != null && le.hasKey("sets")) {
            var ls = le["sets"] as Array;
            for (var i = 0; i < ls.size(); i++) {
                var st = ls[i] as Dictionary;
                var entry = {"source" => "machine"} as Dictionary;
                if (st.hasKey("reps")) { entry["reps"] = st["reps"]; }
                if (st.hasKey("weight_kg")) { entry["weight_kg"] = st["weight_kg"]; }
                if (st.hasKey("duration_s")) { entry["duration_s"] = st["duration_s"]; }
                sets.add(entry);
            }
        }
        r["sets"] = sets;
        r["source"] = "machine";
        setIndex = 0;
        exIndex++;
        persistSession();
        return exIndex >= exerciseCount();
    }

    // ------------------------------------------------------------------ resultats
    function buildResultsPayload(fitSaved as Boolean) as Dictionary {
        var w = workout as Dictionary;
        return {
            "workout_id" => w.hasKey("id") ? w["id"] : "",
            "date" => w.hasKey("date") ? w["date"] : todayIso(),
            "device" => deviceName(),
            "started_at" => startedAt,
            "finished_at" => Time.now().value(),
            "fit_saved" => fitSaved,
            "exercises" => results
        };
    }

    function queuePending(payload as Dictionary) as Void {
        var pending = Storage.getValue("pending");
        var arr = (pending instanceof Array) ? pending as Array : [];
        arr.add(payload);
        // on garde au plus 5 seances en attente
        if (arr.size() > 5) { arr = arr.slice(arr.size() - 5, arr.size()); }
        Storage.setValue("pending", arr);
    }

    function pendingCount() as Number {
        var pending = Storage.getValue("pending");
        return (pending instanceof Array) ? (pending as Array).size() : 0;
    }

    function popPending() as Dictionary? {
        var pending = Storage.getValue("pending");
        if (!(pending instanceof Array) || (pending as Array).size() == 0) { return null; }
        var arr = pending as Array;
        var first = arr[0] as Dictionary;
        arr = arr.slice(1, arr.size());
        Storage.setValue("pending", arr);
        return first;
    }

    function pushBackPending(p as Dictionary) as Void {
        var pending = Storage.getValue("pending");
        var arr = (pending instanceof Array) ? pending as Array : [];
        var merged = [p];
        merged.addAll(arr);
        Storage.setValue("pending", merged);
    }

    function todayIso() as String {
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$", [(g.year as Number).format("%04d"), (g.month as Number).format("%02d"), (g.day as Number).format("%02d")]);
    }

    function deviceName() as String {
        var s = System.getDeviceSettings();
        if (s has :partNumber && s.partNumber != null) { return "garmin-" + s.partNumber; }
        return "garmin";
    }

    function workoutTitle() as String {
        if (workout == null) { return ""; }
        var w = workout as Dictionary;
        return w.hasKey("name") ? w["name"] as String : "";
    }

    function workoutDate() as String {
        if (workout == null) { return ""; }
        var w = workout as Dictionary;
        return w.hasKey("date") ? w["date"] as String : "";
    }
}
