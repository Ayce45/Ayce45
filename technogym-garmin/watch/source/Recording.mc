import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;
import Toybox.Attention;

// Enregistrement FIT : sport Training / Strength. Un lap par serie.
// Le SDK ne permet pas d'ecrire les messages FIT "Set" : les reps/charges partent au backend et,
// a titre indicatif, dans deux developer fields de lap (reps, charge).
module Recording {

    var session as ActivityRecording.Session? = null;
    var repsField as FitContributor.Field? = null;
    var weightField as FitContributor.Field? = null;
    var exerciseField as FitContributor.Field? = null;
    var saved as Boolean = false;

    function isRecording() as Boolean {
        return session != null && (session as ActivityRecording.Session).isRecording();
    }

    function start(name as String) as Boolean {
        if (session != null) { return true; }
        try {
            var s = ActivityRecording.createSession({
                :name => name.length() > 0 ? name : "Muscu",
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
            });
            session = s;
            try {
                repsField = s.createField("reps", 0, FitContributor.DATA_TYPE_UINT16, { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "reps" });
                weightField = s.createField("charge", 1, FitContributor.DATA_TYPE_FLOAT, { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "kg" });
                exerciseField = s.createField("exercice", 2, FitContributor.DATA_TYPE_UINT8, { :mesgType => FitContributor.MESG_TYPE_LAP });
            } catch (e) {
                repsField = null;
                weightField = null;
                exerciseField = null;
            }
            s.start();
            saved = false;
            return true;
        } catch (e) {
            session = null;
            return false;
        }
    }

    // Marque la fin d'une serie : renseigne les champs puis ajoute un lap.
    function lap(position as Number, reps as Number?, weight as Float?) as Void {
        if (session == null) { return; }
        var s = session as ActivityRecording.Session;
        try {
            if (repsField != null) { (repsField as FitContributor.Field).setData(reps == null ? 0 : reps); }
            if (weightField != null) { (weightField as FitContributor.Field).setData(weight == null ? 0.0 : weight); }
            if (exerciseField != null) { (exerciseField as FitContributor.Field).setData(position); }
            if (s.isRecording()) { s.addLap(); }
        } catch (e) {
        }
    }

    function pause() as Void {
        if (session != null && (session as ActivityRecording.Session).isRecording()) {
            (session as ActivityRecording.Session).stop();
        }
    }

    function resume() as Void {
        if (session != null && !(session as ActivityRecording.Session).isRecording()) {
            (session as ActivityRecording.Session).start();
        }
    }

    // Sauvegarde FIT-first : appelee AVANT toute tentative d'envoi reseau.
    function save() as Boolean {
        if (session == null) { return false; }
        var s = session as ActivityRecording.Session;
        try {
            if (s.isRecording()) { s.stop(); }
            s.save();
            saved = true;
        } catch (e) {
            saved = false;
        }
        session = null;
        return saved;
    }

    function discard() as Void {
        if (session == null) { return; }
        var s = session as ActivityRecording.Session;
        try {
            if (s.isRecording()) { s.stop(); }
            s.discard();
        } catch (e) {
        }
        session = null;
    }

    function vibrate(strong as Boolean) as Void {
        if (!Model.vibrateOnRestEnd) { return; }
        if (Attention has :vibrate) {
            var profile = strong
                ? [new Attention.VibeProfile(100, 400), new Attention.VibeProfile(0, 200), new Attention.VibeProfile(100, 400)]
                : [new Attention.VibeProfile(60, 250)];
            Attention.vibrate(profile);
        }
        if (Attention has :playTone) {
            try {
                Attention.playTone(strong ? Attention.TONE_ALERT_HI : Attention.TONE_KEY);
            } catch (e) {
            }
        }
    }
}
