import datetime
import sys
from pathlib import Path

import polyline

sys.path.insert(0, str(Path(__file__).parents[1]))

import polyline_processor
from generator import Generator
from generator.db import Activity
from polyline_processor import start_end_hiding


def test_zero_distance_keeps_polyline_endpoints():
    points = [(31.84, 117.12), (31.85, 117.13), (31.86, 117.14)]

    assert start_end_hiding(points, 0) == points


def test_published_privacy_filter_does_not_mutate_database(tmp_path, monkeypatch):
    points = [
        (31.84, 117.12),
        (31.841, 117.121),
        (31.843, 117.123),
        (31.846, 117.126),
    ]
    summary_polyline = polyline.encode(points)
    generator = Generator(tmp_path / "activities.db")
    generator.session.add(
        Activity(
            run_id=1,
            name="Run",
            distance=1_000,
            moving_time=datetime.timedelta(minutes=5),
            elapsed_time=datetime.timedelta(minutes=5),
            type="Run",
            subtype="",
            start_date="2026-07-14 00:00:00",
            start_date_local="2026-07-14 08:00:00",
            location_country="",
            summary_polyline=summary_polyline,
            average_heartrate=140,
            average_speed=3.3,
            elevation_gain=10,
        )
    )
    generator.session.commit()

    monkeypatch.setattr(polyline_processor, "IGNORE_START_END_RANGE", 0.05)
    output = generator.load()
    stored = generator.session.query(Activity).filter_by(run_id=1).one()

    assert output[0]["summary_polyline"] != summary_polyline
    assert stored.summary_polyline == summary_polyline
