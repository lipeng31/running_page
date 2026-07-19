import datetime
import sys
from collections import namedtuple
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))

from generator.db import Activity, init_db, update_or_create_activity
from generator import Generator


run_map = namedtuple("polyline", "summary_polyline")


def incoming_activity(
    *,
    run_id=1_720_000_000_000,
    source_id="health-workout-1",
    start_date="2026-07-14 00:01:00+00:00",
    distance=10_050,
    summary_polyline="complete-route",
):
    values = {
        "id": run_id,
        "source_id": source_id,
        "name": "Apple Workout Run",
        "distance": distance,
        "moving_time": datetime.timedelta(hours=1),
        "elapsed_time": datetime.timedelta(hours=1, minutes=1),
        "type": "Run",
        "subtype": "",
        "start_date": start_date,
        "start_date_local": "2026-07-14 08:01:00",
        "average_heartrate": 150,
        "average_speed": 2.8,
        "elevation_gain": 20,
        "map": run_map(summary_polyline),
        "start_latlng": None,
    }
    return namedtuple("activity", values)(**values)


def legacy_activity():
    return Activity(
        run_id=18_000_000_001,
        name="Morning Run",
        distance=10_000,
        moving_time=datetime.timedelta(hours=1),
        elapsed_time=datetime.timedelta(hours=1),
        type="Run",
        subtype="Run",
        start_date="2026-07-14 00:00:00",
        start_date_local="2026-07-14 08:00:00",
        location_country="Singapore",
        summary_polyline="damaged-route",
        average_heartrate=140,
        average_speed=2.7,
        elevation_gain=10,
    )


def test_healthkit_gpx_repairs_legacy_row_without_creating_duplicate(tmp_path):
    session = init_db(tmp_path / "activities.db")
    session.add(legacy_activity())
    session.commit()

    created = update_or_create_activity(
        session,
        incoming_activity(),
        match_by_start=True,
    )
    session.commit()

    activities = session.query(Activity).all()
    assert created is False
    assert len(activities) == 1
    assert activities[0].run_id == 18_000_000_001
    assert activities[0].source_id == "health-workout-1"
    assert activities[0].name == "Morning Run"
    assert activities[0].summary_polyline == "complete-route"


def test_route_less_repair_never_erases_existing_route(tmp_path):
    session = init_db(tmp_path / "activities.db")
    session.add(legacy_activity())
    session.commit()

    update_or_create_activity(
        session,
        incoming_activity(summary_polyline=""),
        match_by_start=True,
    )
    session.commit()

    assert session.query(Activity).one().summary_polyline == "damaged-route"


def test_load_removes_only_unverified_synthetic_indoor_routes(tmp_path):
    database_path = tmp_path / "activities.db"
    session = init_db(database_path)
    unverified = legacy_activity()
    unverified.subtype = "indoor"
    verified = Activity(
        run_id=18_000_000_002,
        name="Verified Indoor Route",
        distance=1_000,
        moving_time=datetime.timedelta(minutes=10),
        elapsed_time=datetime.timedelta(minutes=10),
        type="Run",
        subtype="indoor",
        start_date="2026-07-15 00:00:00",
        start_date_local="2026-07-15 08:00:00",
        location_country="Singapore",
        summary_polyline="_p~iF~ps|U_ulLnnqC_mqNvxq`@",
        source_id="health-workout-2",
        average_heartrate=120,
        average_speed=1.7,
        elevation_gain=0,
    )
    session.add_all([unverified, verified])
    session.commit()
    unverified_id = unverified.run_id
    verified_id = verified.run_id
    session.close()

    Generator(database_path).load()
    checked = init_db(database_path)

    assert checked.get(Activity, unverified_id).summary_polyline == ""
    assert (
        checked.get(Activity, verified_id).summary_polyline
        == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    )
