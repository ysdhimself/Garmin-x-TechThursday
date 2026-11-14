import Toybox.Test;

(:test)
function pettingGestureContract(logger) {
    // Sustained movement must work on all axes, including along gravity.
    for (var axis = 0; axis < 3; axis += 1) {
        var wave = new GrassMotionDetector();
        for (var s = 0; s < 5; s += 1) {
            var batch = motionBatch(0, s, axis);
            wave.addBatch(batch[0], batch[1], batch[2], 25, (s + 1) * 1000);
            Test.assert(wave.passed((s + 1) * 1000) == (s == 4));
        }
        Test.assert(wave.getProgress() == 5.0);
    }
    // Stillness, one short burst, and a missing second cannot earn a stamp.
    for (var scenario = 1; scenario <= 3; scenario += 1) {
        var detector = new GrassMotionDetector();
        for (var second = 0; second < 5; second += 1) {
            if (scenario == 3 && second == 2) { continue; }
            var input = motionBatch(scenario, second, 1);
            detector.addBatch(input[0], input[1], input[2], 25, (second + 1) * 1000);
        }
        Test.assert(!detector.passed(6000));
    }
    var absent = new GrassMotionDetector();
    Test.assert(!absent.passed(6000));
    // Five seconds of samples delivered instantly is not five real seconds.
    var fast = new GrassMotionDetector();
    var fresh = motionBatch(0, 0, 0);
    for (var n = 0; n < 5; n += 1) {
        fast.addBatch(fresh[0], fresh[1], fresh[2], 25, 1000);
    }
    Test.assert(!fast.passed(6000));
    // A changing value alone is not petting: reject noise, a one-way tilt,
    // violent movement, and high-frequency shaking.
    for (var kind = 0; kind < 4; kind += 1) {
        var rejected = new GrassMotionDetector();
        for (var sec = 0; sec < 5; sec += 1) {
            var bad = motionBatch(0, sec, 0);
            for (var i = 0; i < 25; i += 1) {
                if (kind == 0) { bad[0][i] = (i % 2) * 20; }
                if (kind == 1) { bad[0][i] = i * 20; }
                if (kind == 2) { bad[0][i] *= 10; }
                if (kind == 3) { bad[0][i] = (i % 2) * 500; }
            }
            rejected.addBatch(bad[0], bad[1], bad[2], 25, (sec + 1) * 1000);
        }
        Test.assert(!rejected.passed(6000));
    }
    return true;
}
