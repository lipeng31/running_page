import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))

from synced_data_file_logger import (
    file_digest,
    load_synced_file_hashes,
    save_synced_data_file_list,
)


def test_legacy_import_list_is_migrated_to_content_hashes(tmp_path):
    data_dir = tmp_path / "GPX_OUT"
    data_dir.mkdir()
    workout_file = data_dir / "workout.gpx"
    workout_file.write_text("first version", encoding="utf-8")
    imported_file = tmp_path / "imported.json"
    imported_file.write_text(json.dumps([workout_file.name]), encoding="utf-8")

    assert load_synced_file_hashes(imported_file) == {workout_file.name: None}

    save_synced_data_file_list(
        [workout_file.name],
        data_dir,
        synced_file=imported_file,
    )

    assert load_synced_file_hashes(imported_file) == {
        workout_file.name: file_digest(workout_file)
    }


def test_changed_file_has_a_different_digest(tmp_path):
    workout_file = tmp_path / "workout.gpx"
    workout_file.write_text("first version", encoding="utf-8")
    original_digest = file_digest(workout_file)

    workout_file.write_text("complete version", encoding="utf-8")

    assert file_digest(workout_file) != original_digest
