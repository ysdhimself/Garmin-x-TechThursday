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
        var x = dc.getWidth() / 2;
        var y = dc.getHeight() / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var detail = DETAILS[state];
        var hint = "START: next";

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (state == TOUCH_GRASS) {
            var progress = app.touchProgress();
            if (progress == null) {
                hint = "START: touch grass";
            } else {
                // Progress ring around the screen edge, clockwise from the top.
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(8);
                if (progress >= 1.0) {
                    dc.drawCircle(x, y, x - 4);
                    detail = "All done!";
                } else {
                    if (progress > 0.0) {
                        dc.drawArc(x, y, x - 4, Graphics.ARC_CLOCKWISE, 90, 90 - 360 * progress);
                    }
                    detail = "Touching grass...";
                    hint = "";
                }
                dc.setPenWidth(1);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
        }

        dc.drawText(x, y - 55, Graphics.FONT_XTINY, (state + 1) + "/" + TITLES.size(), center);
        dc.drawText(x, y - 10, Graphics.FONT_SMALL, TITLES[state], center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + 25, Graphics.FONT_XTINY, detail, center);
        dc.drawText(x, y + 75, Graphics.FONT_XTINY, hint, center);
    }

}
