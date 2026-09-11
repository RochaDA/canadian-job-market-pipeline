"""
tests/test_download.py

Unit tests for the CSV-parsing fallback logic in src/data/download.py.
These don't hit the network, they feed known byte strings in each
encoding/delimiter combination Job Bank has used historically and assert
that parse_csv_bytes recovers the correct columns either way. This is the
part of the pipeline most likely to break silently, so it's the part most
worth testing. Example: I noticed a change in date encoding after 2023.
"""

import pandas as pd
import pytest

from src.data.download import infer_month_label, parse_csv_bytes


def _make_csv_bytes(encoding: str, sep: str) -> bytes:
    # Six columns to satisfy parse_csv_bytes's `df.shape[1] > 5` sanity check --
    # a too-narrow fixture here previously passed even when that check was broken.
    df = pd.DataFrame(
        {
            "NOC21 Code": ["21231", "64100"],
            "City": ["Vancouver", "Burnaby"],
            "Job Title": ["Software Engineer", "Server"],
            "Employer": ["Acme Corp", "Cafe Co"],
            "Province": ["BC", "BC"],
            "Posting Date": ["2024-03-01", "2024-03-02"],
        }
    )
    return df.to_csv(index=False, sep=sep).encode(encoding)


@pytest.mark.parametrize(
    "encoding,sep",
    [
        ("utf-16", "\t"),
        ("utf-8-sig", ","),
        ("utf-8", ","),
        ("cp1252", ","),
        ("latin-1", ","),
    ],
)
def test_parse_csv_bytes_handles_known_encodings(encoding, sep):
    content = _make_csv_bytes(encoding, sep)
    df = parse_csv_bytes(content)

    assert "NOC21 Code" in df.columns
    assert "City" in df.columns
    assert len(df) == 2


def test_parse_csv_bytes_raises_on_unrecognizable_content():
    with pytest.raises(RuntimeError):
        parse_csv_bytes(b"this is not a csv file at all, just plain text")


def test_parse_csv_bytes_strips_whitespace_from_column_names():
    content = (
        "  NOC21 Code ,City,Job Title,Employer,Province,Posting Date\n"
        "21231,Vancouver,Engineer,Acme Corp,BC,2024-03-01\n"
    ).encode("utf-8")
    df = parse_csv_bytes(content)
    assert "NOC21 Code" in df.columns


def test_infer_month_label_from_resource_name():
    resource = {"id": "abc", "name": "Job postings 2024-03", "url": "https://example.com/data.csv"}
    assert infer_month_label(resource, fallback_index=0) == "2024-03"


def test_infer_month_label_falls_back_to_positional_when_unclear():
    resource = {"id": "abc", "name": "postings export", "url": "https://example.com/data.csv"}
    assert infer_month_label(resource, fallback_index=5) == "unknown-05"
