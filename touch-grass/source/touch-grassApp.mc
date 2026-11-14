import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The Touch Grass flow, in order. DONE returns to PASSIVE.
enum FlowState {
    PASSIVE,
    GRASS_TIME,
    MAP,
    PROVE_IT,
    TOUCH_GRASS,
    DONE
}

class touch_grassApp extends Application.AppBase {

    var flowState as FlowState = PASSIVE;

    private const FAKE_TOUCH_MS = 2500;
    // How long "GRASS TOUCHED" shows before the flow advances on its own.
    private const TOUCHED_HOLD_MS = 2000;
    // How long "All done" shows before returning to the title screen.
    private const DONE_HOLD_MS = 2000;
    private var _doneAt as Number = 0;
    private var _mapPushed as Boolean = false;
    private var _touchStartedAt as Number? = null;
    private var _redrawTimer as Timer.Timer? = null;
    // Two clock ring cycles, so every other shaking burst buzzes.
    private const BUZZ_EVERY_MS = 2 * PixelScene.RING_CYCLE_MS;
    private var _lastBuzz as Number = 0;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
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
        flowState = (flowState == DONE ? PASSIVE : flowState + 1) as FlowState;
        if (flowState == MAP) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            // The watch's own map when it has one; otherwise MapScene is
            // drawn by the main view.
            if (WatchUi has :MapTrackView) {
                _mapPushed = true;
                WatchUi.pushView(new touch_grassMapView(), new touch_grassDelegate(), WatchUi.SLIDE_IMMEDIATE);
            }
        }
        if (flowState == GRASS_TIME) {
            // Start GPS a step early so a fix is ready when the map opens.
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            startAlarm();
        } else if (flowState == DONE) {
            _doneAt = System.getTimer();
            startRedraws(250);
        } else {
            stopRedraws();
        }
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

    // GPS fixes are read with Position.getInfo() when the map draws.
    function onPosition(info as Position.Info) as Void {
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
        // "All done" shows briefly, then the flow returns to the title screen.
        if (flowState == DONE && System.getTimer() - _doneAt >= DONE_HOLD_MS) {
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
