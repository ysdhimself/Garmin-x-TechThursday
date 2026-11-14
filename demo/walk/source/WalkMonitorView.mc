import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Two pages (UP/DOWN to switch):
//   1 WALK    - GPS quality, position, distance + arrow to the park, speed, status (ARRIVED / OFF ROUTE / ...)
//   2 SENSORS - heart rate and its change since sitting, steps, cadence, calories, heading,
//               altitude, air pressure, temperature
// Each reading shows "--" when the simulator / watch doesn't provide it.
class WalkMonitorView extends WatchUi.View {
    // Same project choices as PROJECT_PLAN.md: usable/good fixes only, fresh within 10 s,
    // several consecutive fixes inside the radius before arrival.
    const FRESH_MS = 10000;
    const ARRIVE_FIXES = 3;
    const OFF_ROUTE_M = 30.0d;
    const M_PER_DEG_LAT = 111194.9266d;
    const STEP_M = 0.7d; // stride estimate when the watch gives no step count

    var route;          // [[latE6, lonE6], ...]
    var entryLat;       // Double degrees
    var entryLon;
    var radius;         // metres
    var name;

    var page = 0;
    var timer;

    // GPS
    var lat = null;
    var lon = null;
    var quality = Position.QUALITY_NOT_AVAILABLE;
    var speed = null;
    var updates = 0;
    var lastFixMs = 0;
    var inside = 0;
    var arrived = false;
    var maxOffRoute = 0.0d;
    var walkedM = 0.0d;  // summed from GPS fixes
    var gpsCourse = null; // radians, direction of travel from the last two fixes

    // Body + sensors
    var hr = null;
    var hrRest = null;   // average while still, before the walk started
    var hrRestSum = 0;
    var hrRestN = 0;
    var hrPeak = null;   // highest since the walk started
    var walking = false; // has the walk started (speed > 0.3 m/s seen)?
    var cadence = null;
    var calories = null;
    var calStart = null;
    var stepsStart = null;
    var steps = null;
    var heading = null;  // radians, compass
    var altitude = null; // m
    var pressure = null; // Pa
    var temperature = null; // C

    // Diagnostics: which channel delivered data (E position event, P position poll, A activity info,
    // S sensor info).
    var src = "";
    var lastPolled = null;

    function initialize() {
        View.initialize();
        var plan = WatchUi.loadResource(Rez.JsonData.route);
        route = plan["route"]["points"];
        var dest = plan["destination"];
        entryLat = dest["point"][0].toDouble() / 1000000.0d;
        entryLon = dest["point"][1].toDouble() / 1000000.0d;
        radius = dest["arrivalRadiusM"];
        name = dest["name"];
        timer = new Timer.Timer();
    }

    function onShow() as Void { timer.start(method(:tick), 1000, true); }
    function onHide() as Void { stopTimer(); }
    function stopTimer() { timer.stop(); }

    function nextPage(delta) {
        page = (page + delta + 2) % 2;
        WatchUi.requestUpdate();
    }

    function reset() {
        updates = 0; inside = 0; arrived = false; maxOffRoute = 0.0d; walkedM = 0.0d; src = "";
        hrRest = null; hrRestSum = 0; hrRestN = 0; hrPeak = null; walking = false;
        calStart = null; stepsStart = null; steps = null;
        WatchUi.requestUpdate();
    }

    // ---- data in ----

    function onPosition(info as Position.Info) as Void {
        src = "E" + src;
        applyFix(info.position, info.accuracy, info.speed);
        WatchUi.requestUpdate();
    }

    function onSensor(info) as Void {
        readSensor(info);
        WatchUi.requestUpdate();
    }

    // Every second, poll the other places the simulator may put playback data.
    function tick() as Void {
        var s = "";
        var pinfo = Position.getInfo();
        if (pinfo != null && pinfo.position != null) {
            var key = pinfo.position.toDegrees();
            var k = key[0].format("%.6f") + key[1].format("%.6f");
            if (!k.equals(lastPolled)) { lastPolled = k; s += "P"; applyFix(pinfo.position, pinfo.accuracy, pinfo.speed); }
        }
        var a = Activity.getActivityInfo();
        if (a != null) {
            if (a.currentLocation != null) {
                s += "A";
                if (lat == null || System.getTimer() - lastFixMs > 2000) {
                    applyFix(a.currentLocation, a.currentLocationAccuracy, a.currentSpeed);
                }
            }
            if (a.currentHeartRate != null) { hr = a.currentHeartRate; }
            if (a.currentCadence != null) { cadence = a.currentCadence; }
            if (a.calories != null) {
                if (calStart == null) { calStart = a.calories; }
                calories = a.calories - calStart;
            }
            if (a.altitude != null) { altitude = a.altitude; }
            if (a.ambientPressure != null) { pressure = a.ambientPressure; }
            if (heading == null && a.currentHeading != null) { heading = a.currentHeading; }
        }
        var sinfo = Sensor.getInfo();
        if (sinfo != null) {
            if (sinfo.heartRate != null) { s += "S"; }
            readSensor(sinfo);
        }
        var am = ActivityMonitor.getInfo();
        if (am != null && am.steps != null) {
            if (stepsStart == null) { stepsStart = am.steps; }
            if (am.steps > stepsStart) { steps = am.steps - stepsStart; }
        }
        trackHeartRate();
        if (!s.equals("")) { src = s; }
        WatchUi.requestUpdate();
    }

