import Toybox.Graphics;
import Toybox.Lang;

// Pixel-art flow screens: a meadow on a 60 × 60 grid of chunky cells.
// Colours stay inside the fēnix 7's 64-colour palette (each channel
// 00, 55, AA, or FF) so the display shows them without dithering.
module PixelScene {

    const GRID = 60;
    const SKY = 0x55AAFF;
    const HAZE = 0xAAFFFF;
    const SUN = 0xFFFF55;
    const SUN_EDGE = 0xFFAA00;
    const CLOUD = 0xFFFFFF;
    const HILL = 0x55AA55;
    const GRASS = 0x00AA00;
    const BLADE = 0x55FF55;
    const SOIL = 0x005500;
    const NAVY = 0x0055AA;
    const RED = 0xFF5555;
    const SKIN = 0xFFAA55;

    var _dc as Dc?;
    var _cell as Number = 4;
    var _left as Number = 0;
    var _top as Number = 0;

    // Passive landing screen: a sunny meadow.
    function drawPassive(dc as Dc) as Void {
        meadow(dc);
        sun();
        title(dc, "TOUCH", CLOUD, NAVY, "GRASS", BLADE, SOIL);
        footer(dc, "NO GRASS NEEDED", "START: DEMO");
        _dc = null;
    }

    // Touch grass challenge. progress is null before START, then 0.0 to
    // 1.0; the hand waves and a segmented bar fills while it runs.
    function drawTouchGrass(dc as Dc, progress as Float?) as Void {
        meadow(dc);
        if (progress != null && progress >= 1.0) {
            sun();
            title(dc, "GRASS", BLADE, SOIL, "TOUCHED", CLOUD, NAVY);
            footer(dc, "HUMANITY RENEWED", "START: NEXT");
            _dc = null;
            return;
        }

        title(dc, "PET THE", CLOUD, NAVY, "GRASS", BLADE, SOIL);
        if (progress == null) {
            hand(0);
            footer(dc, "WAVE YOUR HAND", "START: BEGIN");
            _dc = null;
            return;
        }

        // Wave: shift the hand a cell left or right each tenth of the challenge.
        hand((progress * 10).toNumber() % 2 == 0 ? -1 : 1);
        var x = dc.getWidth() / 2;
        PixelFont.draw(dc, "TOUCHING...", x, _top + 42 * _cell, _cell / 2, CLOUD, SOIL);
        var segments = 8;
        var filled = (progress * segments).toNumber();
        cell(13, 48, 35, 5, SOIL);
        for (var i = 0; i < segments; i += 1) {
            cell(15 + i * 4, 49, 3, 3, i < filled ? BLADE : GRASS);
        }
        _dc = null;
    }

    // Invitation screen: the same meadow, with an alarm clock for a sun.
    function drawGrassTime(dc as Dc) as Void {
        meadow(dc);
        // Bells and legs.
        cell(35, 3, 2, 1, RED);
        cell(42, 3, 2, 1, RED);
        cell(36, 13, 1, 1, NAVY);
        cell(42, 13, 1, 1, NAVY);
        // Body.
        cell(37, 4, 5, 1, RED);
        cell(36, 5, 7, 1, RED);
        cell(35, 6, 9, 5, RED);
        cell(36, 11, 7, 1, RED);
        cell(37, 12, 5, 1, RED);
        // Face and hands.
        cell(37, 5, 5, 1, CLOUD);
        cell(36, 6, 7, 5, CLOUD);
        cell(37, 11, 5, 1, CLOUD);
        cell(39, 6, 1, 3, NAVY);
        cell(39, 8, 3, 1, NAVY);
        title(dc, "GRASS", BLADE, SOIL, "TIME!", SUN, SUN_EDGE);
        footer(dc, "PERMIT EXPIRING", "START: GO");
        _dc = null;
    }

    // The sun, top right of the sky.
    function sun() as Void {
        cell(40, 4, 5, 1, SUN_EDGE);
        cell(39, 5, 7, 1, SUN);
        cell(38, 6, 9, 5, SUN);
        cell(39, 11, 7, 1, SUN);
        cell(40, 12, 5, 1, SUN_EDGE);
        cell(38, 9, 1, 2, SUN_EDGE);
        cell(46, 9, 1, 2, SUN_EDGE);
    }

