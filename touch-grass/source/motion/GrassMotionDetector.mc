// Bounded, batch-based gesture heuristic. No raw samples are retained.
class GrassMotionDetector {
    const REQUIRED_MS = 5000;
    // ponytail: demo thresholds, tune with watch recordings before claiming accuracy.
    const MIN_SWING_MG = 180;
    const MAX_SWING_MG = 1800;
    const REVERSAL_MG = 90;

    var _acceptedMs = 0;
    var _lastEndMs = 0;
    var _invalid = false;

    function initialize() {
    }

    // elapsedMs is monotonic time since Start, at receipt of this batch.
    // Supply fresh, consecutive ~one-second batches, in millig, only after Start.
    function addBatch(x, y, z, sampleRate, elapsedMs) {
        if (_invalid || _acceptedMs >= REQUIRED_MS) { return; }
        if (sampleRate < 10 || x.size() != y.size() || x.size() != z.size()) {
            _invalid = true;
            return;
        }
        var duration = x.size() * 1000.0 / sampleRate;
        // Reject gaps, duplicates, pre-start and accelerated/replayed delivery.
        if (duration < 800 || duration > 1200 || elapsedMs > 6000 ||
            (elapsedMs - _lastEndMs - duration).abs() > 250 ||
            _acceptedMs + duration > elapsedMs + 100) {
            _invalid = true;
            return;
        }
        _lastEndMs = elapsedMs;

        // Use the largest excursion, not magnitude: gravity at any fixed wrist
        // orientation is constant, whereas petting reverses along an axis.
        var axes = [x, y, z];
        var best = x;
        var largest = 0;
        for (var a = 0; a < 3; a += 1) {
            var samples = axes[a];
            var low = samples[0];
            var high = low;
            for (var i = 1; i < samples.size(); i += 1) {
                if (samples[i] < low) { low = samples[i]; }
                if (samples[i] > high) { high = samples[i]; }
            }
            if (high - low > largest) {
                largest = high - low;
                best = samples;
            }
        }
        var direction = 0;
        var extreme = best[0];
        var turns = 0;
        for (var j = 1; j < best.size(); j += 1) {
            var delta = best[j] - extreme;
            if (direction >= 0 && delta <= -REVERSAL_MG) {
                if (direction != 0) { turns += 1; }
                direction = -1;
                extreme = best[j];
            } else if (direction <= 0 && delta >= REVERSAL_MG) {
                if (direction != 0) { turns += 1; }
                direction = 1;
                extreme = best[j];
            } else if ((direction > 0 && delta > 0) || (direction < 0 && delta < 0)) {
                extreme = best[j];
            }
        }
        if (largest < MIN_SWING_MG || largest > MAX_SWING_MG || turns < 1 || turns > 5) {
            _invalid = true;
            return;
        }
        _acceptedMs += duration;
        if (_acceptedMs > REQUIRED_MS) { _acceptedMs = REQUIRED_MS; }
    }

    function getProgress() {
        return _acceptedMs / 1000.0;
    }

    function passed(elapsedMs) {
        return !_invalid && elapsedMs >= REQUIRED_MS && _acceptedMs >= REQUIRED_MS;
    }
}
