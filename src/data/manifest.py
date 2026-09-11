"""
src/data/manifest.py

A manifest is a small append-only log of what's been downloaded: one JSON
line per monthly file, recording enough metadata to answer "do I already
have this month?" and "where did this row count come from?" without
re-opening the data itself.

Reruns skip months already recorded here instead of re-fetching everything, 
and it doubles as a lineage record (source URL, row count, a content hash, 
and when it was pulled).
"""

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def load_downloaded_months(manifest_path: Path) -> set:
    """Return the set of month labels already present in the manifest."""
    if not manifest_path.exists():
        return set()

    months = set()
    with manifest_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            months.add(entry["month"])
    return months


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
    """Append one record to the manifest, creating the file if needed."""
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    entry = {
        "month": month,
        "url": url,
        "file_path": str(file_path),
        "row_count": row_count,
        "column_count": column_count,
        "columns": columns,
        "sha256": _file_sha256(file_path),
        "downloaded_at": datetime.now(timezone.utc).isoformat(),
    }

    with manifest_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def _file_sha256(file_path: Path) -> str:
    h = hashlib.sha256()
    with file_path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()
