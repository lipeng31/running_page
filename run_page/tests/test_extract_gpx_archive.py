import sys
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[1]))

from extract_gpx_archive import extract_gpx_archive


def write_archive(path: Path, entries: list[tuple[str, bytes]]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, data in entries:
            archive.writestr(name, data)


def test_extracts_flat_gpx_files(tmp_path):
    archive_path = tmp_path / "workouts.zip"
    destination = tmp_path / "GPX_OUT"
    write_archive(
        archive_path,
        [("first.gpx", b"first"), ("second.GPX", b"second")],
    )

    extracted = extract_gpx_archive(archive_path, destination)

    assert [path.name for path in extracted] == ["first.gpx", "second.GPX"]
    assert (destination / "first.gpx").read_bytes() == b"first"
    assert (destination / "second.GPX").read_bytes() == b"second"


@pytest.mark.parametrize(
    "entry_name",
    ["../route.gpx", "/route.gpx", "folder/route.gpx", "route.txt", "bad\\route.gpx"],
)
def test_rejects_unsafe_entries(tmp_path, entry_name):
    archive_path = tmp_path / "workouts.zip"
    write_archive(archive_path, [(entry_name, b"route")])

    with pytest.raises(ValueError, match="Unsafe archive entry"):
        extract_gpx_archive(archive_path, tmp_path / "GPX_OUT")


def test_rejects_empty_archive(tmp_path):
    archive_path = tmp_path / "workouts.zip"
    write_archive(archive_path, [])

    with pytest.raises(ValueError, match="empty"):
        extract_gpx_archive(archive_path, tmp_path / "GPX_OUT")


def test_rejects_duplicate_names(tmp_path):
    archive_path = tmp_path / "workouts.zip"
    with pytest.warns(UserWarning, match="Duplicate name"):
        write_archive(
            archive_path,
            [("route.gpx", b"first"), ("route.gpx", b"second")],
        )

    with pytest.raises(ValueError, match="Unsafe archive entry"):
        extract_gpx_archive(archive_path, tmp_path / "GPX_OUT")


def test_rejects_name_already_extracted_from_another_archive(tmp_path):
    first_archive = tmp_path / "first.zip"
    second_archive = tmp_path / "second.zip"
    destination = tmp_path / "GPX_OUT"
    write_archive(first_archive, [("route.gpx", b"first")])
    write_archive(second_archive, [("route.gpx", b"second")])

    extract_gpx_archive(first_archive, destination)

    with pytest.raises(ValueError, match="Unsafe archive entry"):
        extract_gpx_archive(second_archive, destination)
    assert (destination / "route.gpx").read_bytes() == b"first"
