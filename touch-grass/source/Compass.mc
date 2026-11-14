import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;

// A small compass dial for the corner of the map. The needle and the "N"
// point to true north, so the dial turns as you turn: face east and north
// swings to your left. The map itself stays north-up.
module Compass {

    const FACE = 0x000000;
    const NORTH = 0xFF0000;
    const DIM = 0xAAAAAA;

    // The way the watch faces, in radians clockwise from true north, or null
    // when nothing reports it. Same sources as demo/walk's Walk Monitor: the
    // compass first, then the GPS heading (direction of travel when moving).
    function heading() as Float? {
        var sensors = Sensor.getInfo();
        if (sensors != null && sensors.heading != null) {
            return sensors.heading;
        }
        var position = Position.getInfo();
        if (position != null && position.heading != null) {
            return position.heading;
        }
        return null;
    }

    // Draws the dial centred on (cx, cy) with the given outer radius: a dark
    // face with a fine bezel, tick marks every 45 degrees, a red "N" that sits
    // at north, and a slim needle (red toward north, white toward south).
    function draw(dc as Dc, cx as Number, cy as Number, r as Number) as Void {
        var h = heading();
        var known = h != null;
        // Where north sits on the dial: opposite to the way we face.
        var a = known ? -(h as Float) : 0.0;
        var accent = known ? NORTH : DIM;

        // Bezel and face.
        dc.setColor(0xFFFFFF, 0xFFFFFF);
        dc.fillCircle(cx, cy, r + 2);
        dc.setColor(FACE, FACE);
        dc.fillCircle(cx, cy, r);

        // Ticks every 45 degrees; the north one is replaced by the "N".
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        for (var i = 1; i < 8; i += 1) {
            var cardinal = i % 2 == 0;
            dc.setPenWidth(cardinal ? 2 : 1);
            var from = pointAt(cx, cy, r - (cardinal ? 6 : 4), a + i * Math.PI / 4);
            var to = pointAt(cx, cy, r - 1, a + i * Math.PI / 4);
            dc.drawLine(from[0], from[1], to[0], to[1]);
        }
        dc.setPenWidth(1);

        // Needle.
        var length = r * 0.42;
        var half = r * 0.12;
        var left = pointAt(cx, cy, half, a - Math.PI / 2);
        var right = pointAt(cx, cy, half, a + Math.PI / 2);
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pointAt(cx, cy, length, a), left, right] as Array<[Number, Number]>);
        dc.setColor(known ? 0xFFFFFF : DIM, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pointAt(cx, cy, length * 0.8, a + Math.PI), left, right] as Array<[Number, Number]>);
        dc.setColor(FACE, FACE);
        dc.fillCircle(cx, cy, 2);

        // The "N", kept upright, at the north edge of the dial.
        var n = pointAt(cx, cy, r - 9, a);
        PixelFont.draw(dc, "N", n[0], n[1] - 7, 2, accent, null);
    }

    // A point dist pixels from the centre, angle radians clockwise from up.
    function pointAt(cx as Number, cy as Number, dist as Numeric, angle as Float) as [Number, Number] {
        return [cx + (dist * Math.sin(angle)).toNumber(), cy - (dist * Math.cos(angle)).toNumber()];
    }

}
