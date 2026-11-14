import Toybox.Lang;
import Toybox.WatchUi;

class touch_grassDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new touch_grassMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}