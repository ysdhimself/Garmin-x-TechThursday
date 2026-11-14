import Toybox.Math;

// Synthetic millig input shared by the visible demo and Monkey C tests.
function motionBatch(scenario, second, axis) {
    var axes = [[], [], []];
    for (var i = 0; i < 25; i += 1) {
        var t = second + i / 25.0;
        var value = (300 * Math.sin(2 * Math.PI * 1.25 * t)).toNumber();
        if (scenario == 1 || (scenario == 2 && second > 0)) { value = 0; }
        axes[0].add(0);
        axes[1].add(0);
        axes[2].add(1000);
        axes[axis][i] += value;
    }
    return axes;
}
