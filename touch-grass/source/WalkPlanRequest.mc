import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

class WalkPlanRequest {
    var plan as Dictionary? = null;
    var status as String = "idle";
    private var _inFlight as Boolean = false;

    function initialize() {
    }

    function request() as Void {
        if (_inFlight || status.equals("ready")) { return; }
        var info = Position.getInfo();
        if (info.position == null || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return;
        }
        var deg = (info.position as Position.Location).toDegrees();
        var lat = deg[0].toFloat();
        var lon = deg[1].toFloat();
        if (lat.abs() > 90.0 || lon.abs() > 180.0) {
            return;
        }
        var baseUrl = Application.Properties.getValue("WalkPlanUrl");
        if (!(baseUrl instanceof String) || baseUrl.length() == 0) {
            status = "error";
            return;
        }
        while (baseUrl.length() > 0 && baseUrl.substring(baseUrl.length() - 1, baseUrl.length()).equals("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }
        var latE6 = (lat * 1000000).toNumber();
        var lonE6 = (lon * 1000000).toNumber();
        status = "loading";
        _inFlight = true;
        try {
            Communications.makeWebRequest(
                baseUrl + "/walk-plan",
                {"originLatE6" => latE6, "originLonE6" => lonE6, "maxWalkS" => 120},
                {
                    :method => Communications.HTTP_REQUEST_METHOD_POST,
                    :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
                    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
                    :context => true
                },
                method(:onResponse)
            );
        } catch (e) {
            _inFlight = false;
            status = "error";
        }
    }

    function reset() as Void {
        plan = null;
        status = "idle";
        _inFlight = false;
    }

    function onResponse(code as Number, data as Communications.ContentType?, context as Object) as Void {
        _inFlight = false;
        if (code == 200 && data instanceof Dictionary && (data as Dictionary).hasKey("route")) {
            plan = data as Dictionary;
            status = "ready";
            System.println("Walk plan received from backend");
        } else {
            status = "error";
            System.println("Walk plan request failed: " + code);
        }
        WatchUi.requestUpdate();
    }
}
