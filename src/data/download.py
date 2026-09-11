"""
src/data/download.py

Fetches Canadian Job Bank's monthly open-data CSV files one month at a time and
writes each as its own file under data/raw/, alongside a manifest entry.

Design notes:

- Idempotent: months already recorded in the manifest are skipped on rerun,
  so a failed run partway through can simply be re-run instead of restarted.
- Schema drift is logged loudly: government open-data exports change column names/sets across time without warning, and a plain
  concat would hide that.
- Network calls retry with exponential backoff, since a single transient
  failure shouldn't fail the whole run.
- Parsing is separated from fetching so the
  encoding-fallback logic can be unit tested without any network calls
  (see tests/test_download.py).
"""

import io
import logging
import re
import time
from pathlib import Path

import pandas as pd
import requests

from src.data import config
from src.data.manifest import append_entry, load_downloaded_months

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(message)s",
)
logger = logging.getLogger(__name__)

CKAN_PACKAGE_URL = (
    "https://open.canada.ca/data/api/action/package_show"
    "?id=ea639e28-c0fc-48bf-b5dd-b8899bd43072"
)

# Minimum columns any successfully-parsed file must have. Used both to
# validate a parse attempt and to sanity-check for schema drift.
EXPECTED_COLUMNS = {"NOC21 Code", "City"}

_MONTH_PATTERN = re.compile(r"(20\d{2})[-_]?(\d{2})")


def discover_monthly_resources(language=None, limit=None):
    """
    Auto-discover monthly CSV resources from the CKAN dataset API, returning
    the resource metadata dicts (not just URLs) so the month label and
    provenance can be derived without guessing from the URL alone.
    """
    language = language or config.LANGUAGE
    resp = requests.get(CKAN_PACKAGE_URL, timeout=config.REQUEST_TIMEOUT_SECONDS)
    resp.raise_for_status()
    resources = resp.json()["result"]["resources"]

    monthly = [
        r
        for r in resources
        if r.get("format") == "CSV" and language in (r.get("language") or []) and r.get("url")
    ]

    if limit is not None:
        monthly = monthly[:limit]

    logger.info("Discovered %d '%s' CSV resource(s) from the CKAN API.", len(monthly), language)
    return monthly


def infer_month_label(resource, fallback_index):
    """
    Best-effort extraction of a YYYY-MM label from a CKAN resource's
    metadata. Tries the resource name, then the URL, then last_modified /
    created dates, then falls back to a positional label (nothing is ever
    silently dropped just for lacking a clean label, but unclear cases are
    logged so it is possible to notice them.)
    """
    for field in ("name", "url"):
        value = resource.get(field) or ""
        match = _MONTH_PATTERN.search(value)
        if match:
            return f"{match.group(1)}-{match.group(2)}"

    for field in ("last_modified", "created"):
        value = resource.get(field) or ""
        match = _MONTH_PATTERN.search(value)
        if match:
            return f"{match.group(1)}-{match.group(2)}"

    logger.warning(
        "Could not infer a month label for resource id=%s name=%r -- using a positional fallback.",
        resource.get("id"),
        resource.get("name"),
    )
    return f"unknown-{fallback_index:02d}"


def parse_csv_bytes(content: bytes) -> pd.DataFrame:
    """
    Parse raw CSV bytes into a DataFrame, trying known Job Bank
    encoding/delimiter combinations in order.

    Job Bank's export format isn't consistent across months: recent files
    are UTF-16 + tab-delimited, older files use a different
    encoding/delimiter, and a wrong guess doesn't always raise an error --
    pandas can silently parse it into garbled columns. So each attempt is
    VALIDATED against EXPECTED_COLUMNS before being accepted, rather than
    trusting the first attempt that doesn't throw.
    """
    attempts = [
        ("utf-16", "\t"),
        ("utf-8-sig", ","),
        ("utf-8", ","),
        ("cp1252", ","),
        ("latin-1", ","),
    ]

    last_err = None
    for encoding, sep in attempts:
        try:
            df = pd.read_csv(io.BytesIO(content), encoding=encoding, sep=sep, low_memory=False)
        except Exception as e:
            last_err = e
            continue

        df.columns = df.columns.str.strip().str.replace(r"\s+", " ", regex=True)

        if df.shape[1] > 5 and EXPECTED_COLUMNS.issubset(set(df.columns)):
            return df

        last_err = RuntimeError(
            f"Parsed with encoding={encoding!r} sep={sep!r} but got "
            f"{df.shape[1]} column(s) and missing expected headers; "
            f"first columns: {list(df.columns)[:5]}"
        )

    raise RuntimeError(f"Could not parse CSV content: {last_err}")


