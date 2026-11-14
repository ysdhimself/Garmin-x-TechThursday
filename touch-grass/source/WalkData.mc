import Toybox.Activity;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

// Collects the WALK step: position, distance to the grass, heart rate, cadence/steps, calories and
// altitude, then freezes a summary on arrival (shown on the SUMMARY step).
//
// Data source, in order:
//   LIVE - Activity.getActivityInfo() / Position.getInfo(). In the CIQ simulator this is the
//          Activity Data playback of demo/walk/fixtures/quick-walk.fit (positions arrive as POOR quality).
//   DEMO - if no position near the route arrives within FALLBACK_MS, a built-in replay of the same 30 s walk:
//          route-edmonton-short.json (42 m) at 1.4 m/s, then standing at the grass. Same heart-rate / cadence /
//          calorie model as demo/walk/fixtures/generate.py.
//
// Arrival: 3 fixes in a row inside the radius AND stopped, so a walk ends when you stop at the grass rather
// than when you cross the edge of the radius.
module WalkData {

    const FALLBACK_MS = 3000;
    const ARRIVE_FIXES = 3;
    const JUMP_M = 50.0;        // one move larger than this is a location jump, not walking
    const NEAR_ROUTE_M = 2000.0; // live fixes further than this from the grass are ignored
    const MOVING_MPS = 0.3;
    const WALK_MPS = 1.4;
    const STEP_M = 0.7;

    enum Mode { WAITING, LIVE, DEMO }

    var _route = null;       // [[latE6, lonE6], ...] from route-edmonton-short.json
    var _entryLat = 0.0d;
    var _entryLon = 0.0d;
    var _radius = 25;

    var _mode = WAITING;
    var _startMs = 0;
    var _demoStartMs = 0;
    var _lastTickMs = 0;

    var _lat = null;
    var _lon = null;
    var _speed = null;
    var _hr = null;
    var _cadence = null;     // strides/min as reported
    var _calTotal = null;
    var _alt = null;

    var _walkedM = 0.0d;
    var _steps = 0.0;
    var _inside = 0;
    var _arrived = false;
    var _walkStartMs = null;
    var _lastMovingMs = null;
    var _calAtWalk = null;
    var _altAtWalk = null;
    var _restSum = 0;
    var _restN = 0;
    var _walkHrSum = 0;
    var _walkHrN = 0;
    var _hrPeak = null;
    var _cadSum = 0.0;
    var _cadN = 0;
    var _summary = null;

    // ---- lifecycle ----

    function start() as Void {
        var httpPlan = getApp().walkPlanRequest.plan;
        var plan;
        if (httpPlan != null) {
            plan = httpPlan;
            System.println("WalkData: using walk plan from backend");
        } else {
            plan = WatchUi.loadResource(Rez.JsonData.walkRoute) as Dictionary;
            System.println("WalkData: using bundled walk plan fallback");
        }
        _route = (plan["route"] as Dictionary)["points"];
        var dest = plan["destination"] as Dictionary;
        var p = dest["point"] as Array<Number>;
        _entryLat = p[0].toDouble() / 1000000.0d;
        _entryLon = p[1].toDouble() / 1000000.0d;
        _radius = dest["arrivalRadiusM"] as Number;
        _mode = WAITING;
        _startMs = System.getTimer();
        _lastTickMs = _startMs;
        _lat = null; _lon = null; _speed = null; _hr = null; _cadence = null; _calTotal = null; _alt = null;
        _walkedM = 0.0d; _steps = 0.0; _inside = 0; _arrived = false;
        _walkStartMs = null; _lastMovingMs = null; _calAtWalk = null; _altAtWalk = null;
        _restSum = 0; _restN = 0; _walkHrSum = 0; _walkHrN = 0; _hrPeak = null;
        _cadSum = 0.0; _cadN = 0; _summary = null;
    }

    // Leaving WALK early (START): keep whatever was collected for the summary.
    function finish() as Void {
        if (_summary == null) { freeze(System.getTimer()); }
    }

