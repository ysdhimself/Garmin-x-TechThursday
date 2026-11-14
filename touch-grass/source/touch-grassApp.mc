import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The Touch Grass flow, in order. SUMMARY returns to PASSIVE.
enum FlowState {
    PASSIVE,
    GRASS_TIME,
    MAP,
    WALK,
    PROVE_IT,
    TOUCH_GRASS,
    SUMMARY
}

class touch_grassApp extends Application.AppBase {

    var flowState as FlowState = PASSIVE;
    var photoSession as PhotoSession;
    var walkPlanRequest as WalkPlanRequest;
    private var _visible as Boolean = false;
    private var _active as Boolean = true;

    private const FAKE_TOUCH_MS = 2500;
    // How long "GRASS TOUCHED" shows before the flow advances on its own.
    private const TOUCHED_HOLD_MS = 2000;
    // How long the walk SUMMARY shows before returning to the title screen.
    private const SUMMARY_HOLD_MS = 5000;
    private var _summaryAt as Number = 0;
    private var _mapPushed as Boolean = false;
    private var _touchStartedAt as Number? = null;
    private var _redrawTimer as Timer.Timer? = null;
    // Two clock ring cycles, so every other shaking burst buzzes.
    private const BUZZ_EVERY_MS = 2 * PixelScene.RING_CYCLE_MS;
    private var _lastBuzz as Number = 0;

    function initialize() {
        AppBase.initialize();
        photoSession = new PhotoSession();
        walkPlanRequest = new WalkPlanRequest();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        var config = WatchUi.loadResource(Rez.JsonData.localConfig) as Dictionary;
        var url = config["backendUrl"] as String;
        if (url.length() > 0) {
            Application.Properties.setValue("PhotoBaseUrl", url);
            Application.Properties.setValue("WalkPlanUrl", url);
        }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        _active = false;
        photoSession.stop();
        stopRedraws();
    }

    function onInactive(state as Dictionary?) as Void {
        _active = false;
        photoSession.stop();
    }

    function onActive(state as Dictionary?) as Void {
        _active = true;
        resumePhoto();
    }

    function viewShown() as Void {
        _visible = true;
        resumePhoto();
    }

    function viewHidden() as Void {
        _visible = false;
        photoSession.stop();
    }

    private function resumePhoto() as Void {
        if (_active && _visible && flowState == PROVE_IT) {
            photoSession.start();
        }
    }

    function cancelPhoto() as Boolean {
        if (flowState != PROVE_IT) { return false; }
        photoSession.stop();
        flowState = MAP;
        WatchUi.requestUpdate();
        return true;
    }

