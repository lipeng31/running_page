import datetime
import random
import string

from geopy.geocoders import options, Nominatim
from sqlalchemy import (
    Column,
    Float,
    Integer,
    Interval,
    String,
    create_engine,
    inspect,
    text,
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

Base = declarative_base()


# random user name 8 letters
def randomword():
    letters = string.ascii_lowercase
    return "".join(random.choice(letters) for i in range(4))


options.default_user_agent = "running_page"
# reverse the location (lat, lon) -> location detail
g = Nominatim(user_agent=randomword())


ACTIVITY_KEYS = [
    "run_id",
    "name",
    "distance",
    "moving_time",
    "type",
    "subtype",
    "start_date",
    "start_date_local",
    "location_country",
    "summary_polyline",
    "average_heartrate",
    "average_speed",
    "elevation_gain",
]


class Activity(Base):
    __tablename__ = "activities"

    run_id = Column(Integer, primary_key=True)
    name = Column(String)
    distance = Column(Float)
    moving_time = Column(Interval)
    elapsed_time = Column(Interval)
    type = Column(String)
    subtype = Column(String)
    start_date = Column(String)
    start_date_local = Column(String)
    location_country = Column(String)
    summary_polyline = Column(String)
    source_id = Column(String)
    average_heartrate = Column(Float)
    average_speed = Column(Float)
    elevation_gain = Column(Float)
    streak = None

    def to_dict(self):
        out = {}
        for key in ACTIVITY_KEYS:
            attr = getattr(self, key)
            if isinstance(attr, (datetime.timedelta, datetime.datetime)):
                out[key] = str(attr)
            else:
                out[key] = attr

        if self.streak:
            out["streak"] = self.streak

        return out


def _as_utc_datetime(value):
    if isinstance(value, datetime.datetime):
        parsed = value
    else:
        parsed = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed.astimezone(datetime.timezone.utc)


def _matching_activity(session, run_activity):
    """Find a legacy activity representing the same GPX workout.

    Apple Workout GPX IDs are timestamp based, while older records use Strava
    IDs. Match conservatively by UTC start time and distance so a full
    HealthKit re-export repairs the legacy row instead of creating a duplicate.
    """
    try:
        incoming_start = _as_utc_datetime(run_activity.start_date)
        incoming_distance = float(run_activity.distance)
    except (AttributeError, TypeError, ValueError):
        return None

    best_match = None
    best_score = None
    for activity in session.query(Activity).all():
        try:
            start_difference = abs(
                (_as_utc_datetime(activity.start_date) - incoming_start).total_seconds()
            )
            distance_difference = abs(float(activity.distance) - incoming_distance)
        except (TypeError, ValueError):
            continue

        distance_tolerance = max(500, incoming_distance * 0.08)
        if start_difference > 5 * 60 or distance_difference > distance_tolerance:
            continue

        score = (start_difference, distance_difference)
        if best_score is None or score < best_score:
            best_match = activity
            best_score = score

    return best_match


def update_or_create_activity(session, run_activity, match_by_start=False):
    created = False
    try:
        source_id = getattr(run_activity, "source_id", None) or None
        activity = None
        if source_id:
            activity = session.query(Activity).filter_by(source_id=source_id).first()
        if activity is None:
            activity = (
                session.query(Activity).filter_by(run_id=int(run_activity.id)).first()
            )
        if activity is None and match_by_start:
            activity = _matching_activity(session, run_activity)

        current_elevation_gain = 0.0  # default value

        # https://github.com/stravalib/stravalib/blob/main/src/stravalib/strava_model.py#L639C1-L643C41
        if (
            hasattr(run_activity, "total_elevation_gain")
            and run_activity.total_elevation_gain is not None
        ):
            current_elevation_gain = float(run_activity.total_elevation_gain)
        elif (
            hasattr(run_activity, "elevation_gain")
            and run_activity.elevation_gain is not None
        ):
            current_elevation_gain = float(run_activity.elevation_gain)

        if not activity:
            start_point = run_activity.start_latlng
            location_country = getattr(run_activity, "location_country", "")
            # or China for #176 to fix
            if not location_country and start_point or location_country == "China":
                try:
                    location_country = str(
                        g.reverse(
                            f"{start_point.lat}, {start_point.lon}",
                            language="zh-CN",  # type: ignore
                            timeout=15,
                        )
                    )
                # limit (only for the first time)
                except Exception:
                    try:
                        location_country = str(
                            g.reverse(
                                f"{start_point.lat}, {start_point.lon}",
                                language="zh-CN",  # type: ignore
                                timeout=15,
                            )
                        )
                    except Exception:
                        pass

            activity = Activity(
                run_id=run_activity.id,
                name=run_activity.name,
                distance=run_activity.distance,
                moving_time=run_activity.moving_time,
                elapsed_time=run_activity.elapsed_time,
                type=run_activity.type,
                subtype=run_activity.subtype,
                start_date=run_activity.start_date,
                start_date_local=run_activity.start_date_local,
                location_country=location_country,
                average_heartrate=run_activity.average_heartrate,
                average_speed=float(run_activity.average_speed),
                elevation_gain=current_elevation_gain,
                summary_polyline=(
                    run_activity.map and run_activity.map.summary_polyline or ""
                ),
                source_id=source_id,
            )
            session.add(activity)
            created = True
        else:
            # Keep the more descriptive historical title when a HealthKit
            # repair is matched to an older provider record.
            if not activity.name or activity.name == "Apple Workout Run":
                activity.name = run_activity.name
            activity.distance = float(run_activity.distance)
            activity.moving_time = run_activity.moving_time
            activity.elapsed_time = run_activity.elapsed_time
            activity.type = run_activity.type
            if run_activity.subtype:
                activity.subtype = run_activity.subtype
            activity.start_date = run_activity.start_date
            activity.start_date_local = run_activity.start_date_local
            activity.average_heartrate = run_activity.average_heartrate
            activity.average_speed = float(run_activity.average_speed)
            activity.elevation_gain = current_elevation_gain
            incoming_polyline = (
                run_activity.map and run_activity.map.summary_polyline or ""
            )
            if incoming_polyline:
                activity.summary_polyline = incoming_polyline
                if (activity.subtype or "").lower() == "indoor":
                    activity.subtype = run_activity.subtype or "Run"
            if source_id:
                activity.source_id = source_id
    except Exception as e:
        print(f"something wrong with {run_activity.id}")
        print(str(e))

    return created


def add_missing_columns(engine, model):
    inspector = inspect(engine)
    table_name = model.__tablename__
    columns = {col["name"] for col in inspector.get_columns(table_name)}
    missing_columns = []

    for column in model.__table__.columns:
        if column.name not in columns:
            missing_columns.append(column)
    if missing_columns:
        with engine.connect() as conn:
            for column in missing_columns:
                column_type = str(column.type)
                conn.execute(
                    text(
                        f"ALTER TABLE {table_name} ADD COLUMN {column.name} {column_type}"
                    )
                )


def init_db(db_path):
    engine = create_engine(
        f"sqlite:///{db_path}", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(engine)

    # check missing columns
    add_missing_columns(engine, Activity)

    sm = sessionmaker(bind=engine)
    session = sm()
    # apply the changes
    session.commit()
    return session