    // Called once a second while WALK is on screen.
    function tick() as Void {
        var now = System.getTimer();
        var dt = (now - _lastTickMs) / 1000.0;
        _lastTickMs = now;
        if (_arrived) { return; }

        if (_mode != DEMO) {
            readLive();
            if (_mode == WAITING && now - _startMs >= FALLBACK_MS) {
                _mode = DEMO;
                _demoStartMs = now;
                _restSum = 68; // the demo has no sitting phase: seed a typical resting heart rate
                _restN = 1;
            }
        }
        if (_mode == DEMO) { readDemo(now); }
        if (_lat != null) { track(now, dt); }
    }

    // ---- data sources ----

    function readLive() as Void {
        var loc = null;
        var spd = null;
        var a = Activity.getActivityInfo();
        if (a != null) {
            loc = a.currentLocation;
            spd = a.currentSpeed;
            if (a.currentHeartRate != null) { _hr = a.currentHeartRate; }
            if (a.currentCadence != null) { _cadence = a.currentCadence; }
            if (a.calories != null) { _calTotal = a.calories; }
            if (a.altitude != null) { _alt = a.altitude; }
        }
        if (loc == null) {
            var p = Position.getInfo();
            loc = p.position;
            spd = p.speed;
        }
        if (loc == null) { return; }
        var d = (loc as Position.Location).toDegrees();
        var lat = d[0].toDouble();
        var lon = d[1].toDouble();
        // Ignore positions far from the walk (e.g. the simulator's default location before playback).
        if (distanceM(lat, lon, _entryLat, _entryLon) > NEAR_ROUTE_M) { return; }
        _mode = LIVE;
        move(lat, lon);
        _speed = spd;
    }

    // Built-in replay: walk the whole route at 1.4 m/s from the moment the fallback starts (42 m = 30 s),
    // then stand at the grass.
    function readDemo(now as Number) as Void {
        var t = (now - _demoStartMs) / 1000.0;
        var total = routeLength();
        var walkS = total / WALK_MPS;
        var along = t * WALK_MPS;
        var walking = along < total;
        if (!walking) { along = total; }
        var pt = pointAt(along);
        move(pt[0], pt[1]);
        _speed = walking ? WALK_MPS : 0.0;
        if (walking) {
            _hr = (70 + 25 * t / walkS).toNumber();
        } else {
            _hr = (95 - (t - walkS) / 2).toNumber();
            if (_hr < 85) { _hr = 85; }
        }
        _cadence = walking ? 53 : 0;
        _calTotal = (4.0 / 60.0 * (walking ? t : walkS)).toNumber();
        _alt = 668.0 + 1.5 * Math.sin(along / 30.0);
    }

    // ---- tracking ----

    function move(lat as Double, lon as Double) as Void {
        if (_lat != null) {
            var moved = distanceM(_lat, _lon, lat, lon);
            if (moved > JUMP_M) {
                _inside = 0;
            } else if (moved > 0.3) {
                _walkedM += moved;
            }
        }
        _lat = lat;
        _lon = lon;
    }

    function track(now as Number, dt as Float) as Void {
        var moving = _speed != null && _speed > MOVING_MPS;
        if (_walkStartMs == null && moving) {
            _walkStartMs = now;
            _calAtWalk = _calTotal;
            _altAtWalk = _alt;
        }
        if (moving) { _lastMovingMs = now; }
        if (_hr != null) {
            if (_walkStartMs == null) {
                _restSum += _hr; _restN += 1;
            } else {
                _walkHrSum += _hr; _walkHrN += 1;
                if (_hrPeak == null || _hr > _hrPeak) { _hrPeak = _hr; }
            }
        }
        if (_walkStartMs != null && moving) {
            var spm = stepsPerMin();
            if (spm != null) {
                _cadSum += spm; _cadN += 1;
                _steps += spm / 60.0 * dt;
            } else {
                _steps += _speed * dt / STEP_M;
            }
        }
        // Arrival: 3 fixes in a row inside the radius while stopped. The simulator reports FIT playback as POOR,
        // so any fix counts here; on a real watch Part 1 should require USABLE/GOOD.
        var near = distanceM(_lat, _lon, _entryLat, _entryLon) <= _radius;
        _inside = (near && !moving) ? _inside + 1 : 0;
        if (_inside >= ARRIVE_FIXES) {
            _arrived = true;
            freeze(now);
        }
    }

