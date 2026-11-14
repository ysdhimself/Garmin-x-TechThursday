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

// Three pages (UP/DOWN to switch; SUMMARY opens by itself 3 s after arrival):
//   0 WALK    - GPS, distance + arrow to the park, speed, status (STOPPED / WALKING / OFF ROUTE / ARRIVED)
//   1 SENSORS - live heart rate, steps, cadence, calories, heading, altitude, pressure, temperature
//   2 SUMMARY - the walk from start to arrival: time, distance, heart rate (rest / avg / peak / rise),
//               steps, cadence, calories, altitude and temperature change
// Any reading the simulator / watch doesn't provide shows "--".
class WalkMonitorView extends WatchUi.View {
    const FRESH_MS = 10000;
    const ARRIVE_FIXES = 3;
    const OFF_ROUTE_M = 30.0d;
    const JUMP_M = 50.0d;     // a single move larger than this is a location jump, not walking
    const WALKING_MPS = 0.3;
    const SUMMARY_DELAY_MS = 3000;
    const M_PER_DEG_LAT = 111194.9266d;
    const STEP_M = 0.7d;      // stride estimate when the watch gives no step count
    const PAGES = 3;

    var route;
    var entryLat;
    var entryLon;
    var radius;
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
    var arrivedOnPoor = false;
    var maxOffRoute = 0.0d;
    var walkedM = 0.0d;
    var gpsCourse = null;

    // Live sensors
    var hr = null;
    var cadence = null;
    var calories = null;     // kcal since the app started (activity info)
    var calBase = null;
    var steps = null;        // watch step count since the app started
    var stepsBase = null;
    var heading = null;
    var altitude = null;
    var pressure = null;
    var temperature = null;

    // Walk tracking for the summary
    var walkStartMs = null;
    var arriveMs = null;
    var summaryShown = false;
    var restSum = 0;
    var restN = 0;
    var walkHrSum = 0;
    var walkHrN = 0;
    var hrPeak = null;
    var cadSum = 0;
    var cadN = 0;
    var start = null;        // snapshot at walk start: {walked, cal, steps, alt, temp}
    var summary = null;      // frozen at arrival