    function readSensor(info) {
        if (info.heartRate != null) { hr = info.heartRate; }
        if (info.cadence != null) { cadence = info.cadence; }
        if (info.heading != null) { heading = info.heading; }
        if (info.altitude != null) { altitude = info.altitude; }
        if (info.pressure != null) { pressure = info.pressure; }
        if (info.temperature != null) { temperature = info.temperature; }
    }

    // Resting HR = average while still before the walk; peak = highest once walking.
    function trackHeartRate() {
        if (hr == null) { return; }
        if (!walking) {
            hrRestSum += hr; hrRestN++;
            hrRest = hrRestSum / hrRestN;
        } else if (hrPeak == null || hr > hrPeak) {
            hrPeak = hr;
        }
    }

    function applyFix(loc, acc, spd) {
        updates++;
        quality = acc == null ? Position.QUALITY_NOT_AVAILABLE : acc;
        speed = spd;
        if (spd != null && spd > 0.3) { walking = true; }
        if (loc == null) { return; }
        var d = loc.toDegrees();
        var newLat = d[0].toDouble();
        var newLon = d[1].toDouble();
        if (lat != null) {
            var moved = distanceM(lat, lon, newLat, newLon);
            if (moved > 0.5) {
                walkedM += moved;
                gpsCourse = bearing(lat, lon, newLat, newLon);
            }
        }
        lat = newLat;
        lon = newLon;
        lastFixMs = System.getTimer();
        var usable = quality == Position.QUALITY_USABLE || quality == Position.QUALITY_GOOD;
        inside = (usable && distanceM(lat, lon, entryLat, entryLon) <= radius) ? inside + 1 : 0;
        if (inside >= ARRIVE_FIXES) { arrived = true; }
        var off = distanceToRouteM(lat, lon);
        if (off > maxOffRoute) { maxOffRoute = off; }
    }