    // Cadence in steps/min: FIT/Garmin walking cadence is strides/min (one per two steps).
    function stepsPerMin() {
        if (_cadence == null || _cadence <= 0) { return null; }
        return _cadence < 80 ? _cadence * 2 : _cadence;
    }

    function freeze(now as Number) as Void {
        _summary = {
            "timeS" => walkedS(),
            "distM" => _walkedM.toNumber(),
            "rest" => _restN > 0 ? _restSum / _restN : null,
            "peak" => _hrPeak,
            "avg" => _walkHrN > 0 ? _walkHrSum / _walkHrN : null,
            "steps" => _steps > 0 ? _steps.toNumber() : null,
            "cadence" => _cadN > 0 ? (_cadSum / _cadN).toNumber() : null,
            "kcal" => (_calTotal == null || _calAtWalk == null) ? null : _calTotal - _calAtWalk,
            "alt" => (_alt == null || _altAtWalk == null) ? null : (_alt - _altAtWalk).toNumber(),
        };
    }

    // ---- read by the screens ----

    function arrived() as Boolean { return _arrived; }
    function hasData() as Boolean { return _lat != null; }
    function summary() { return _summary; }
    function speed() { return _speed; }
    function heartRate() { return _hr; }
    function steps() as Number { return _steps.toNumber(); }

    // Seconds from the start of the walk to the last moment of moving (the walk itself, not standing after).
    function walkedS() as Number {
        if (_walkStartMs == null) { return 0; }
        var end = _arrived || _lastMovingMs == null ? _lastMovingMs : System.getTimer();
        if (end == null) { end = _walkStartMs; }
        return ((end - _walkStartMs) / 1000.0 + 0.5).toNumber();
    }

    function distanceToGrass() {
        if (_lat == null) { return null; }
        return distanceM(_lat, _lon, _entryLat, _entryLon).toNumber();
    }

    // ---- geometry ----

    function routeLength() as Float {
        var total = 0.0;
        for (var i = 0; i + 1 < _route.size(); i += 1) {
            total += segLength(i);
        }
        return total;
    }

    function segLength(i as Number) as Float {
        var a = _route[i];
        var b = _route[i + 1];
        return distanceM(a[0] / 1000000.0d, a[1] / 1000000.0d, b[0] / 1000000.0d, b[1] / 1000000.0d).toFloat();
    }

    // Point `along` metres down the route, as [lat, lon] doubles.
    function pointAt(along as Float) as Array<Double> {
        for (var i = 0; i + 1 < _route.size(); i += 1) {
            var len = segLength(i);
            if (along <= len && len > 0) {
                var f = along / len;
                var a = _route[i];
                var b = _route[i + 1];
                return [
                    (a[0] + (b[0] - a[0]) * f) / 1000000.0d,
                    (a[1] + (b[1] - a[1]) * f) / 1000000.0d
                ] as Array<Double>;
            }
            along -= len;
        }
        var last = _route[_route.size() - 1];
        return [last[0] / 1000000.0d, last[1] / 1000000.0d] as Array<Double>;
    }

    function distanceM(lat1, lon1, lat2, lon2) as Double {
        var dLat = Math.toRadians(lat2 - lat1);
        var dLon = Math.toRadians(lon2 - lon1);
        var a = Math.pow(Math.sin(dLat / 2), 2)
            + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLon / 2), 2);
        return (2 * 6371008.8d * Math.asin(Math.sqrt(a))).toDouble();
    }
}
