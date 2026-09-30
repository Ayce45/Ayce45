import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Reseau : passe par le telephone (Garmin Connect Mobile, BLE) via Communications.makeWebRequest.
// Le token d'appairage est envoye en en-tete X-Pair-Token et en query (?token=) par securite,
// certains firmwares filtrant les en-tetes personnalises.
module Net {

    var busy as Boolean = false;
    var onDone as Method? = null;   // callback(success as Boolean, message as String)

    function configured() as Boolean {
        return Model.backendUrl.length() > 0 && Model.pairToken.length() > 0;
    }

    function _headers(json as Boolean) as Dictionary {
        var h = { "X-Pair-Token" => Model.pairToken } as Dictionary;
        if (json) { h["Content-Type"] = Communications.REQUEST_CONTENT_TYPE_JSON; }
        return h;
    }

    function fetchToday(callback as Method?) as Boolean {
        if (busy || !configured()) { return false; }
        busy = true;
        onDone = callback;
        var url = Model.backendUrl + "/workout/today";
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => _headers(false),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, { "token" => Model.pairToken }, options, new Lang.Method(Net, :onWorkout));
        return true;
    }

    function onWorkout(code as Number, data as Dictionary or String or Null) as Void {
        busy = false;
        if (code == 200 && data instanceof Dictionary && (data as Dictionary).hasKey("exercises")) {
            Model.setWorkout(data as Dictionary);
            Model.online = true;
            Model.lastError = "";
            _finish(true, "OK");
        } else {
            Model.online = false;
            Model.lastError = describe(code, data);
            _finish(false, Model.lastError);
        }
    }

    // Etat live : ce que les machines Technogym ont deja enregistre pour la seance du jour.
    var liveBusy as Boolean = false;

    function fetchLive(callback as Method?) as Boolean {
        if (liveBusy || busy || !configured() || Model.workout == null) { return false; }
        var w = Model.workout as Dictionary;
        if (!w.hasKey("id")) { return false; }
        liveBusy = true;
        onLive = callback;
        var url = Model.backendUrl + "/workout/" + (w["id"] as String) + "/live";
        var params = { "token" => Model.pairToken } as Dictionary;
        if (w.hasKey("date")) { params["day"] = w["date"]; }
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => _headers(false),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, params, options, new Lang.Method(Net, :onLiveResponse));
        return true;
    }

    var onLive as Method? = null;

    function onLiveResponse(code as Number, data as Dictionary or String or Null) as Void {
        liveBusy = false;
        var changed = false;
        if (code == 200 && data instanceof Dictionary) {
            changed = Model.applyLive(data as Dictionary);
            Model.online = true;
        }
        var cb = onLive;
        onLive = null;
        if (cb != null) { (cb as Method).invoke(code == 200, changed); }
        WatchUi.requestUpdate();
    }

    // Seance courante Technogym (bornes, machines, app) : GET /live.
    var curBusy as Boolean = false;
    var onCurrent as Method? = null;

    function fetchCurrent(callback as Method?) as Boolean {
        if (curBusy || !configured()) { return false; }
        curBusy = true;
        onCurrent = callback;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => _headers(false),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(Model.backendUrl + "/live", { "token" => Model.pairToken }, options, new Lang.Method(Net, :onCurrentResponse));
        return true;
    }

    function onCurrentResponse(code as Number, data as Dictionary or String or Null) as Void {
        curBusy = false;
        var events = 0;
        var ok = code == 200 && data instanceof Dictionary && (data as Dictionary).hasKey("has_current_workout");
        if (ok) {
            events = Live.apply(data as Dictionary);
            Model.online = true;
        } else {
            Live.lastError = describe(code, data);
            Model.online = false;
        }
        var cb = onCurrent;
        onCurrent = null;
        if (cb != null) { (cb as Method).invoke(ok, events); }
        WatchUi.requestUpdate();
    }

    // Echantillons cardio : POST /live/hr (independant des autres requetes, une a la fois).
    var hrBusy as Boolean = false;
    var _hrPayload as Dictionary? = null;

    function sendHr(payload as Dictionary) as Boolean {
        if (hrBusy || !configured()) { return false; }
        hrBusy = true;
        _hrPayload = payload;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => _headers(true),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(Model.backendUrl + "/live/hr?token=" + Model.pairToken, payload, options, new Lang.Method(Net, :onHrResponse));
        return true;
    }

    function onHrResponse(code as Number, data as Dictionary or String or Null) as Void {
        hrBusy = false;
        var p = _hrPayload;
        _hrPayload = null;
        if (code == 200) {
            if (data instanceof Dictionary && (data as Dictionary).hasKey("total")) {
                Live.hrSent = Model.num(data as Dictionary, "total", 0).toNumber();
            }
        } else if (p != null) {
            Live.hrFailed(p as Dictionary);
        }
    }

    var _sending as Dictionary? = null;

    function sendResults(payload as Dictionary, callback as Method?) as Boolean {
        if (busy || !configured()) { return false; }
        busy = true;
        onDone = callback;
        _sending = payload;
        var wid = payload.hasKey("workout_id") ? payload["workout_id"] as String : "unknown";
        var url = Model.backendUrl + "/workout/" + wid + "/results?token=" + Model.pairToken;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => _headers(true),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, payload, options, new Lang.Method(Net, :onResults));
        return true;
    }

    function onResults(code as Number, data as Dictionary or String or Null) as Void {
        busy = false;
        var payload = _sending;
        _sending = null;
        if (code == 200) {
            Model.online = true;
            _finish(true, WatchUi.loadResource(Rez.Strings.Sent) as String);
        } else {
            Model.online = false;
            if (payload != null) { Model.queuePending(payload as Dictionary); }
            _finish(false, describe(code, data));
        }
    }

    // Envoie la premiere seance en attente ; les autres suivront aux prochains appels.
    function sendPending(callback as Method?) as Boolean {
        var p = Model.popPending();
        if (p == null) { return false; }
        return sendResults(p as Dictionary, callback);
    }

    function _finish(ok as Boolean, msg as String) as Void {
        var cb = onDone;
        onDone = null;
        if (cb != null) {
            (cb as Method).invoke(ok, msg);
        }
        WatchUi.requestUpdate();
    }

    function describe(code as Number, data as Dictionary or String or Null) as String {
        if (code == 401) { return "Compte non reconnu (401)"; }
        if (code == 404) { return "Séance introuvable (404)"; }
        if (code == 502 || code == 503) { return "Technogym indisponible"; }
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) { return "Téléphone non connecté"; }
        if (code == Communications.BLE_HOST_TIMEOUT || code == Communications.NETWORK_REQUEST_TIMED_OUT) { return "Délai dépassé"; }
        if (code == Communications.NETWORK_RESPONSE_TOO_LARGE) { return "Réponse trop grande"; }
        if (code == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) { return "Réponse invalide"; }
        if (code == Communications.SECURE_CONNECTION_REQUIRED) { return "HTTPS requis"; }
        if (data instanceof Dictionary && (data as Dictionary).hasKey("detail")) {
            return (data as Dictionary)["detail"].toString();
        }
        return "Erreur réseau " + code;
    }
}
