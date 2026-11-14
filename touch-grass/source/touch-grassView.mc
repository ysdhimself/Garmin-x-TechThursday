import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class touch_grassView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        getApp().viewShown();
    }

    function onHide() as Void {
        getApp().viewHidden();
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
        if (state == WALK) {
            PixelScene.drawWalk(dc);
            return;
        }
        if (state == SUMMARY) {
            PixelScene.drawSummary(dc);
            return;
        }
        if (state == TOUCH_GRASS) {
            PixelScene.drawTouchGrass(dc, app.touchProgress());
            return;
        }
        if (state == PROVE_IT) {
            PixelScene.drawProveIt(dc, app.photoSession);
            return;
        }
    }

}
