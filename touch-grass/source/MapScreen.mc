import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The MAP step on the watch's built-in map. The map shows a box centred on
// the latest GPS fix, ZOOM_HALF_SPAN_M metres out each way (smaller zooms
// in). The location marker is drawn by us, not the map, so its size is ours
// to choose. Without any fix it shows the demo venue (downtown Calgary)
// behind a "Finding GPS..." label until one arrives.
class touch_grassMapView extends WatchUi.MapView {

    // Half the visible width and height, in metres.
    private const ZOOM_HALF_SPAN_M = 80.0;
    private const METRES_PER_DEG_LAT = 111320.0;
    // Re-centre only after moving this far, so the map doesn't jitter.
    private const RECENTRE_M = 15.0;
    private const FALLBACK_LAT = 51.04437;
    private const FALLBACK_LON = -114.05563;
    private const YOU = 0x0055FF;

    // The centre of the map box, and the latest fix (the dot moves with the
    // fix even between re-centres).
    private var _lat as Float = FALLBACK_LAT;
    private var _lon as Float = FALLBACK_LON;
    private var _fixLat as Float = FALLBACK_LAT;
    private var _fixLon as Float = FALLBACK_LON;
    private var _hasFix as Boolean = false;

    // The map draws (and loads) underneath a pixel-art loading screen for
    // this long, so you never see it filling in. Tune to taste.
    private const COVER_MS = 2500;
    private var _shownAt as Number = 0;
    private var _redraw as Timer.Timer? = null;

    function initialize() {
        MapView.initialize();
        MapView.setMapMode(WatchUi.MAP_MODE_PREVIEW);
        var settings = System.getDeviceSettings();
        MapView.setScreenVisibleArea(0, 0, settings.screenWidth, settings.screenHeight);
        readPosition();
        showArea();
    }

    function onShow() as Void {
        _shownAt = System.getTimer();
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 250, true);
        _redraw = timer;
    }

    function onHide() as Void {
        stopTimer();
    }

    // Keeps redrawing so the cover lifts on time and the compass follows
    // the heading.
    function onTick() as Void {
        WatchUi.requestUpdate();
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
        var w = dc.getWidth();
        if (_hasFix) {
            drawYou(dc);
        }
        Compass.draw(dc, w / 2 + w * 24 / 100, dc.getHeight() / 2 - w * 24 / 100, w * 12 / 100);
        if (!_hasFix) {
            // Be honest that this is not the user's area yet.
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
        // Before a real fix the watch (and the simulator) can report a
        // placeholder such as 180, 180. Ignore anything that is not a place;
        // handing the map an impossible area crashes it.
        if (lat.abs() > 90.0 || lon.abs() > 180.0) {
            return;
        }
        var movedLat = (lat - _lat) * METRES_PER_DEG_LAT;
        var movedLon = (lon - _lon) * METRES_PER_DEG_LAT * Math.cos(Math.toRadians(lat));
        var first = !_hasFix;
        _hasFix = true;
        _fixLat = lat;
        _fixLon = lon;
        if (first || movedLat.abs() > RECENTRE_M || movedLon.abs() > RECENTRE_M) {
            _lat = lat;
            _lon = lon;
            showArea();
        }
    }

    // A small blue dot with a white ring where the fix falls inside the map
    // box, plus a short pointer in the direction you face (north is up).
    private function drawYou(dc as Dc) as Void {
        var w = dc.getWidth();
        var metresPerPixel = 2.0 * ZOOM_HALF_SPAN_M / w;
        var east = (_fixLon - _lon) * METRES_PER_DEG_LAT * Math.cos(Math.toRadians(_lat));
        var north = (_fixLat - _lat) * METRES_PER_DEG_LAT;
        var x = w / 2 + (east / metresPerPixel).toNumber();
        var y = dc.getHeight() / 2 - (north / metresPerPixel).toNumber();
        var r = w * 2 / 100;

        var heading = Compass.heading();
        if (heading != null) {
            var h = heading as Float;
            dc.setColor(YOU, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [x + ((r + r * 2) * Math.sin(h)).toNumber(), y - ((r + r * 2) * Math.cos(h)).toNumber()],
                [x + ((r + r / 2) * Math.sin(h - 1.2)).toNumber(), y - ((r + r / 2) * Math.cos(h - 1.2)).toNumber()],
                [x + ((r + r / 2) * Math.sin(h + 1.2)).toNumber(), y - ((r + r / 2) * Math.cos(h + 1.2)).toNumber()]
            ] as Array<[Number, Number]>);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r + 2);
        dc.setColor(YOU, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
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
