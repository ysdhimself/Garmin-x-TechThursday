import Toybox.Graphics;
import Toybox.Lang;

// Chunky 5 × 7 pixel font drawn with rectangles, so text matches the
// app's pixel-art style at any scale. Uppercase only; lowercase letters
// are drawn as uppercase and unknown characters as spaces.
module PixelFont {

    const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.!?/-'";
    // Seven rows per glyph in CHARS order; bit 4 is the leftmost column.
    const ROWS = [
        14, 17, 17, 31, 17, 17, 17, // A
        30, 17, 17, 30, 17, 17, 30, // B
        14, 17, 16, 16, 16, 17, 14, // C
        30, 17, 17, 17, 17, 17, 30, // D
        31, 16, 16, 30, 16, 16, 31, // E
        31, 16, 16, 30, 16, 16, 16, // F
        14, 17, 16, 23, 17, 17, 15, // G
        17, 17, 17, 31, 17, 17, 17, // H
        14, 4, 4, 4, 4, 4, 14, // I
        7, 2, 2, 2, 2, 18, 12, // J
        17, 18, 20, 24, 20, 18, 17, // K
        16, 16, 16, 16, 16, 16, 31, // L
        17, 27, 21, 21, 17, 17, 17, // M
        17, 17, 25, 21, 19, 17, 17, // N
        14, 17, 17, 17, 17, 17, 14, // O
        30, 17, 17, 30, 16, 16, 16, // P
        14, 17, 17, 17, 21, 18, 13, // Q
        30, 17, 17, 30, 20, 18, 17, // R
        15, 16, 16, 14, 1, 1, 30, // S
        31, 4, 4, 4, 4, 4, 4, // T
        17, 17, 17, 17, 17, 17, 14, // U
        17, 17, 17, 17, 17, 10, 4, // V
        17, 17, 17, 21, 21, 21, 10, // W
        17, 17, 10, 4, 10, 17, 17, // X
        17, 17, 10, 4, 4, 4, 4, // Y
        31, 1, 2, 4, 8, 16, 31, // Z
        14, 17, 19, 21, 25, 17, 14, // 0
        4, 12, 4, 4, 4, 4, 14, // 1
        14, 17, 1, 2, 4, 8, 31, // 2
        31, 2, 4, 2, 1, 17, 14, // 3
        2, 6, 10, 18, 31, 2, 2, // 4
        31, 16, 30, 1, 1, 17, 14, // 5
        6, 8, 16, 30, 17, 17, 14, // 6
        31, 1, 2, 4, 8, 8, 8, // 7
        14, 17, 17, 14, 17, 17, 14, // 8
        14, 17, 17, 15, 1, 2, 12, // 9
        0, 4, 4, 0, 4, 4, 0, // :
        0, 0, 0, 0, 0, 12, 12, // .
        4, 4, 4, 4, 4, 0, 4, // !
        14, 17, 1, 2, 4, 0, 4, // ?
        0, 1, 2, 4, 8, 16, 0, // /
        0, 0, 0, 31, 0, 0, 0, // -
        4, 4, 8, 0, 0, 0, 0 // '
    ];

    // Draws text centred on x with its top at y. Each font pixel is
    // scale × scale screen pixels. A shadow, when given, is offset one
    // font pixel down and to the right.
    function draw(dc as Dc, text as String, x as Number, y as Number,
            scale as Number, color as Number, shadow as Number?) as Void {
        var left = x - (text.length() * 6 - 1) * scale / 2;
        if (shadow != null) {
            drawGlyphs(dc, text, left + scale, y + scale, scale, shadow);
        }
        drawGlyphs(dc, text, left, y, scale, color);
    }

    function drawGlyphs(dc as Dc, text as String, x as Number, y as Number,
            scale as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var chars = text.toUpper().toCharArray();
        for (var i = 0; i < chars.size(); i += 1) {
            var glyph = CHARS.find(chars[i].toString());
            if (glyph == null) {
                continue;
            }
            var gx = x + i * 6 * scale;
            for (var row = 0; row < 7; row += 1) {
                var bits = ROWS[glyph * 7 + row];
                for (var col = 0; col < 5; col += 1) {
                    if ((bits & (16 >> col)) != 0) {
                        dc.fillRectangle(gx + col * scale, y + row * scale, scale, scale);
                    }
                }
            }
        }
    }

}
