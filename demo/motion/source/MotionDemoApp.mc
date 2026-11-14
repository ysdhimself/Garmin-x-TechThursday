import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class MotionDemoApp extends Application.AppBase {
    var view;
    function initialize() { AppBase.initialize(); }
    function getInitialView() {
        view = new MotionDemoView();
        return [view, new MotionDemoDelegate(view)];
    }
    function onInactive(state) as Void {
        if (view != null && view.status == :running) { view.cancel(); }
    }
    function onStop(state) as Void { if (view != null) { view.cancel(); } }
}

class MotionDemoView extends WatchUi.View {
    var challenge;
    var timer;
    var mode = 0;
    var names = ["LIVE SENSOR", "DEMO: PETTING", "DEMO: STILL", "DEMO: BRIEF", "DEMO: GAP"];
    var status = :ready;
    var progress = 0.0;
    var second = 0;

    function initialize() {
        View.initialize();
        challenge = new GrassMotionChallenge();
        timer = new Timer.Timer();
    }

    function start() {
        cancel();
        status = :running;
        second = 0;
        if (mode == 0) {
            challenge.start(method(:onProgress), method(:onResult));
        } else {
            challenge.startDemo(method(:onProgress), method(:onResult));
            timer.start(method(:feed), 1000, true);
        }
        WatchUi.requestUpdate();
    }

    function feed() as Void {
        if (second < 5 && !(mode == 4 && second == 2)) {
            var batch = motionBatch(mode - 1, second, 0);
            challenge.addBatch(batch[0], batch[1], batch[2], 25);
        }
        second += 1;
        if (second >= 5) { timer.stop(); }
    }

    function onProgress(seconds) {
        progress = seconds;
        WatchUi.requestUpdate();
    }

    function onResult(passed) {
        timer.stop();
        status = passed ? :passed : :retry;
        System.println(names[mode] + ": " + (passed ? "passed" : "retry") + " (" + progress + "s accepted)");
        if (mode == 0) { System.println("Accelerometer samples received: " + challenge.samplesReceived); }
        WatchUi.requestUpdate();
    }

    function cancel() {
        challenge.cancel();
        timer.stop();
        status = :ready;
        progress = 0.0;
        WatchUi.requestUpdate();
    }

    function nextMode(delta) {
        cancel();
        mode = (mode + delta + names.size()) % names.size();
    }

    function onHide() as Void { cancel(); }

    function onUpdate(dc) as Void {
        var cx = dc.getWidth() / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, 30, Graphics.FONT_XTINY, names[mode], Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        var title = "TOUCH GRASS";
        if (status == :passed) { title = "GRASS TOUCHED"; }
        if (status == :retry) { title = "TRY AGAIN"; }
        var missingSensor = mode == 0 && status == :retry && challenge.samplesReceived == 0;
        if (missingSensor) { title = "NO SENSOR DATA"; }
        dc.drawText(cx, 60, Graphics.FONT_SMALL, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var line = "Pet gently for 5s";
        if (status == :running) { line = progress.format("%.1f") + " / 5.0s motion"; }
        if (status == :passed) { line = "Humanity renewed"; }
        if (status == :retry) { line = "Keep waving gently"; }
        if (missingSensor) { line = "Check sensor source"; }
        dc.drawText(cx, 96, Graphics.FONT_XTINY, line, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.fillRectangle(cx - 65, 131, 130, 8);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        dc.fillRectangle(cx - 65, 131, (130 * progress / 5).toNumber(), 8);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, 151, Graphics.FONT_XTINY, "START: " + (status == :running ? "cancel" : "begin"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 175, Graphics.FONT_XTINY, "UP/DOWN: mode", Graphics.TEXT_JUSTIFY_CENTER);
        var footer = "Motion, not contact";
        if (mode == 0 && status != :ready) { footer = "Samples: " + challenge.samplesReceived; }
        dc.drawText(cx, 198, Graphics.FONT_XTINY, footer, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class MotionDemoDelegate extends WatchUi.BehaviorDelegate {
    var view;
    function initialize(v) { BehaviorDelegate.initialize(); view = v; }
    function onSelect() as Boolean {
        if (view.status == :running) { view.cancel(); } else { view.start(); }
        return true;
    }
    function onNextPage() as Boolean { view.nextMode(1); return true; }
    function onPreviousPage() as Boolean { view.nextMode(-1); return true; }
    function onBack() as Boolean {
        if (view.status == :running) { view.cancel(); return true; }
        return false;
    }
}
