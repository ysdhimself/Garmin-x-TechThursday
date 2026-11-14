# /// script
# requires-python = ">=3.10"
# dependencies = ["fit-tool==0.9.17"]
# ///
"""Run `uv run demo/motion/fixtures/generate.py` to regenerate both FIT files."""

from math import pi, sin
from pathlib import Path

from fit_tool.fit_file_builder import FitFileBuilder
from fit_tool.profile.messages.accelerometer_data_message import AccelerometerDataMessage
from fit_tool.profile.messages.event_message import EventMessage
from fit_tool.profile.messages.file_id_message import FileIdMessage
from fit_tool.profile.messages.record_message import RecordMessage
from fit_tool.profile.profile_type import Event, EventType, FileType, Manufacturer


START_MS = 1_784_030_400_000  # Fixed Unix milliseconds, not the generation time.
SECONDS = 120
RATE = 25


def generate(name, amplitude):
    builder = FitFileBuilder()
    identity = FileIdMessage()
    identity.type = FileType.ACTIVITY
    identity.manufacturer = Manufacturer.DEVELOPMENT
    identity.product = 1
    identity.serial_number = 1
    identity.time_created = START_MS
    builder.add(identity)

    for second in range(SECONDS + 1):
        timestamp = START_MS + second * 1000
        if second in (0, SECONDS):
            event = EventMessage()
            event.timestamp = timestamp
            event.event = Event.TIMER
            event.event_type = EventType.START if second == 0 else EventType.STOP_ALL
            builder.add(event)
        record = RecordMessage()
        record.timestamp = timestamp
        builder.add(record)
        if second == SECONDS:
            break
        accel = AccelerometerDataMessage()
        accel.timestamp = timestamp
        # Garmin's PitchCounter sample uses these signed millig fields (not
        # uncalibrated ADC counts). Each message contains one second at 25 Hz.
        accel.compressed_calibrated_accel_x = [
            round(amplitude * sin(2 * pi * 1.25 * (second + i / RATE)))
            for i in range(RATE)
        ]
        accel.compressed_calibrated_accel_y = [0] * RATE
        accel.compressed_calibrated_accel_z = [1000] * RATE
        builder.add(accel)

    path = Path(__file__).with_name(name + ".fit")
    builder.build().to_file(str(path))
    print(path)


if __name__ == "__main__":
    generate("petting", 300)
    generate("still", 0)
