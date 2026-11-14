import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.WatchUi;

// Walk Monitor: shows the live GPS / heart-rate data the simulator plays from demo/walk/fixtures/*.fit,
// measured against the walk plan in route-edmonton.json. Test tool only, not the Touch Grass app.
class WalkMonitorApp extends Application.AppBase {
    var view;

    function initialize() { AppBase.initialize(); }

    function onStart(state) as Void {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensor));
    }

    function onStop(state) as Void {
        // Turn GPS and sensors off on exit.
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        Sensor.enableSensorEvents(null);
        Sensor.setEnabledSensors([]);
        if (view != null) { view.stopTimer(); }
    }

    function getInitialView() {
        view = new WalkMonitorView();
        return [view, new WalkMonitorDelegate(view)];
    }

    function onPosition(info as Position.Info) as Void { if (view != null) { view.onPosition(info); } }

    function onSensor(info as Sensor.Info) as Void { if (view != null) { view.onSensor(info); } }
}

// SELECT / START resets the counters so the next file can be played from a clean state.
// UP / DOWN switch between the WALK and SENSORS pages.
class WalkMonitorDelegate extends WatchUi.BehaviorDelegate {
    var view;
    function initialize(v) { BehaviorDelegate.initialize(); view = v; }
    function onSelect() { view.reset(); return true; }
    function onNextPage() { view.nextPage(1); return true; }
    function onPreviousPage() { view.nextPage(-1); return true; }
}
