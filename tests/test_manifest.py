"""
tests/test_manifest.py

Unit tests for manifest.py's bronze-load tracking, using a temporary
manifest file so nothing touches the real data/raw/manifest.jsonl.
"""

import json
from pathlib import Path

from src.data.manifest import (
    append_entry,
    append_loaded_to_bronze,
    load_downloaded_months,
    load_pending_bronze_uploads,
)


def _write_dummy_download(manifest_path: Path, tmp_path: Path, month: str) -> Path:
    file_path = tmp_path / f"job_postings_{month}.csv"
    file_path.write_text("a,b\n1,2\n")
    append_entry(
        manifest_path,
        month=month,
        url=f"https://example.com/{month}.csv",
        file_path=file_path,
        row_count=1,
        column_count=2,
        columns=["a", "b"],
    )
    return file_path


def test_pending_uploads_includes_new_downloads(tmp_path):
    manifest_path = tmp_path / "manifest.jsonl"
    _write_dummy_download(manifest_path, tmp_path, "2026-08")

    pending = load_pending_bronze_uploads(manifest_path)

    assert len(pending) == 1
    assert pending[0]["month"] == "2026-08"


def test_pending_uploads_excludes_already_loaded_months(tmp_path):
    manifest_path = tmp_path / "manifest.jsonl"
    _write_dummy_download(manifest_path, tmp_path, "2026-08")
    append_loaded_to_bronze(manifest_path, month="2026-08", table="workspace.bronze.job_postings")

    pending = load_pending_bronze_uploads(manifest_path)

    assert pending == []


def test_pending_uploads_only_returns_unloaded_months(tmp_path):
    manifest_path = tmp_path / "manifest.jsonl"
    _write_dummy_download(manifest_path, tmp_path, "2026-08")
    _write_dummy_download(manifest_path, tmp_path, "2026-09")
    append_loaded_to_bronze(manifest_path, month="2026-08", table="workspace.bronze.job_postings")

    pending = load_pending_bronze_uploads(manifest_path)

    assert len(pending) == 1
    assert pending[0]["month"] == "2026-09"


def test_load_downloaded_months_ignores_loaded_to_bronze_entries(tmp_path):
    manifest_path = tmp_path / "manifest.jsonl"
    _write_dummy_download(manifest_path, tmp_path, "2026-08")
    append_loaded_to_bronze(manifest_path, month="2026-08", table="workspace.bronze.job_postings")

    # A loaded_to_bronze entry should not itself count as a "download" --
    # download.py's idempotency logic must still only see the real download.
    assert load_downloaded_months(manifest_path) == {"2026-08"}


def test_backward_compatible_with_entries_missing_type_field(tmp_path):
    # Simulates a manifest written by an earlier version of the code that
    # never had a "type" field on download entries.
    manifest_path = tmp_path / "manifest.jsonl"
    legacy_entry = {
        "month": "2026-07",
        "url": "https://example.com/2026-07.csv",
        "file_path": str(tmp_path / "job_postings_2026-07.csv"),
        "row_count": 1,
        "column_count": 2,
        "columns": ["a", "b"],
        "sha256": "deadbeef",
        "downloaded_at": "2026-08-01T00:00:00+00:00",
    }
    with manifest_path.open("w", encoding="utf-8") as f:
        f.write(json.dumps(legacy_entry) + "\n")

    assert load_downloaded_months(manifest_path) == {"2026-07"}
    pending = load_pending_bronze_uploads(manifest_path)
    assert len(pending) == 1
    assert pending[0]["month"] == "2026-07"
