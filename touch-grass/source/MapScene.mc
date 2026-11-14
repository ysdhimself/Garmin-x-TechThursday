import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;

// The MAP step: a simplified, north-up map in a light Apple Maps style,
// drawn with plain shapes so it appears instantly and needs no map tiles
// or network. Calgary: Platform Calgary to Central Library Garden.
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
    const ROUTE_COLOR = 0x5555FF;
    const INK = 0x555555;

    // Platform Calgary: where "you" start when there is no GPS fix.
    const DEMO_YOU = [51044277, -114055682] as Array<Number>;
    // Central Library Garden, from demo-park.json.
    const PARK_RING = [
        [51045460, -114055422],
        [51045400, -114054800],
        [51045900, -114054600],
        [51046100, -114054900],
        [51046100, -114055300],
        [51045700, -114055600]
    ] as Array<Array<Number> >;
    const POND = [
        [51045750, -114054900],
        [51045850, -114055050],
        [51045900, -114054750],
        [51045800, -114054650]
    ] as Array<Array<Number> >;
    // Route: Platform Calgary northbound to the library entrance.
    const ROUTE = [
        [51044277, -114055682],
        [51044298, -114055620],
        [51044312, -114055584],
        [51044452, -114055591],
        [51044503, -114055604],
        [51045212, -114055553],
        [51045453, -114055540],
        [51045460, -114055422]
    ] as Array<Array<Number> >;
    // Decorative streets: lat1, lon1, lat2, lon2, major (1) or minor (0).
    const STREETS = [
        [51044200, -114057000, 51044200, -114053500, 1],
        [51046300, -114057000, 51046300, -114053500, 1],
        [51045000, -114057000, 51045000, -114053500, 0],
        [51043500, -114055600, 51046800, -114055600, 0],
        [51043500, -114054500, 51046800, -114054500, 0]
    ] as Array<Array<Number> >;

    const CENTER_LAT = 51045100;
    const CENTER_LON = -114055100;
    const FIT_LAT_SPAN = 2400;
    const CARD_NOTE = "Platform Calgary to Library";

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
        route(dc);

        var label = project(51045750, -114055000);
        dc.setColor(PARK_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(label[0], label[1], Graphics.FONT_XTINY, "Library Garden",
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
                pts.add(project(51045800 + (dLat * Math.sin(a)).toNumber(),
                    -114054800 + (dLon * Math.cos(a)).toNumber()));
            }
            outline(dc, pts);
        }
    }

    // The walking route as a dashed blue line from origin to destination.
    function route(dc as Dc) as Void {
        dc.setColor(ROUTE_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((3.0 * _s).toNumber());
        var pts = screen(ROUTE);
        for (var i = 0; i + 1 < pts.size(); i += 1) {
            dc.drawLine(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]);
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
