import Toybox.Test;

(:test)
function mockWalkStartsImmediately(logger) {
    WalkData.start(true);
    WalkData.tick();
    Test.assert(WalkData.hasData());
    Test.assert(WalkData.speed() == 1.4);
    Test.assert(WalkData.heartRate() >= 70);
    Test.assert(!WalkData.arrived());
    WalkData.finish();
    Test.assert(WalkData.summary()["rest"] == 68);
    Test.assert(WalkData.summary()["cadence"] == 106);
    return true;
}