    // A raised open hand in the sky, shifted dx cells sideways, with
    // motion lines on each side.
    function hand(dx as Number) as Void {
        var x = 36 + dx;
        cell(x + 1, 3, 1, 3, SKIN);
        cell(x + 3, 3, 1, 3, SKIN);
        cell(x + 5, 3, 1, 3, SKIN);
        cell(x + 7, 4, 1, 2, SKIN);
        cell(x + 1, 6, 7, 1, SKIN);
        cell(x, 7, 8, 1, SKIN);
        cell(x + 1, 8, 7, 2, SKIN);
        cell(x + 2, 10, 5, 1, SKIN);
        cell(x + 2, 11, 5, 2, NAVY);
        cell(x - 2, 5, 1, 2, CLOUD);
        cell(x + 9, 6, 1, 2, CLOUD);
    }

    // Sky, clouds, hills, and the grassy meadow shared by every screen.
    function meadow(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        _dc = dc;
        _cell = (w < h ? w : h) / GRID;
        _left = (w - GRID * _cell) / 2;
        _top = (h - GRID * _cell) / 2;
        // Cells beyond the grid that still fall on screen (larger displays).
        var margin = _left / _cell + 1;

        // Sky, fading into haze through a dithered band.
        dc.setColor(SKY, SKY);
        dc.clear();
        dc.setColor(HAZE, HAZE);
        dc.fillRectangle(0, _top + 30 * _cell, w, h);
        for (var gx = -margin; gx < GRID + margin; gx += 2) {
            cell(gx, 28, 1, 1, HAZE);
            cell(gx + 1, 29, 1, 1, HAZE);
            cell(gx + 1, 30, 1, 1, SKY);
        }

        cloud(12, 8, 13);
        cloud(46, 19, 9);

        // Rolling hills, then the meadow.
        cell(5, 32, 13, 1, HILL);
        cell(2, 33, 19, 1, HILL);
        cell(38, 31, 11, 1, HILL);
        cell(35, 32, 17, 1, HILL);
        cell(32, 33, 23, 1, HILL);
        cell(-margin, 34, GRID + 2 * margin, 4, HILL);
        dc.setColor(GRASS, GRASS);
        dc.fillRectangle(0, _top + 38 * _cell, w, h);

        // Grass blades along the meadow's edge, in a repeating pattern.
        var blades = [1, 2, 0, 1, 3, 1, 0, 2, 1, 0];
        for (var gx = -margin; gx < GRID + margin; gx += 1) {
            var height = blades[(gx + GRID) % blades.size()] as Number;
            cell(gx, 38 - height, 1, height + 1, BLADE);
        }
        flower(9, 36);
        flower(50, 35);

        // Speckled soil below the text.
        for (var gy = 54; gy < GRID; gy += 1) {
            for (var gx = 0; gx < GRID; gx += 1) {
                if ((gx * 7 + gy * 13) % 11 == 0) {
                    cell(gx, gy, 1, 1, SOIL);
                }
            }
        }
    }

    // Two lines of large text in the sky.
    function title(dc as Dc, first as String, firstColor as Number, firstShadow as Number,
            second as String, secondColor as Number, secondShadow as Number) as Void {
        var x = dc.getWidth() / 2;
        PixelFont.draw(dc, first, x, _top + 14 * _cell, _cell, firstColor, firstShadow);
        PixelFont.draw(dc, second, x, _top + 23 * _cell, _cell, secondColor, secondShadow);
    }

    // A status line and a button hint on the meadow.
    function footer(dc as Dc, status as String, hint as String) as Void {
        var x = dc.getWidth() / 2;
        var small = _cell / 2;
        PixelFont.draw(dc, status, x, _top + 42 * _cell, small, CLOUD, SOIL);
        PixelFont.draw(dc, hint, x, _top + 49 * _cell, small, SUN, SOIL);
    }

    // Fills a block of grid cells.
    function cell(gx as Number, gy as Number, w as Number, h as Number, color as Number) as Void {
        var dc = _dc as Dc;
        dc.setColor(color, color);
        dc.fillRectangle(_left + gx * _cell, _top + gy * _cell, w * _cell, h * _cell);
    }

    // A flat-bottomed cloud with its top-left at (gx, gy).
    function cloud(gx as Number, gy as Number, w as Number) as Void {
        cell(gx + 3, gy, w - 7, 1, CLOUD);
        cell(gx + 1, gy + 1, w - 2, 1, CLOUD);
        cell(gx, gy + 2, w, 1, CLOUD);
        cell(gx + 1, gy + 3, w - 2, 1, HAZE);
    }

    // A four-petal flower centred on (gx, gy).
    function flower(gx as Number, gy as Number) as Void {
        cell(gx - 1, gy, 3, 1, RED);
        cell(gx, gy - 1, 1, 3, RED);
        cell(gx, gy, 1, 1, SUN);
    }

}
