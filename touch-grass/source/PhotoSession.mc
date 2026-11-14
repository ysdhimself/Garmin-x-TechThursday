import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// One owner for the timer and the single outstanding HTTP request. Invalidating
// an attempt does not unlock that request: its stale callback must drain first.
class PhotoSession {
    var status as String = "loading";
    var qr as Array<String>? = null;
    var reconnecting as Boolean = false;
    private var _running as Boolean = false;
    private var _generation as Number = 0;
    private var _inFlight as Boolean = false;
    private var _timer as Timer.Timer? = null;
    private var _id as String? = null;
    private var _baseUrl as String = "";
    private var _expiresAt as Number = 0;

    function initialize() {
    }

    function start() as Void {
        if (_running) { return; }
        _running = true;
        _generation += 1;
        status = "loading";
        qr = null;
        _id = null;
        reconnecting = false;
        var baseUrl = Application.Properties.getValue("PhotoBaseUrl");
        if (!(baseUrl instanceof String) || baseUrl.length() == 0) {
            status = "error";
            WatchUi.requestUpdate();
            return;
        }
        _baseUrl = baseUrl;
        while (_baseUrl.length() > 0 && _baseUrl.substring(_baseUrl.length() - 1, _baseUrl.length()).equals("/")) {
            _baseUrl = _baseUrl.substring(0, _baseUrl.length() - 1);
        }
        var timer = new Timer.Timer();
        timer.start(method(:tick), 2000, true);
        _timer = timer;
        tick();
    }

    function stop() as Void {
        _running = false;
        _generation += 1;
        var timer = _timer;
        if (timer != null) { timer.stop(); }
        _timer = null;
        qr = null;
        _id = null;
    }

    function retry() as Void {
        if (status.equals("error") || status.equals("expired")) {
            stop();
            start();
        }
    }

    function tick() as Void {
        if (!_running || status.equals("error") || status.equals("expired")) { return; }
        if (_id != null && System.getTimer() >= _expiresAt) {
            expire();
            return;
        }
        if (_inFlight) { return; }
        var creating = _id == null;
        var url = _baseUrl + "/photo-sessions";
        if (!creating) { url += "/" + _id; }
        _inFlight = true;
        try {
            Communications.makeWebRequest(url, creating ? {} : null, {
                :method => creating ? Communications.HTTP_REQUEST_METHOD_POST : Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
                :context => [_generation, creating]
            }, method(:onResponse));
        } catch (e) {
            _inFlight = false;
            requestFailed(creating);
        }
    }

    function onResponse(code as Number, data as Communications.ContentType?, context as Object) as Void {
        var request = context as Array;
        _inFlight = false;
        if (!_running || request[0] != _generation) { return; }
        // A late passing response cannot resurrect a locally expired session.
        if (status.equals("expired") || (_id != null && System.getTimer() >= _expiresAt)) {
            expire();
            return;
        }
        var creating = request[1];
        if (code == 410) {
            expire();
        } else if (!(data instanceof Dictionary)) {
            requestFailed(creating);
        } else if (creating) {
            if (code == 201 && validCreation(data)) {
                _id = data["id"];
                qr = data["qr"] as Array<String>;
                _expiresAt = System.getTimer() + data["expiresInS"] * 1000;
                status = "ready";
            } else {
                requestFailed(true);
            }
        } else if (code == 200 && validStatus(data)) {
            reconnecting = false;
            if (data["expiresInS"] <= 0) {
                expire();
            } else if (isPassed(data)) {
                stop();
                getApp().photoPassed();
            }
        } else {
            requestFailed(false);
        }
        WatchUi.requestUpdate();
    }

    private function requestFailed(creating as Boolean) as Void {
        // A failed POST is ambiguous: only explicit START creates another one.
        // Poll failures keep the existing QR and retry on the next timer tick.
        if (creating) { status = "error"; }
        else { reconnecting = true; }
        WatchUi.requestUpdate();
    }

    private function expire() as Void {
        status = "expired";
        qr = null;
        WatchUi.requestUpdate();
    }

    static function validCreation(data) as Boolean {
        if (!(data instanceof Dictionary)) { return false; }
        var id = data["id"];
        var url = data["url"];
        var rows = data["qr"];
        var ttl = data["expiresInS"];
        if (!(id instanceof String) || id.length() != 16
                || !(url instanceof String) || url.length() == 0
                || !(ttl instanceof Number) || ttl <= 0 || ttl > 600
                || !(rows instanceof Array) || rows.size() < 21 || rows.size() > 177
                || (rows.size() - 21) % 4 != 0) { return false; }
        var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";
        for (var i = 0; i < id.length(); i += 1) {
            if (alphabet.find(id.substring(i, i + 1)) == null) { return false; }
        }
        for (var y = 0; y < rows.size(); y += 1) {
            var row = rows[y];
            if (!(row instanceof String) || row.length() != rows.size()) { return false; }
            for (var x = 0; x < row.length(); x += 1) {
                var bit = row.substring(x, x + 1);
                if (!bit.equals("0") && !bit.equals("1")) { return false; }
            }
        }
        return true;
    }

    static function validStatus(data) as Boolean {
        if (!(data instanceof Dictionary)) { return false; }
        var confidence = data["confidence"];
        var threshold = data["threshold"];
        return ("pending".equals(data["status"]) || "passed".equals(data["status"]))
            && (threshold instanceof Float || threshold instanceof Double)
            && threshold.toFloat() == 0.7
            && data["expiresInS"] instanceof Number
            && (confidence == null || ((confidence instanceof Float || confidence instanceof Double || confidence instanceof Number)
                && confidence >= 0 && confidence <= 1));
    }

    static function isPassed(data) as Boolean {
        return data instanceof Dictionary && validStatus(data) && "passed".equals(data["status"])
            && data["confidence"] != null && data["confidence"] >= 0.70;
    }
}
