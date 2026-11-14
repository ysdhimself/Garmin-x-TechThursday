import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The MAP step on the watch's built-in map. MapTrackView draws the device's
// own location on the on-board map, so this only decides which area to show:
// a box centred on the latest GPS fix, ZOOM_HALF_SPAN_M metres out each way.
// A smaller number zooms in. Without any fix it shows FALLBACK until one
// arrives (the sample area from fixtures/routes/demo-park.json).
class touch_grassMapView extends WatchUi.MapTrackView {

    // Half the visible width and height, in metres.
    private const ZOOM_HALF_SPAN_M = 150.0;
    private const METRES_PER_DEG_LAT = 111320.0;
    // Re-centre only after moving this far, so the map doesn't jitter.
    private const RECENTRE_M = 15.0;
    private const FALLBACK_LAT = 53.546;
    private const FALLBACK_LON = -113.4938;

    private var _lat as Float = FALLBACK_LAT;
    private var _lon as Float = FALLBACK_LON;
    private var _hasFix as Boolean = false;

    // The map draws (and loads) underneath a pixel-art loading screen for
    // this long, so you never see it filling in. Tune to taste.
    private const COVER_MS = 2500;
    private var _shownAt as Number = 0;
    private var _redraw as Timer.Timer? = null;

    function initialize() {
        MapTrackView.initialize();
        MapView.setMapMode(WatchUi.MAP_MODE_PREVIEW);
        var settings = System.getDeviceSettings();
        MapView.setScreenVisibleArea(0, 0, settings.screenWidth, settings.screenHeight);
        readPosition();
        showArea();
    }

    // Redraw regularly while the cover is up so it lifts on time.
    function onShow() as Void {
        _shownAt = System.getTimer();
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 200, true);
        _redraw = timer;
    }

    function onHide() as Void {
        stopTimer();
    }

    function onTick() as Void {
        if (covered()) {
            WatchUi.requestUpdate();
        } else {
            stopTimer();
            WatchUi.requestUpdate();
        }
    }

    private function stopTimer() as Void {
        var timer = _redraw;
        if (timer != null) {
            timer.stop();
            _redraw = null;
        }
    }

    // True while the loading screen should hide the map.
    private function covered() as Boolean {
        return System.getTimer() - _shownAt < COVER_MS;
    }

    function onUpdate(dc as Dc) as Void {
        readPosition();
        MapView.onUpdate(dc);
        if (covered()) {
            PixelScene.drawMapLoading(dc);
            return;
        }
        if (!_hasFix) {
            // Be honest that this is not the user's area yet.
            var w = dc.getWidth();
            var y = dc.getHeight() * 82 / 100;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.fillRoundedRectangle(w / 2 - w * 3 / 10, y - 14, w * 6 / 10, 28, 12);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, "Finding GPS...",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Takes the newest usable fix and re-frames the map when it has moved.
    private function readPosition() as Void {
        var info = Position.getInfo();
        if (info.position == null || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return;
        }
        var deg = (info.position as Position.Location).toDegrees();
        var lat = deg[0].toFloat();
        var lon = deg[1].toFloat();
        var movedLat = (lat - _lat) * METRES_PER_DEG_LAT;
        var movedLon = (lon - _lon) * METRES_PER_DEG_LAT * Math.cos(Math.toRadians(lat));
        var first = !_hasFix;
        _hasFix = true;
        if (first || movedLat.abs() > RECENTRE_M || movedLon.abs() > RECENTRE_M) {
            _lat = lat;
            _lon = lon;
            showArea();
        }
    }

    // Frames a square box around the current centre.
    private function showArea() as Void {
        var dLat = ZOOM_HALF_SPAN_M / METRES_PER_DEG_LAT;
        var dLon = dLat / Math.cos(Math.toRadians(_lat));
        try {
            MapView.setMapVisibleArea(
                new Position.Location({:latitude => _lat + dLat, :longitude => _lon - dLon, :format => :degrees}),
                new Position.Location({:latitude => _lat - dLat, :longitude => _lon + dLon, :format => :degrees}));
        } catch (ex) {
            System.println("Map area rejected: " + ex.getErrorMessage());
        }
    }
}
