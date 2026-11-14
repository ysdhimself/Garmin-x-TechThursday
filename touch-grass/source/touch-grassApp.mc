import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
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
        flowState = (flowState == DONE ? PASSIVE : flowState + 1) as FlowState;
        if (flowState == GRASS_TIME) {
            startAlarm();
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

    function onRedraw() as Void {
        if (flowState == TOUCH_GRASS && touchProgress() == 1.0) {
            stopRedraws();
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
