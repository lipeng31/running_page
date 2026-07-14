import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))

from gpxtrackposter.track import Track


def test_running_page_imports_extended_gpx_summary_and_heart_rate(tmp_path):
    gpx_file = tmp_path / "extended.gpx"
    gpx_file.write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RunningPageSync"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
     xmlns:rps="https://github.com/lipeng31/running_page/xmlschemas/WorkoutExtension/v1">
  <metadata><time>2026-07-14T00:00:00Z</time></metadata>
  <extensions>
    <rps:distance>10000</rps:distance>
    <rps:moving_time>3600</rps:moving_time>
    <rps:elapsed_time>3700</rps:elapsed_time>
    <rps:average_speed>2.777778</rps:average_speed>
    <rps:average_hr>149.5</rps:average_hr>
    <rps:metrics>
      <rps:metric identifier="HKQuantityTypeIdentifierRunningPower" name="running_power" unit="W">
        <rps:summary average="264.5" />
        <rps:sample start="2026-07-14T00:00:00Z" end="2026-07-14T00:00:05Z" value="276.25" />
      </rps:metric>
    </rps:metrics>
  </extensions>
  <trk>
    <name>Apple Workout Run</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="1.3000000" lon="103.8000000">
        <ele>10</ele><time>2026-07-14T00:00:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>148</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
      <trkpt lat="1.3010000" lon="103.8010000">
        <ele>12</ele><time>2026-07-14T00:00:10Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>152</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
""",
        encoding="utf-8",
    )

    track = Track()
    track.load_gpx(gpx_file)

    assert track.average_heartrate == 149.5
    assert track.length == 10_000
    assert track.moving_dict["moving_time"] == datetime.timedelta(seconds=3_600)
    assert track.moving_dict["elapsed_time"] == datetime.timedelta(seconds=3_700)
    assert track.moving_dict["average_speed"] == 2.777778
