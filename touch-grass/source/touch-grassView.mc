import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class touch_grassView extends WatchUi.View {

    // Indexed by FlowState; keep in the same order as the enum.
    private const TITLES = [
        "Passive",
        "Touch grass time!",
        "Get to the grass",
        "You arrived",
        "You proved it",
        "All done"
    ];
    private const DETAILS = [
        "Waiting for grass time",
        "Time to go outside",
        "Map goes here",
        "Prove it",
        "Touch the grass",
        "Back to passive next"
    ];

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var app = getApp();
        var state = app.flowState;
        if (state == PASSIVE) {
            PixelScene.drawPassive(dc);
            return;
        }
        if (state == GRASS_TIME) {
            PixelScene.drawGrassTime(dc);
            return;
        }
        if (state == MAP) {
            MapScene.draw(dc);
            return;
        }
        if (state == TOUCH_GRASS) {
            PixelScene.drawTouchGrass(dc, app.touchProgress());
            return;
        }
        var x = dc.getWidth() / 2;
        var y = dc.getHeight() / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(x, y - 55, Graphics.FONT_XTINY, (state + 1) + "/" + TITLES.size(), center);
        dc.drawText(x, y - 10, Graphics.FONT_SMALL, TITLES[state], center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + 25, Graphics.FONT_XTINY, DETAILS[state], center);
        dc.drawText(x, y + 75, Graphics.FONT_XTINY, "START: next", center);
    }

}
