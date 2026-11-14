import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;

(:motion)
class GrassMotionChallenge {
    var _detector;
    var _timer;
    var _onProgress;
    var _onResult;
    var _started = 0;
    var _running = false;
    var _listening = false;
    var _sampleRate = 25;
    var samplesReceived = 0;

    function initialize() {
        _timer = new Timer.Timer();
    }

    function start(onProgress, onResult) {
        begin(onProgress, onResult);
        try {
            _sampleRate = Sensor.getMaxSampleRateForSensorType(:accelerometer);
            if (_sampleRate > 25) { _sampleRate = 25; }
            if (_sampleRate < 10) {
                finish(false);
                return;
            }
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => _sampleRate }
            });
            _listening = true;
            System.println("Motion listener registered at " + _sampleRate + " Hz");
        } catch (error instanceof Lang.Exception) {
            System.println("Motion sensor unavailable: " + error.getErrorMessage());
            finish(false);
        }
    }

    // Mutually exclusive with live sensors; the demo must feed real batches.
    function startDemo(onProgress, onResult) {
        begin(onProgress, onResult);
    }

    function begin(onProgress, onResult) {
        cancel();
        samplesReceived = 0;
        _detector = new GrassMotionDetector();
        _onProgress = onProgress;
        _onResult = onResult;
        _started = System.getTimer();
        _running = true;
        // Five seconds of samples plus one second of callback-delivery grace.
        // Missing input always resolves to retry rather than waiting forever.
        _timer.start(method(:onDeadline), 6000, false);
        _onProgress.invoke(0.0);
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        if (!_running || !_listening || data.accelerometerData == null) { return; }
        var accel = data.accelerometerData;
        samplesReceived += accel.x.size();
        addBatch(accel.x, accel.y, accel.z, _sampleRate);
    }

    function addBatch(x, y, z, sampleRate) {
        if (!_running) { return; }
        _detector.addBatch(x, y, z, sampleRate, System.getTimer() - _started);
        _onProgress.invoke(_detector.getProgress());
    }

    function onDeadline() as Void {
        if (_running) { finish(_detector.passed(System.getTimer() - _started)); }
    }

    function finish(passed) {
        var callback = _onResult;
        cancel();
        callback.invoke(passed);
    }

    // Call on view hide, app inactivity, and app stop. No result after cancel.
    function cancel() {
        _running = false;
        _timer.stop();
        if (_listening) {
            Sensor.unregisterSensorDataListener();
            _listening = false;
        }
        _onProgress = null;
        _onResult = null;
    }
}
