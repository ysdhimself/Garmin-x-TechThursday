import Toybox.Application;
import Toybox.Lang;
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
    function advanceFlow() as Void {
        flowState = (flowState == DONE ? PASSIVE : flowState + 1) as FlowState;
        WatchUi.requestUpdate();
    }

}

function getApp() as touch_grassApp {
    return Application.getApp() as touch_grassApp;
}