    // ---- drawing ----

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (page == 0) { drawWalk(dc); } else { drawSensors(dc); }
        // page dots
        var cx = dc.getWidth() / 2;
        for (var i = 0; i < 2; i++) {
            dc.setColor(i == page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 6 + i * 12, 250, 3);
        }
    }

    function drawWalk(dc) {
        var cx = dc.getWidth() / 2;
        var J = Graphics.TEXT_JUSTIFY_CENTER;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 22, Graphics.FONT_XTINY, "WALK  #" + updates + (src.equals("") ? "" : " " + src), J);

        var fresh = lat != null && System.getTimer() - lastFixMs <= FRESH_MS;
        dc.setColor(qualityColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 46, Graphics.FONT_XTINY, "GPS " + qualityName() + (lat != null && !fresh ? " STALE" : ""), J);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (lat == null) {
            dc.drawText(cx, 100, Graphics.FONT_SMALL, "WAITING FOR GPS", J);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 140, Graphics.FONT_XTINY, "Activity Data > Load .fit > Play", J);
            dc.drawText(cx, 170, Graphics.FONT_XTINY, "HR " + fmt(hr, "%d") + "   DOWN: sensors", J);
            return;
        }
        dc.drawText(cx, 70, Graphics.FONT_XTINY, lat.format("%.6f") + "  " + lon.format("%.6f"), J);

        var toPark = distanceM(lat, lon, entryLat, entryLon);
        dc.drawText(cx, 94, Graphics.FONT_XTINY, "TO " + name.toUpper(), J);
        dc.drawText(cx + 18, 114, Graphics.FONT_NUMBER_MILD, toPark.format("%d") + " m", J);

        // Arrow toward the park, relative to the way you're facing (compass, else direction of travel).
        var face = heading != null ? heading : gpsCourse;
        var toBearing = bearing(lat, lon, entryLat, entryLon);
        var rel = face == null ? toBearing : toBearing - face;
        dc.setColor(arrived ? Graphics.COLOR_GREEN : Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        drawArrow(dc, cx - 78, 146, rel);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 178, Graphics.FONT_XTINY, fmt(speed, "%.1f") + " m/s   walked " + walkedM.format("%d") + " m", J);

        var off = distanceToRouteM(lat, lon);
        var status;
        var color;
        if (arrived) { status = "ARRIVED"; color = Graphics.COLOR_GREEN; }
        else if (off > OFF_ROUTE_M) { status = "OFF ROUTE " + off.format("%d") + " m"; color = Graphics.COLOR_ORANGE; }
        else if (speed != null && speed > 0.3) { status = "WALKING"; color = Graphics.COLOR_WHITE; }
        else { status = "STOPPED"; color = Graphics.COLOR_LT_GRAY; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 202, Graphics.FONT_SMALL, status, J);
    }

    function drawSensors(dc) {
        var cx = dc.getWidth() / 2;
        var J = Graphics.TEXT_JUSTIFY_CENTER;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 22, Graphics.FONT_XTINY, "SENSORS", J);

        // Heart rate, big, with the change since sitting.
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 42, Graphics.FONT_NUMBER_MILD, fmt(hr, "%d"), J);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var change = (hrRest != null && hrPeak != null) ? ("+" + (hrPeak - hrRest).format("%d") + " vs sitting") : "rest " + fmt(hrRest, "%d");
        dc.drawText(cx, 100, Graphics.FONT_XTINY, "HR bpm   " + change, J);

        // Steps: the watch's own count if it moves, else estimated from GPS distance (marked ~).
        var stepsText = steps != null ? steps.format("%d") : (walkedM > 1 ? "~" + (walkedM / STEP_M).format("%d") : "--");
        dc.drawText(cx, 124, Graphics.FONT_XTINY, "STEPS " + stepsText + "   CAD " + fmt(cadence, "%d"), J);
        dc.drawText(cx, 148, Graphics.FONT_XTINY, "KCAL " + fmt(calories, "%d") + "   HEAD " + (heading == null ? "--" : degrees(heading).format("%d") + "°"), J);
        dc.drawText(cx, 172, Graphics.FONT_XTINY, "ALT " + fmt(altitude, "%d") + " m   " + (pressure == null ? "-- hPa" : (pressure / 100.0).format("%.1f") + " hPa"), J);
        dc.drawText(cx, 196, Graphics.FONT_XTINY, "TEMP " + fmt(temperature, "%d") + " C", J);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, "max off-route " + maxOffRoute.format("%d") + " m", J);
    }

    // Filled arrow centred at (x, y) pointing `angle` radians clockwise from straight up.
    function drawArrow(dc, x, y, angle) {
        var pts = [[0, -18], [11, 12], [0, 5], [-11, 12]];
        var c = Math.cos(angle);
        var s = Math.sin(angle);
        var out = [];
        for (var i = 0; i < pts.size(); i++) {
            var px = pts[i][0];
            var py = pts[i][1];
            out.add([x + px * c - py * s, y + px * s + py * c]);
        }
        dc.fillPolygon(out);
    }

    // ---- helpers ----

    function fmt(v, f) { return v == null ? "--" : v.format(f); }

    function degrees(r) {
        var d = Math.toDegrees(r).toNumber() % 360;
        return d < 0 ? d + 360 : d;
    }

    function qualityName() {
        if (quality == Position.QUALITY_GOOD) { return "GOOD"; }
        if (quality == Position.QUALITY_USABLE) { return "USABLE"; }
        if (quality == Position.QUALITY_POOR) { return "POOR"; }
        if (quality == Position.QUALITY_LAST_KNOWN) { return "LAST KNOWN"; }
        return "NO FIX";
    }

    function qualityColor() {
        if (quality == Position.QUALITY_GOOD) { return Graphics.COLOR_GREEN; }
        if (quality == Position.QUALITY_USABLE) { return Graphics.COLOR_YELLOW; }
        return Graphics.COLOR_RED;
    }

    // Great-circle distance in metres.
    function distanceM(lat1, lon1, lat2, lon2) {
        var dLat = Math.toRadians(lat2 - lat1);
        var dLon = Math.toRadians(lon2 - lon1);
        var a = Math.pow(Math.sin(dLat / 2), 2)
            + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLon / 2), 2);
        return 2 * 6371008.8d * Math.asin(Math.sqrt(a));
    }

    // Initial bearing from point 1 to point 2, radians clockwise from north.
    function bearing(lat1, lon1, lat2, lon2) {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dl = Math.toRadians(lon2 - lon1);
        return Math.atan2(Math.sin(dl) * Math.cos(p2), Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl));
    }

    // Shortest distance in metres from the point to the route polyline (flat-earth, fine at walking scale).
    function distanceToRouteM(pLat, pLon) {
        var mLon = M_PER_DEG_LAT * Math.cos(Math.toRadians(pLat));
        var best = 1.0e9d;
        for (var i = 0; i + 1 < route.size(); i++) {
            var a = route[i];
            var b = route[i + 1];
            var ax = (a[1].toDouble() / 1000000.0d - pLon) * mLon;
            var ay = (a[0].toDouble() / 1000000.0d - pLat) * M_PER_DEG_LAT;
            var bx = (b[1].toDouble() / 1000000.0d - pLon) * mLon;
            var by = (b[0].toDouble() / 1000000.0d - pLat) * M_PER_DEG_LAT;
            var dx = bx - ax;
            var dy = by - ay;
            var len2 = dx * dx + dy * dy;
            var t = 0.0d;
            if (len2 > 0) {
                t = -(ax * dx + ay * dy) / len2;
                if (t < 0) { t = 0.0d; }
                if (t > 1) { t = 1.0d; }
            }
            var qx = ax + t * dx;
            var qy = ay + t * dy;
            var d = Math.sqrt(qx * qx + qy * qy);
            if (d < best) { best = d; }
        }
        return best;
    }
}