def fetch_csv(url: str) -> pd.DataFrame:
    """Download a single Job Bank monthly CSV (with retries) and parse it."""
    content = _get_with_retries(url)
    return parse_csv_bytes(content)


def _get_with_retries(url: str) -> bytes:
    """GET a URL with exponential backoff, retrying on transient failures."""
    last_exc = None
    for attempt in range(1, config.MAX_RETRIES + 1):
        try:
            resp = requests.get(url, timeout=config.REQUEST_TIMEOUT_SECONDS)
            resp.raise_for_status()
            return resp.content
        except requests.RequestException as e:
            last_exc = e
            if attempt < config.MAX_RETRIES:
                delay = config.BACKOFF_BASE_SECONDS * (2 ** (attempt - 1))
                logger.warning(
                    "Attempt %d/%d failed for %s (%s) -- retrying in %.0fs",
                    attempt,
                    config.MAX_RETRIES,
                    url,
                    e,
                    delay,
                )
                time.sleep(delay)
    raise RuntimeError(f"Failed to fetch {url} after {config.MAX_RETRIES} attempts: {last_exc}")


def _check_schema_drift(month, columns, previous_columns):
    """Log loudly if this month's columns differ from the previous month's."""
    if previous_columns is None:
        return

    current = set(columns)
    previous = set(previous_columns)

    added = current - previous
    removed = previous - current

    if added or removed:
        logger.warning(
            "Schema drift detected at %s -- added: %s, removed: %s",
            month,
            sorted(added) or "none",
            sorted(removed) or "none",
        )


def run(language=None, limit=None):
    """
    Download every monthly resource not already recorded in the manifest,
    writing each as its own file under RAW_DIR and appending a manifest
    entry. Safe to rerun -- already-downloaded months are skipped.
    """
    language = language or config.LANGUAGE
    limit = limit if limit is not None else config.MONTHS_TO_FETCH

    config.RAW_DIR.mkdir(parents=True, exist_ok=True)
    already_downloaded = load_downloaded_months(config.MANIFEST_PATH)
    logger.info("%d month(s) already in the manifest, will be skipped.", len(already_downloaded))

    resources = discover_monthly_resources(language=language, limit=limit)

    previous_columns = None
    downloaded, skipped, failed = 0, 0, 0

    for i, resource in enumerate(resources):
        month = infer_month_label(resource, fallback_index=i)

        if month in already_downloaded:
            logger.info("Skipping %s -- already downloaded.", month)
            skipped += 1
            continue

        url = resource["url"]
        logger.info("Downloading %s from %s", month, url)

        try:
            df = fetch_csv(url)
        except Exception as e:
            logger.error("Failed to fetch/parse %s: %s", month, e)
            failed += 1
            continue

        _check_schema_drift(month, list(df.columns), previous_columns)
        previous_columns = list(df.columns)

        file_path = config.RAW_DIR / f"job_postings_{month}.csv"
        df.to_csv(file_path, index=False)

        append_entry(
            config.MANIFEST_PATH,
            month=month,
            url=url,
            file_path=file_path,
            row_count=len(df),
            column_count=df.shape[1],
            columns=list(df.columns),
        )

        logger.info("Saved %s: %d rows, %d columns -> %s", month, len(df), df.shape[1], file_path)
        downloaded += 1
        time.sleep(config.PAUSE_BETWEEN_DOWNLOADS_SECONDS)

    logger.info(
        "Done. downloaded=%d skipped=%d failed=%d total_in_manifest=%d",
        downloaded,
        skipped,
        failed,
        len(load_downloaded_months(config.MANIFEST_PATH)),
    )


if __name__ == "__main__":
    run()
