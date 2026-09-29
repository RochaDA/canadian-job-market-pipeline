"""
src/data/manifest.py

A manifest is a small append-only log of what's been downloaded: one JSON
line per monthly file, recording enough metadata to answer "do I already
have this month?", "where did this row count come from?", and "has this month 
already been uploaded and COPY INTO into the bronze table?" without
re-opening the data itself.

Existing entries from before the latest change have no "type" field. Every
function here treats a missing "type" as "download", so old manifests
keep working without modification.
"""

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def load_downloaded_months(manifest_path: Path) -> set:
    """Return the set of month labels with a download entry in the manifest."""
    if not manifest_path.exists():
        return set()

    months = set()
    for entry in _read_entries(manifest_path):
        if entry.get("type", "download") == "download":
            months.add(entry["month"])
    return months


def load_pending_bronze_uploads(manifest_path: Path) -> list:
    """
    Return the most recent download entry for every month that does NOT yet
    have a matching "loaded_to_bronze" entry, i.e. months downloaded but
    not yet uploaded/COPY INTO'd into the bronze table.
    """
    if not manifest_path.exists():
        return []

    latest_download_by_month = {}
    loaded_months = set()

    for entry in _read_entries(manifest_path):
        entry_type = entry.get("type", "download")
        if entry_type == "download":
            latest_download_by_month[entry["month"]] = entry
        elif entry_type == "loaded_to_bronze":
            loaded_months.add(entry["month"])

    return [
        entry
        for month, entry in latest_download_by_month.items()
        if month not in loaded_months
    ]


def append_entry(
    manifest_path: Path,
    *,
    month: str,
    url: str,
    file_path: Path,
    row_count: int,
    column_count: int,
    columns: list,
) -> None:
    """Append a download record, creating the manifest file if needed."""
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    entry = {
        "type": "download",
        "month": month,
        "url": url,
        "file_path": str(file_path),
        "row_count": row_count,
        "column_count": column_count,
        "columns": columns,
        "sha256": _file_sha256(file_path),
        "downloaded_at": datetime.now(timezone.utc).isoformat(),
    }

    _append_line(manifest_path, entry)


def append_loaded_to_bronze(manifest_path: Path, *, month: str, table: str) -> None:
    """Append a record marking a month as successfully loaded into bronze."""
    entry = {
        "type": "loaded_to_bronze",
        "month": month,
        "table": table,
        "loaded_at": datetime.now(timezone.utc).isoformat(),
    }
    _append_line(manifest_path, entry)


def _read_entries(manifest_path: Path):
    with manifest_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def _append_line(manifest_path: Path, entry: dict) -> None:
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def _file_sha256(file_path: Path) -> str:
    h = hashlib.sha256()
    with file_path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()
