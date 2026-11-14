# /// script
# requires-python = ">=3.10"
# dependencies = ["fit-tool==0.9.17"]
# ///
"""Run `uv run demo/walk/fixtures/generate.py` to regenerate the walk activity FIT files.

Each file is a synthetic Touch Grass session for the Connect IQ simulator's Activity Data playback:
sit still at the origin -> walk the route in route-edmonton.json at 1.4 m/s -> stand at the green space.
One Record per second (position, speed, distance, heart rate, cadence, altitude) plus 25 Hz
AccelerometerData in the same signed millig fields as demo/motion. Deterministic: fixed start time,
no randomness, so regenerating gives identical bytes. Synthetic data, not a wrist recording.
"""

import json
from math import atan2, cos, hypot, pi, radians, sin
from pathlib import Path

from fit_tool.fit_file_builder import FitFileBuilder
from fit_tool.profile.messages.accelerometer_data_message import AccelerometerDataMessage
from fit_tool.profile.messages.event_message import EventMessage
from fit_tool.profile.messages.file_id_message import FileIdMessage
from fit_tool.profile.messages.record_message import RecordMessage
from fit_tool.profile.profile_type import Event, EventType, FileType, Manufacturer

HERE = Path(__file__).parent
START_MS = 1_794_927_600_000  # 2026-11-17T15:00:00Z, fixed (not the generation time)
WALK_MPS = 1.4
RATE = 25  # accelerometer samples per second, as in demo/motion
ALTITUDE_M = 668.0  # downtown Edmonton, approximate
EARTH_R = 6371008.8

PLAN = json.loads((HERE / "route-edmonton.json").read_text())
ORIGIN = PLAN["origin"]  # [latE6, lonE6]
LAT0 = ORIGIN[0] / 1e6
LON0 = ORIGIN[1] / 1e6
M_PER_DEG_LAT = EARTH_R * pi / 180
M_PER_DEG_LON = M_PER_DEG_LAT * cos(radians(LAT0))


def to_xy(p):
    """[latE6, lonE6] -> local metres (east, north) from the origin."""
    return ((p[1] / 1e6 - LON0) * M_PER_DEG_LON, (p[0] / 1e6 - LAT0) * M_PER_DEG_LAT)


def to_latlon(x, y):
    return (LAT0 + y / M_PER_DEG_LAT, LON0 + x / M_PER_DEG_LON)


ROUTE = [to_xy(p) for p in PLAN["route"]["points"]]
ENTRY = to_xy(PLAN["destination"]["point"])


def length(path):
    return sum(hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(path, path[1:]))


def point_at(path, d):
    """Point at distance d (metres) along the polyline."""
    for a, b in zip(path, path[1:]):
        seg = hypot(b[0] - a[0], b[1] - a[1])
        if d <= seg and seg > 0:
            f = d / seg
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        d -= seg
    return path[-1]


def walk(path, stop_at=None):
    """One position per second at WALK_MPS along `path`, ending exactly at the end (or at stop_at metres)."""
    total = length(path) if stop_at is None else stop_at
    steps = max(1, round(total / WALK_MPS))
    return [point_at(path, total * i / steps) for i in range(1, steps + 1)]


def dist_to_path(p, path):
    best = float("inf")
    for a, b in zip(path, path[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = dx * dx + dy * dy
        t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L)) if L else 0.0
        best = min(best, hypot(a[0] + t * dx - p[0], a[1] + t * dy - p[1]))
    return best


def stop_point(path, away_m):
    """Furthest distance along `path` whose straight-line distance to the path's end is still >= away_m."""
    d, total = 0.0, length(path)
    while d + 0.5 <= total and hypot(*(c - e for c, e in zip(point_at(path, d + 0.5), path[-1]))) >= away_m:
        d += 0.5
    return d


