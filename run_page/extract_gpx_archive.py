import argparse
import shutil
import zipfile
from pathlib import Path, PurePosixPath


MAX_ARCHIVE_ENTRIES = 1_000
MAX_UNCOMPRESSED_SIZE = 1_073_741_824


def extract_gpx_archive(archive_path: Path, destination: Path) -> list[Path]:
    destination.mkdir(parents=True, exist_ok=True)
    extracted: list[Path] = []
    seen: set[str] = set()

    with zipfile.ZipFile(archive_path) as archive:
        entries = archive.infolist()
        if not entries:
            raise ValueError("The Apple Workout archive is empty")
        if len(entries) > MAX_ARCHIVE_ENTRIES:
            raise ValueError("The Apple Workout archive contains too many files")
        if sum(entry.file_size for entry in entries) > MAX_UNCOMPRESSED_SIZE:
            raise ValueError("The Apple Workout archive is too large")

        for entry in entries:
            path = PurePosixPath(entry.filename)
            if (
                entry.is_dir()
                or entry.flag_bits & 0x1
                or "\\" in entry.filename
                or path.is_absolute()
                or len(path.parts) != 1
                or path.suffix.lower() != ".gpx"
                or path.name in seen
                or (destination / path.name).exists()
            ):
                raise ValueError(f"Unsafe archive entry: {entry.filename}")

            seen.add(path.name)

        for entry in entries:
            path = PurePosixPath(entry.filename)
            output_path = destination / path.name
            with archive.open(entry) as source, output_path.open("wb") as target:
                shutil.copyfileobj(source, target)
            extracted.append(output_path)

    return extracted


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Safely extract a temporary Apple Workout GPX archive."
    )
    parser.add_argument("archive", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    extract_gpx_archive(args.archive, args.destination)


if __name__ == "__main__":
    main()
