"""
src/data/upload_to_bronze.py

Replaces the manual "drag file into Catalog Explorer, then run COPY INTO
in the SQL Editor" steps with one command. For every month recorded in the
manifest as downloaded but not yet loaded into bronze, this uploads the
file to the Unity Catalog Volume and runs COPY INTO against the bronze
table, then records the month as loaded so reruns are idempotent, same
principle as download.py's manifest-based skip logic.

Credentials are read from the same DATABRICKS_HOST / DATABRICKS_HTTP_PATH /
DATABRICKS_TOKEN environment variables already set up for dbt.

Usage:
    python -m src.data.upload_to_bronze
"""

import logging
import re
import time

from databricks.sdk import WorkspaceClient

from src.data import config
from src.data.manifest import append_loaded_to_bronze, load_pending_bronze_uploads

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(message)s",
)
logger = logging.getLogger(__name__)

# Terminal states the Statement Execution API can return.
_SUCCEEDED = "SUCCEEDED"
_FAILED_STATES = {"FAILED", "CANCELED", "CLOSED"}
_IN_PROGRESS_STATES = {"PENDING", "RUNNING"}


def _extract_warehouse_id(http_path: str) -> str:
    """Pulls the warehouse ID out of an HTTP path like /sql/1.0/warehouses/abc123."""
    if not http_path:
        raise ValueError(
            "DATABRICKS_HTTP_PATH is not set . Expected the same value used in "
            "your dbt profiles.yml (e.g. /sql/1.0/warehouses/xxxxxxxxxxxxxxxx)."
        )
    match = re.search(r"warehouses/([a-zA-Z0-9]+)", http_path)
    if not match:
        raise ValueError(f"Could not extract a warehouse ID from http_path: {http_path!r}")
    return match.group(1)


def _run_copy_into(client: WorkspaceClient, warehouse_id: str, volume_file_path: str) -> None:
    """Runs COPY INTO for one file, polling until the statement finishes.

    Note: COPY INTO tracks which files it has loaded in its own internal
    ledger, separate from the table's data -- TRUNCATE TABLE does not reset
    this ledger. If bronze ever needs a full reload, either temporarily add
    COPY_OPTIONS ('force' = 'true') to the statement below (and remove it
    again immediately after), or drop and recreate the table entirely.
    """
    statement = f"""
        COPY INTO {config.BRONZE_TABLE}
        FROM '{volume_file_path}'
        FILEFORMAT = CSV
        FORMAT_OPTIONS ('header' = 'true')
    """

    response = client.statement_execution.execute_statement(
        warehouse_id=warehouse_id,
        statement=statement,
        wait_timeout=config.COPY_INTO_WAIT_TIMEOUT,
    )

    state = response.status.state.value if response.status and response.status.state else None
    statement_id = response.statement_id

    # If the warehouse hadn't finished within wait_timeout, poll for completion
    # rather than assuming failure -- COPY INTO on a large file can take a while.
    while state in _IN_PROGRESS_STATES:
        time.sleep(3)
        response = client.statement_execution.get_statement(statement_id)
        state = response.status.state.value if response.status and response.status.state else None

    if state != _SUCCEEDED:
        error_message = (
            response.status.error.message
            if response.status and response.status.error
            else "no error detail returned"
        )
        raise RuntimeError(f"COPY INTO did not succeed (state={state}): {error_message}")


def run(client: WorkspaceClient = None) -> None:
    """Uploads and loads every month recorded as downloaded but not yet in bronze."""
    client = client or WorkspaceClient(
        host=config.DATABRICKS_HOST,
        token=config.DATABRICKS_TOKEN,
    )
    warehouse_id = _extract_warehouse_id(config.DATABRICKS_HTTP_PATH)

    pending = load_pending_bronze_uploads(config.MANIFEST_PATH)
    logger.info("%d month(s) pending upload to bronze.", len(pending))

    loaded, failed = 0, 0

    for entry in pending:
        month = entry["month"]
        local_path = entry["file_path"]
        file_name = local_path.split("/")[-1]
        volume_file_path = f"{config.BRONZE_VOLUME_PATH}/{file_name}"

        try:
            logger.info("Uploading %s -> %s", local_path, volume_file_path)
            client.files.upload_from(volume_file_path, local_path, overwrite=True)

            logger.info("Running COPY INTO for %s into %s", month, config.BRONZE_TABLE)
            _run_copy_into(client, warehouse_id, volume_file_path)

            append_loaded_to_bronze(config.MANIFEST_PATH, month=month, table=config.BRONZE_TABLE)
            logger.info("Loaded %s into bronze successfully.", month)
            loaded += 1

        except Exception as e:
            logger.error("Failed to upload/load %s: %s", month, e)
            failed += 1

    logger.info("Done. loaded=%d failed=%d", loaded, failed)


if __name__ == "__main__":
    run()