def detour(path, off_m):
    """Path with an out-and-back side trip from the route's midpoint to a spot off_m metres from the route."""
    half = length(path) / 2
    mid = point_at(path, half)
    ahead = point_at(path, half + 1)
    hx, hy = ahead[0] - mid[0], ahead[1] - mid[1]
    n = hypot(hx, hy) or 1
    # Try both sides of the travel direction; push out until the spot is off_m from the whole route.
    sides = []
    for sign in (1, -1):
        k = off_m
        spot = (mid[0] - sign * hy / n * k, mid[1] + sign * hx / n * k)
        while dist_to_path(spot, path) < off_m and k < 4 * off_m:
            k += 1
            spot = (mid[0] - sign * hy / n * k, mid[1] + sign * hx / n * k)
        sides.append((k, spot))
    side = min(sides)[1]  # the side that needs the shorter trip
    before, d = [path[0]], 0.0
    for a, b in zip(path, path[1:]):
        seg = hypot(b[0] - a[0], b[1] - a[1])
        if d + seg >= half:
            return before + [mid, side, mid] + [b] + path[path.index(b) + 1 :]
        before.append(b)
        d += seg
    return path


def session(sit_s, moves, stand_s, pet_window=None, start=(0.0, 0.0)):
    """Second-by-second samples: (x, y, speed, phase, pet_second_or_None). Sits at `start`."""
    out = [(start[0], start[1], 0.0, "sit", None) for _ in range(sit_s)]
    prev = start
    for p in moves:
        out.append((p[0], p[1], hypot(p[0] - prev[0], p[1] - prev[1]), "walk", None))
        prev = p
    for s in range(stand_s):
        # Standing still, with sub-metre GPS wobble so the position stream keeps updating.
        x = prev[0] + 0.6 * sin(s * 0.7)
        y = prev[1] + 0.6 * cos(s * 0.9)
        pet = s - pet_window[0] if pet_window and pet_window[0] <= s < pet_window[1] else None
        out.append((x, y, 0.0, "stand", pet))
    return out


CAL_PER_S = {"sit": 1.3 / 60, "walk": 4.0 / 60, "stand": 1.6 / 60}  # kcal/s, rough adult values
STRIDES_PER_MIN = 53  # walking cadence in FIT units (strides/min); ~106 steps/min
SEA_LEVEL_PA = 101325.0


def altitude_m(distance):
    """Gentle +-1.5 m undulation along the walk, around downtown Edmonton's ~668 m."""
    return ALTITUDE_M + 1.5 * sin(distance / 30.0)


def pressure_pa(alt):
    """Barometric formula (standard atmosphere), so pressure and altitude agree (~93.4 kPa at 668 m)."""
    return SEA_LEVEL_PA * (1 - 2.25577e-5 * alt) ** 5.25588


def temperature_c(phase, seconds_since_outside):
    """Watch temperature: ~22 C indoors while sitting, cooling toward ~6 C once outside (November)."""
    if phase == "sit":
        return 22.0
    return 6.0 + 16.0 * 0.985 ** seconds_since_outside