    function photoPassed() as Void {
        if (!_active || !_visible || flowState != PROVE_IT) { return; }
        flowState = TOUCH_GRASS;
        startRedraws(100);
        WatchUi.requestUpdate();
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new touch_grassView(), new touch_grassDelegate() ];
    }

    // Placeholder: a button press moves to the next state until real
    // triggers (backend, arrival, motion challenge) replace it.
    // In TOUCH_GRASS, the first press starts the fake touch challenge and
    // presses are ignored until it finishes.
    function advanceFlow() as Void {
        if (flowState == PROVE_IT) {
            if (_active && _visible) { photoSession.retry(); }
            return;
        }
        if (flowState == TOUCH_GRASS) {
            var progress = touchProgress();
            if (progress == null) {
                startFakeTouch();
                return;
            }
            if (progress < 1.0) {
                return;
            }
            _touchStartedAt = null;
        }
        if (flowState == MAP) {
            // Leaving the map: turn GPS off and close the built-in map view.
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
            if (_mapPushed) {
                _mapPushed = false;
                WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            }
        }
        if (flowState == WALK) {
            // Leaving the walk (arrived, or START to skip): keep the stats, GPS off.
            WalkData.finish();
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        }
        flowState = (flowState == SUMMARY ? PASSIVE : flowState + 1) as FlowState;
        if (flowState == MAP) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            // The watch's own map when it has one; otherwise MapScene is
            // drawn by the main view.
            if (WatchUi has :MapView) {
                _mapPushed = true;
                WatchUi.pushView(new touch_grassMapView(), new touch_grassDelegate(), WatchUi.SLIDE_IMMEDIATE);
            }
        }
        if (flowState == GRASS_TIME) {
            walkPlanRequest.reset();
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            walkPlanRequest.request();
            startAlarm();
        } else if (flowState == WALK) {
            // Live data (simulator Activity Data playback / GPS), or the built-in demo walk after 3 s.
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            var config = WatchUi.loadResource(Rez.JsonData.localConfig) as Dictionary;
            WalkData.start(config["mockWalk"] == true);
            startRedraws(1000);
        } else if (flowState == SUMMARY) {
            _summaryAt = System.getTimer();
            startRedraws(250);
        } else {
            stopRedraws();
        }
        if (flowState == PROVE_IT) { resumePhoto(); }
        WatchUi.requestUpdate();
    }

    // Fake touch challenge progress: null before START, then 0.0 to 1.0.
    function touchProgress() as Float? {
        var startedAt = _touchStartedAt;
        if (startedAt == null) {
            return null;
        }
        var progress = (System.getTimer() - startedAt).toFloat() / FAKE_TOUCH_MS;
        return progress < 1.0 ? progress : 1.0;
    }

    // The accelerometer is unreliable, so this stands in for
    // GrassMotionChallenge: it always passes after FAKE_TOUCH_MS.
    private function startFakeTouch() as Void {
        _touchStartedAt = System.getTimer();
        startRedraws(100);
        WatchUi.requestUpdate();
    }

    // Buzz now, then keep redrawing so the alarm clock rings; onRedraw
    // buzzes again every BUZZ_EVERY_MS while the step stays open.
    private function startAlarm() as Void {
        buzz();
        // Skip the next boundary if it is under half a period away, so the
        // first repeat comes 2–6 seconds after this buzz, not right on top.
        _lastBuzz = (System.getTimer() + BUZZ_EVERY_MS / 2) / BUZZ_EVERY_MS;
        startRedraws(PixelScene.RING_FRAME_MS);
    }

    // Three quick pulses, about as long as one burst of clock shaking.
    private function buzz() as Void {
        if (Attention has :vibrate) {
            var pulses = [] as Array<Attention.VibeProfile>;
            for (var i = 0; i < 3; i += 1) {
                pulses.add(new Attention.VibeProfile(100, 250));
                pulses.add(new Attention.VibeProfile(0, 100));
            }
            Attention.vibrate(pulses);
        }
    }

    // Redraws the screen every periodMs for animations.
    private function startRedraws(periodMs as Number) as Void {
        stopRedraws();
        var timer = new Timer.Timer();
        timer.start(method(:onRedraw), periodMs, true);
        _redrawTimer = timer;
    }

    private function stopRedraws() as Void {
        var timer = _redrawTimer;
        if (timer != null) {
            timer.stop();
            _redrawTimer = null;
        }
    }

    function onPosition(info as Position.Info) as Void {
        if (flowState == GRASS_TIME || flowState == MAP) {
            walkPlanRequest.request();
        }
        WatchUi.requestUpdate();
    }

    function onRedraw() as Void {
        // Once the challenge passes, show "GRASS TOUCHED" briefly, then
        // move on by itself (START skips the wait).
        var startedAt = _touchStartedAt;
        if (flowState == TOUCH_GRASS && startedAt != null
                && System.getTimer() - startedAt >= FAKE_TOUCH_MS + TOUCHED_HOLD_MS) {
            advanceFlow();
            return;
        }
        // The walk updates once a second until arrival, then holds on ARRIVED until START.
        if (flowState == WALK && !WalkData.arrived()) {
            WalkData.tick();
            if (WalkData.arrived()) {
                stopRedraws();
            }
        }
        // The summary shows for SUMMARY_HOLD_MS, then back to the title screen.
        if (flowState == SUMMARY && System.getTimer() - _summaryAt >= SUMMARY_HOLD_MS) {
            advanceFlow();
            return;
        }
        if (flowState == GRASS_TIME) {
            // Buzz on each new BUZZ_EVERY_MS boundary, which lines up with
            // the start of a clock-shaking burst.
            var slot = System.getTimer() / BUZZ_EVERY_MS;
            if (slot != _lastBuzz) {
                _lastBuzz = slot;
                buzz();
            }
        }
        WatchUi.requestUpdate();
    }

}

function getApp() as touch_grassApp {
    return Application.getApp() as touch_grassApp;
}