    var src = "";
    var lastPolled = null;
    var lastActivity = null;

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
        page = (page + delta + PAGES) % PAGES;
        WatchUi.requestUpdate();
    }

    function reset() {
        updates = 0; inside = 0; arrived = false; arrivedOnPoor = false; maxOffRoute = 0.0d; walkedM = 0.0d;
        walkStartMs = null; arriveMs = null; summaryShown = false; summary = null; start = null;
        restSum = 0; restN = 0; walkHrSum = 0; walkHrN = 0; hrPeak = null; cadSum = 0; cadN = 0;
        calBase = null; stepsBase = null; calories = null; steps = null; src = ""; page = 0;
        WatchUi.requestUpdate();
    }

    // ---- data in ----

    function onPosition(info as Position.Info) as Void {
        src = "E";
        applyFix(info.position, info.accuracy, info.speed);
        WatchUi.requestUpdate();
    }

    function onSensor(info) as Void {
        readSensor(info);
        WatchUi.requestUpdate();
    }

    // Once a second: read every channel the simulator may fill from FIT playback. In the CIQ simulator,
    // FIT playback arrives through Activity.getActivityInfo() (A), not Position events (E).
    function tick() as Void {
        var s = "";
        var pinfo = Position.getInfo();
        if (pinfo != null && pinfo.position != null) {
            var k = key(pinfo.position);
            if (!k.equals(lastPolled)) { lastPolled = k; s += "P"; applyFix(pinfo.position, pinfo.accuracy, pinfo.speed); }
        }
        var a = Activity.getActivityInfo();
        if (a != null) {
            if (a.currentLocation != null) {
                s += "A";
                var k2 = key(a.currentLocation);
                if (!k2.equals(lastActivity)) {
                    lastActivity = k2;
                    applyFix(a.currentLocation, a.currentLocationAccuracy, a.currentSpeed);
                } else if (a.currentSpeed != null) {
                    speed = a.currentSpeed;
                }
            }
            if (a.currentHeartRate != null) { hr = a.currentHeartRate; }
            if (a.currentCadence != null) { cadence = a.currentCadence; }
            if (a.calories != null) {
                if (calBase == null) { calBase = a.calories; }
                calories = a.calories - calBase;
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
            if (stepsBase == null) { stepsBase = am.steps; }
            steps = am.steps > stepsBase ? am.steps - stepsBase : null;
        }
        trackWalk();
        if (!s.equals("")) { src = s; }
        if (arrived && !summaryShown && System.getTimer() - arriveMs >= SUMMARY_DELAY_MS) {
            summaryShown = true;
            page = 2;
        }
        WatchUi.requestUpdate();
    }

    function key(loc) {
        var d = loc.toDegrees();
        return d[0].format("%.6f") + d[1].format("%.6f");
    }

    function readSensor(info) {
        if (info.heartRate != null) { hr = info.heartRate; }
        if (info.cadence != null) { cadence = info.cadence; }
        if (info.heading != null) { heading = info.heading; }
        if (info.altitude != null) { altitude = info.altitude; }
        if (info.pressure != null) { pressure = info.pressure; }
        if (info.temperature != null) { temperature = info.temperature; }
    }

    // Walk = from the first moment speed exceeds 0.3 m/s until arrival.
    function trackWalk() {
        var moving = speed != null && speed > WALKING_MPS;
        if (walkStartMs == null && moving) {
            walkStartMs = System.getTimer();
            start = { "walked" => walkedM, "cal" => calories, "steps" => steps, "alt" => altitude, "temp" => temperature };
        }
        if (arrived) { return; }
        if (hr != null) {
            if (walkStartMs == null) { restSum += hr; restN++; }
            else {
                walkHrSum += hr; walkHrN++;
                if (hrPeak == null || hr > hrPeak) { hrPeak = hr; }
            }
        }
        if (walkStartMs != null && cadence != null && cadence > 0) { cadSum += cadence; cadN++; }
    }

    function applyFix(loc, acc, spd) {
        updates++;
        quality = acc == null ? Position.QUALITY_NOT_AVAILABLE : acc;
        if (spd != null) { speed = spd; }
        if (loc == null) { return; }
        var d = loc.toDegrees();
        var newLat = d[0].toDouble();
        var newLon = d[1].toDouble();
        if (lat != null) {
            var moved = distanceM(lat, lon, newLat, newLon);
            if (moved > JUMP_M) {
                // Location jump (e.g. the simulator's default location -> the FIT file): not walking.
                inside = 0;
            } else if (moved > 0.5) {
                walkedM += moved;
                gpsCourse = bearing(lat, lon, newLat, newLon);
            }
        }
        lat = newLat;
        lon = newLon;
        lastFixMs = System.getTimer();
        // Project rule: usable/good fixes only. The simulator reports FIT playback as POOR, so this test
        // tool also accepts POOR and flags it; the Touch Grass app should keep the stricter rule on a watch.
        var ok = quality == Position.QUALITY_USABLE || quality == Position.QUALITY_GOOD || quality == Position.QUALITY_POOR;
        inside = (ok && distanceM(lat, lon, entryLat, entryLon) <= radius) ? inside + 1 : 0;
        if (inside >= ARRIVE_FIXES && !arrived) {
            arrived = true;
            arrivedOnPoor = quality == Position.QUALITY_POOR;
            arriveMs = System.getTimer();
            freezeSummary();
        }
        var off = distanceToRouteM(lat, lon);
        if (off > maxOffRoute) { maxOffRoute = off; }
    }

    function freezeSummary() {
        var st = start == null ? {} : start;
        summary = {
            "timeS" => walkStartMs == null ? null : (arriveMs - walkStartMs) / 1000,
            "distM" => walkedM - (st["walked"] == null ? 0.0d : st["walked"]),
            "rest" => restN > 0 ? restSum / restN : null,
            "avg" => walkHrN > 0 ? walkHrSum / walkHrN : null,
            "peak" => hrPeak,
            "steps" => diff(steps, st["steps"]),
            "cad" => cadN > 0 ? cadSum / cadN : null,
            "kcal" => diff(calories, st["cal"]),
            "alt" => diff(altitude, st["alt"]),
            "temp" => diff(temperature, st["temp"]),
            "tempEnd" => temperature,
        };
    }

    function diff(now, before) { return (now == null || before == null) ? null : now - before; }

    // ---- drawing ----

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (page == 0) { drawWalk(dc); } else if (page == 1) { drawSensors(dc); } else { drawSummary(dc); }
        var cx = dc.getWidth() / 2;
        for (var i = 0; i < PAGES; i++) {
            dc.setColor(i == page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 12 + i * 12, 250, 3);
        }
    }

    // Big digits (number font has digits only) followed by a small unit.
    function drawValue(dc, cx, y, value, unit) {
        var wNum = dc.getTextWidthInPixels(value, Graphics.FONT_NUMBER_MILD);
        var wUnit = dc.getTextWidthInPixels(" " + unit, Graphics.FONT_SMALL);
        var x = cx - (wNum + wUnit) / 2;
        dc.drawText(x, y, Graphics.FONT_NUMBER_MILD, value, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + wNum, y + 22, Graphics.FONT_SMALL, " " + unit, Graphics.TEXT_JUSTIFY_LEFT);
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
        dc.drawText(cx, 94, Graphics.FONT_XTINY, "TO " + name.toUpper(), J);
        drawValue(dc, cx + 20, 112, distanceM(lat, lon, entryLat, entryLon).format("%d"), "m");

        var face = heading != null ? heading : gpsCourse;
        var toBearing = bearing(lat, lon, entryLat, entryLon);
        dc.setColor(arrived ? Graphics.COLOR_GREEN : Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        drawArrow(dc, cx - 80, 146, face == null ? toBearing : toBearing - face);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 178, Graphics.FONT_XTINY, fmt(speed, "%.1f") + " m/s   walked " + walkedM.format("%d") + " m", J);

        var off = distanceToRouteM(lat, lon);
        var status;
        var color;
        if (arrived) { status = arrivedOnPoor ? "ARRIVED*" : "ARRIVED"; color = Graphics.COLOR_GREEN; }
        else if (off > OFF_ROUTE_M) { status = "OFF ROUTE " + off.format("%d") + " m"; color = Graphics.COLOR_ORANGE; }
        else if (speed != null && speed > WALKING_MPS) { status = "WALKING"; color = Graphics.COLOR_WHITE; }
        else { status = "STOPPED"; color = Graphics.COLOR_LT_GRAY; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 202, Graphics.FONT_SMALL, status, J);
        if (arrivedOnPoor) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 228, Graphics.FONT_XTINY, "*on simulator POOR GPS", J);
        }
    }

    function drawSensors(dc) {
        var cx = dc.getWidth() / 2;
        var J = Graphics.TEXT_JUSTIFY_CENTER;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 22, Graphics.FONT_XTINY, "SENSORS", J);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        drawValue(dc, cx, 40, fmt(hr, "%d"), "bpm");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var rest = restN > 0 ? restSum / restN : null;
        dc.drawText(cx, 100, Graphics.FONT_XTINY, "resting " + fmt(rest, "%d") + "   peak " + fmt(hrPeak, "%d"), J);
        dc.drawText(cx, 124, Graphics.FONT_XTINY, "STEPS " + stepsText(steps, walkedM) + "   CAD " + fmt(cadence, "%d"), J);
        dc.drawText(cx, 148, Graphics.FONT_XTINY, "KCAL " + fmt(calories, "%d") + "   HEAD " + (heading == null ? "--" : degrees(heading).format("%d") + " deg"), J);
        dc.drawText(cx, 172, Graphics.FONT_XTINY, "ALT " + fmt(altitude, "%d") + " m   " + (pressure == null ? "-- hPa" : (pressure / 100.0).format("%.1f") + " hPa"), J);
        dc.drawText(cx, 196, Graphics.FONT_XTINY, "TEMP " + fmt(temperature, "%d") + " C", J);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, "max off-route " + maxOffRoute.format("%d") + " m", J);
    }

    function drawSummary(dc) {
        var cx = dc.getWidth() / 2;
        var J = Graphics.TEXT_JUSTIFY_CENTER;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 22, Graphics.FONT_XTINY, "WALK SUMMARY", J);
        if (summary == null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 110, Graphics.FONT_SMALL, "NOT ARRIVED YET", J);
            dc.drawText(cx, 145, Graphics.FONT_XTINY, "Shows 3 s after arrival", J);
            return;
        }
        var t = summary["timeS"];
        var timeText = t == null ? "--" : (t / 60).format("%d") + ":" + (t % 60).format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawValue(dc, cx, 40, t == null ? "--" : t.format("%d"), "sec");
        dc.drawText(cx, 100, Graphics.FONT_XTINY, timeText + " walk   " + summary["distM"].format("%d") + " m", J);

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        var rise = (summary["rest"] != null && summary["peak"] != null) ? "+" + (summary["peak"] - summary["rest"]).format("%d") : "--";
        dc.drawText(cx, 124, Graphics.FONT_XTINY, "HR " + fmt(summary["rest"], "%d") + " > " + fmt(summary["peak"], "%d") + " (" + rise + ")  avg " + fmt(summary["avg"], "%d"), J);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 148, Graphics.FONT_XTINY, "STEPS " + stepsText(summary["steps"], summary["distM"]) + "   CAD " + fmt(summary["cad"], "%d"), J);
        dc.drawText(cx, 172, Graphics.FONT_XTINY, "KCAL " + fmt(summary["kcal"], "%d") + "   ALT " + signed(summary["alt"]) + " m", J);
        dc.drawText(cx, 196, Graphics.FONT_XTINY, "TEMP " + fmt(summary["tempEnd"], "%d") + " C (" + signed(summary["temp"]) + ")", J);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 222, Graphics.FONT_XTINY, "START: reset", J);
    }

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

    function signed(v) {
        if (v == null) { return "--"; }
        return (v >= 0 ? "+" : "") + v.format("%d");
    }

    // Watch step count if it moved, else an estimate from GPS distance (marked ~).
    function stepsText(count, dist) {
        if (count != null) { return count.format("%d"); }
        return dist != null && dist > 1 ? "~" + (dist / STEP_M).format("%d") : "--";
    }

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
        if (quality == Position.QUALITY_POOR) { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_RED;
    }

    function distanceM(lat1, lon1, lat2, lon2) {
        var dLat = Math.toRadians(lat2 - lat1);
        var dLon = Math.toRadians(lon2 - lon1);
        var a = Math.pow(Math.sin(dLat / 2), 2)
            + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLon / 2), 2);
        return 2 * 6371008.8d * Math.asin(Math.sqrt(a));
    }

    function bearing(lat1, lon1, lat2, lon2) {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dl = Math.toRadians(lon2 - lon1);
        return Math.atan2(Math.sin(dl) * Math.cos(p2), Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl));
    }

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
