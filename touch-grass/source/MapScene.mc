import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

// The MAP step: a simplified, north-up map in a light Apple Maps style,
// drawn with plain shapes so it appears instantly and needs no map tiles
// or network. It shows a sample park (from fixtures/routes/demo-park.json,
// synthetic data, not a real place) with a few streets, a pond, and contour
// lines for topography, plus a blue dot for your location.
// Points are [latitude, longitude] in microdegrees, as in the fixture.
// Colours stay inside the fēnix 7's 64-colour palette.
module MapScene {

    const LAND = 0xFFFFAA;
    const CONTOUR = 0xFFAA55;
    const PARK = 0xAAFFAA;
    const PARK_EDGE = 0x55AA55;
    const WATER = 0xAAFFFF;
    const ROAD = 0xFFFFFF;
    const ROAD_EDGE = 0xAAAAAA;
    const YOU = 0x0055FF;
    const INK = 0x555555;

    // Where "you" are on the demo map when there is no GPS fix on it.
    const DEMO_YOU = [53546000, -113493800] as Array<Number>;
    // The park, from the fixture.
    const PARK_RING = [
        [53546950, -113492900],
        [53547300, -113492950],
        [53547800, -113492700],
        [53547800, -113491400],
        [53547100, -113491300],
        [53546950, -113491900]
    ] as Array<Array<Number> >;
    const POND = [
        [53547300, -113492300],
        [53547450, -113492400],
        [53547550, -113492000],
        [53547400, -113491800]
    ] as Array<Array<Number> >;
    // Decorative streets: lat1, lon1, lat2, lon2, major (1) or minor (0).
    const STREETS = [
        [53545500, -113497500, 53545500, -113488000, 1],
        [53548300, -113497500, 53548300, -113488000, 1],
        [53545000, -113494600, 53549000, -113494600, 0],
        [53545000, -113490700, 53549000, -113490700, 0],
        [53546000, -113497500, 53546000, -113493800, 0]
    ] as Array<Array<Number> >;

    // The map is centred on this point, and scaled to fit the route and park.
    const CENTER_LAT = 53546900;
    const CENTER_LON = -113492550;
    const FIT_LAT_SPAN = 1800;   // microdegrees of latitude to keep on screen
    const CARD_NOTE = "Demo map - sample data";

    var _s as Float = 1.0;        // screen scale relative to a 260 px display
    var _cx as Number = 0;
    var _cy as Number = 0;
    var _pxPerMicro as Float = 0.09;
    var _cosLat as Float = 0.6;

    function draw(dc as Dc) as Void {
        var w = dc.getWidth();
        _s = w / 260.0;
        _cx = w / 2;
        _cy = (91 * _s).toNumber();
        _cosLat = Math.cos(Math.toRadians(CENTER_LAT / 1000000.0)).toFloat();
        _pxPerMicro = (162 * _s) / FIT_LAT_SPAN;

        dc.setColor(LAND, LAND);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        contours(dc);

        // Green space and pond.
        dc.setColor(PARK, PARK);
        dc.fillPolygon(screen(PARK_RING));
        dc.setColor(PARK_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        outline(dc, screen(PARK_RING));
        dc.setColor(WATER, WATER);
        dc.fillPolygon(screen(POND));

        streets(dc);

        var label = project(CENTER_LAT + 400, -113492100);
        dc.setColor(PARK_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(label[0], label[1], Graphics.FONT_XTINY, "Demo Park",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        you(dc, project(youPoint()[0], youPoint()[1]));
        card(dc, w);
        Compass.draw(dc, w / 2 + (62 * _s).toNumber(), (68 * _s).toNumber(), (28 * _s).toNumber());
    }

    // Soft elevation lines: two concentric hill outlines.
    function contours(dc as Dc) as Void {
        dc.setColor(CONTOUR, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var ring = 0; ring < 2; ring += 1) {
            var dLat = 250 + ring * 220;
            var dLon = 900 + ring * 650;
            var pts = [] as Array<[Number, Number]>;
            for (var i = 0; i < 24; i += 1) {
                var a = i * Math.PI / 12;
                pts.add(project(53546100 + (dLat * Math.sin(a)).toNumber(),
                    -113491500 + (dLon * Math.cos(a)).toNumber()));
            }
            outline(dc, pts);
        }
    }

    // Streets: all the casings first, so crossings merge into clean junctions.
    function streets(dc as Dc) as Void {
        for (var pass = 0; pass < 2; pass += 1) {
            for (var i = 0; i < STREETS.size(); i += 1) {
                var st = STREETS[i];
                var a = project(st[0], st[1]);
                var b = project(st[2], st[3]);
                var width = (st[4] == 1 ? 6.0 : 4.0) * _s;
                dc.setColor(pass == 0 ? ROAD_EDGE : ROAD, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth((pass == 0 ? width + 2 : width).toNumber());
                dc.drawLine(a[0], a[1], b[0], b[1]);
            }
        }
    }

    // The blue location dot, with a pale halo and white ring.
    function you(dc as Dc, p as [Number, Number]) as Void {
        dc.setColor(WATER, WATER);
        dc.fillCircle(p[0], p[1], (13 * _s).toNumber());
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.fillCircle(p[0], p[1], (8 * _s).toNumber());
        dc.setColor(YOU, YOU);
        dc.fillCircle(p[0], p[1], (6 * _s).toNumber());
    }

    // The bottom info card: destination and walk length.
    function card(dc as Dc, w as Number) as Void {
        var cw = (140 * _s).toNumber();
        var ch = (46 * _s).toNumber();
        var x = (w - cw) / 2;
        var y = (186 * _s).toNumber();
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.fillRoundedRectangle(x, y, cw, ch, (10 * _s).toNumber());
        dc.setColor(ROAD_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(x, y, cw, ch, (10 * _s).toNumber());
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + ch / 3, Graphics.FONT_XTINY, "You are here", center);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + ch * 2 / 3, Graphics.FONT_XTINY, CARD_NOTE, center);
    }

    // "You": the live GPS fix when it falls on this map, otherwise the
    // route's start, so the demo works wherever the watch or simulator is.
    function youPoint() as Array<Number> {
        var info = Position.getInfo();
        if (info.position != null && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            var deg = (info.position as Position.Location).toDegrees();
            var lat = (deg[0] * 1000000).toNumber();
            var lon = (deg[1] * 1000000).toNumber();
            if ((lat - CENTER_LAT).abs() < 3000 && (lon - CENTER_LON).abs() < 5000) {
                return [lat, lon];
            }
        }
        return DEMO_YOU;
    }

    // Microdegrees to screen pixels, north up, flat-earth scaled by cos(lat).
    function project(lat as Number, lon as Number) as [Number, Number] {
        var x = _cx + ((lon - CENTER_LON) * _cosLat * _pxPerMicro).toNumber();
        var y = _cy - ((lat - CENTER_LAT) * _pxPerMicro).toNumber();
        return [x, y];
    }

    function screen(points as Array<Array<Number> >) as Array<[Number, Number]> {
        var out = [] as Array<[Number, Number]>;
        for (var i = 0; i < points.size(); i += 1) {
            out.add(project(points[i][0], points[i][1]));
        }
        return out;
    }

    // Draws a closed outline through the points.
    function outline(dc as Dc, pts as Array<[Number, Number]>) as Void {
        for (var i = 0; i < pts.size(); i += 1) {
            var a = pts[i];
            var b = pts[(i + 1) % pts.size()];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
    }

}
