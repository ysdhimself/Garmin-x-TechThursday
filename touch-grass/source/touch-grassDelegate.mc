import Toybox.Lang;
import Toybox.WatchUi;

class touch_grassDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // START (or a tap) moves to the next flow state.
    function onSelect() as Boolean {
        getApp().advanceFlow();
        return true;
    }

    function onBack() as Boolean {
        return getApp().cancelPhoto();
    }

}