def heart_rate(i, phase, phase_start):
    t = i - phase_start
    if phase == "sit":
        return 68 + round(2 * sin(i / 9))
    if phase == "walk":
        return min(95, 70 + t) + round(2 * sin(i / 5))
    return max(85, 95 - t // 2) + round(1.5 * sin(i / 7))


def build(name, samples):
    builder = FitFileBuilder()
    identity = FileIdMessage()
    identity.type = FileType.ACTIVITY
    identity.manufacturer = Manufacturer.DEVELOPMENT
    identity.product = 2
    identity.serial_number = 2
    identity.time_created = START_MS
    builder.add(identity)

    distance = 0.0
    calories = 0.0
    strides = 0.0
    outside_since = None
    phase_start, last_phase = 0, None
    n = len(samples)
    for i in range(n + 1):
        ts = START_MS + i * 1000
        if i in (0, n):
            event = EventMessage()
            event.timestamp = ts
            event.event = Event.TIMER
            event.event_type = EventType.START if i == 0 else EventType.STOP_ALL
            builder.add(event)
        if i == n:
            break
        x, y, speed, phase, pet = samples[i]
        if phase != last_phase:
            phase_start, last_phase = i, phase
        distance += speed
        calories += CAL_PER_S[phase]
        if phase == "walk":
            strides += STRIDES_PER_MIN / 60
        if phase != "sit" and outside_since is None:
            outside_since = i
        lat, lon = to_latlon(x, y)
        alt = altitude_m(distance)

        record = RecordMessage()
        record.timestamp = ts
        record.position_lat = lat
        record.position_long = lon
        record.distance = round(distance, 2)
        record.speed = round(speed, 3)
        record.altitude = round(alt, 1)
        record.heart_rate = heart_rate(i, phase, phase_start)
        record.cadence = STRIDES_PER_MIN if phase == "walk" else 0  # strides/min (about 106 steps/min)
        record.total_cycles = int(strides)  # cumulative strides; steps = 2 x strides
        record.calories = int(calories)  # cumulative kcal
        record.temperature = round(temperature_c(phase, 0 if outside_since is None else i - outside_since))
        record.absolute_pressure = round(pressure_pa(alt))
        builder.add(record)

        accel = AccelerometerDataMessage()
        accel.timestamp = ts
        # Same signal as demo/motion "petting": 1.25 Hz, +-300 millig on X, gravity on Z.
        amp = 300 if pet is not None else 0
        t0 = pet or 0
        accel.compressed_calibrated_accel_x = [round(amp * sin(2 * pi * 1.25 * (t0 + k / RATE))) for k in range(RATE)]
        accel.compressed_calibrated_accel_y = [0] * RATE
        accel.compressed_calibrated_accel_z = [1000] * RATE
        builder.add(accel)

    path = HERE / f"{name}.fit"
    builder.build().to_file(str(path))
    print(path, f"({n} s)")


def write_short_plan(walk_s):
    """route-edmonton-short.json: the same real route, starting walk_s x 1.4 m before the entry.
    Same entry point, green space and attribution; only the origin moves along the route."""
    keep = walk_s * WALK_MPS
    start_d = max(0.0, length(ROUTE) - keep)
    start = point_at(ROUTE, start_d)
    rest, d = [], 0.0
    for a, b in zip(ROUTE, ROUTE[1:]):
        d += hypot(b[0] - a[0], b[1] - a[1])
        if d > start_d + 0.5:
            rest.append(b)
    pts = [start] + rest
    to_e6 = lambda p: [round(v * 1e6) for v in to_latlon(*p)]
    plan = dict(PLAN)
    plan["origin"] = to_e6(start)
    plan["route"] = {
        "points": [to_e6(p) for p in pts[:-1]] + [PLAN["route"]["points"][-1]],  # end exactly on the entry
        "distanceM": round(length(pts)),
        "durationS": round(length(pts) / WALK_MPS),
    }
    path = HERE / "route-edmonton-short.json"
    path.write_text(json.dumps(plan, indent=2) + "\n")
    print(path)
    return pts  # same local frame as ROUTE (metres from the full plan's origin)


if __name__ == "__main__":
    # Quick demo: sit 5 s -> ~30 s walk -> stand 15 s (petting in standing seconds 3-12). Uses
    # route-edmonton-short.json, whose origin is ~42 m before the entry on the same real route.
    short = write_short_plan(30)
    build("quick-walk", session(5, walk(short), 15, pet_window=(3, 13), start=short[0]))

    build("touch-grass-full", session(60, walk(ROUTE), 30, pet_window=(10, 20)))
    build("arrive-no-wave", session(60, walk(ROUTE), 30))
    build("walk-stops-short", session(20, walk(ROUTE, stop_at=max(1.0, stop_point(ROUTE, 40))), 60))
    build("walk-off-route", session(20, walk(detour(ROUTE, 60)), 30))
