"""
src/data/config.py

Central place for ingestion settings. Keeping these out of download.py means
you can point the pipeline at a different date range, output location, or
language without touching any logic.
"""

import os
from pathlib import Path

# Where each month's raw CSV file and the manifest get written.
RAW_DIR = Path("data/raw")
MANIFEST_PATH = RAW_DIR / "manifest.jsonl"

# Which language edition of the dataset to pull: "en" or "fr". Job Bank
# publishes both for the same postings, so mixing them would double-count.
LANGUAGE = "en"

# If set, only fetch this many of the most recent monthly resources.
# Leave as None to fetch everything the CKAN API currently lists.
MONTHS_TO_FETCH = 24

# Hardcode specific URLs here to bypass discovery entirely (useful if the
# CKAN API is unreachable but you already know the direct links).
DIRECT_URLS = []

# Network behaviour
REQUEST_TIMEOUT_SECONDS = 60
MAX_RETRIES = 3
BACKOFF_BASE_SECONDS = 2.0  # retry delays: 2s, 4s, 8s
PAUSE_BETWEEN_DOWNLOADS_SECONDS = 1.0

# Databricks upload/load settings:
# Reuses the same credentials already configured for dbt. These read from the same
# DATABRICKS_HOST / DATABRICKS_HTTP_PATH / DATABRICKS_TOKEN environment
# variables, so no new credential setup is needed.
DATABRICKS_HOST = os.environ.get("DATABRICKS_HOST")
DATABRICKS_HTTP_PATH = os.environ.get("DATABRICKS_HTTP_PATH")
DATABRICKS_TOKEN = os.environ.get("DATABRICKS_TOKEN")

BRONZE_VOLUME_PATH = "/Volumes/workspace/bronze/raw_files"
BRONZE_TABLE = "workspace.bronze.job_postings"

# How long to wait for a COPY INTO statement to finish before treating it
# as still-running and polling for the result separately.
COPY_INTO_WAIT_TIMEOUT = "50s"