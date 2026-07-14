import hashlib
import json
import os

from config import SYNCED_FILE

SYNCED_FILE_VERSION = 2


def file_digest(file_path):
    digest = hashlib.sha256()
    with open(file_path, "rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def save_synced_data_file_list(file_list, data_dir, synced_file=SYNCED_FILE):
    synced_hashes = load_synced_file_hashes(synced_file)
    for file_name in file_list:
        file_path = os.path.join(data_dir, file_name)
        if os.path.isfile(file_path):
            synced_hashes[file_name] = file_digest(file_path)

    with open(synced_file, "w", encoding="utf-8") as file:
        json.dump(
            {"version": SYNCED_FILE_VERSION, "files": synced_hashes},
            file,
            sort_keys=True,
        )


def load_synced_file_hashes(synced_file=SYNCED_FILE):
    if not os.path.exists(synced_file):
        return {}

    with open(synced_file, "r", encoding="utf-8") as file:
        try:
            saved = json.load(file)
        except (OSError, ValueError) as error:
            print(f"json load {synced_file} \nerror {error}")
            return {}

    if isinstance(saved, dict):
        if saved.get("version") == SYNCED_FILE_VERSION and isinstance(
            saved.get("files"), dict
        ):
            return saved["files"]

        legacy_files = saved.get("files") if "files" in saved else saved
        if isinstance(legacy_files, dict):
            # An unversioned hash map is stale after importer behavior changes.
            return {file_name: None for file_name in legacy_files}
        return {}
    if isinstance(saved, list):
        # A legacy filename-only entry is intentionally treated as stale once.
        return {file_name: None for file_name in saved}
    return {}


def load_synced_file_list(synced_file=SYNCED_FILE):
    return list(load_synced_file_hashes(synced_file))
