#!/usr/bin/env python3
"""Download and merge observations from the LI-COR Cloud data API."""

from __future__ import annotations

import argparse
import csv
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

import requests


API_URL = "https://api.licor.cloud/v1/data"
DEFAULT_LOGGER = "22188604"
FIELDNAMES = [
    "logger_sn",
    "sensor_sn",
    "timestamp_utc",
    "data_type",
    "data_type_id",
    "value",
    "unit",
    "sensor_measurement_type",
]


def parse_timestamp(value: str) -> datetime:
    cleaned = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(cleaned)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def api_timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def csv_timestamp(value: str) -> str:
    return parse_timestamp(value).strftime("%Y-%m-%d %H:%M:%SZ")


def read_existing(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def normalize_observation(item: dict[str, Any]) -> dict[str, str]:
    return {
        "logger_sn": str(item.get("logger_sn", "")),
        "sensor_sn": str(item.get("sensor_sn", "")),
        "timestamp_utc": csv_timestamp(str(item.get("timestamp", item.get("timestamp_utc", "")))),
        "data_type": str(item.get("data_type", "")),
        "data_type_id": str(item.get("data_type_id", "")),
        "value": str(item.get("value", item.get("si_value", ""))),
        "unit": str(item.get("unit", item.get("si_unit", ""))),
        "sensor_measurement_type": str(item.get("sensor_measurement_type", "")),
    }


def fetch_window(
    session: requests.Session,
    token: str,
    logger_sn: str,
    start: datetime,
    end: datetime,
) -> list[dict[str, str]]:
    response = session.get(
        API_URL,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        params={
            "loggers": logger_sn,
            "start_date_time": api_timestamp(start),
            "end_date_time": api_timestamp(end),
        },
        timeout=90,
    )
    response.raise_for_status()
    payload = response.json()
    records = payload.get("data", payload.get("observation_list", []))
    if not isinstance(records, list):
        raise RuntimeError("LI-COR response did not contain a data list")
    if payload.get("max_results") is True:
        print(
            f"Warning: API reported max_results for {api_timestamp(start)} to {api_timestamp(end)}",
            file=sys.stderr,
        )
    return [normalize_observation(item) for item in records]


def windows(start: datetime, end: datetime, days: int = 30) -> Iterable[tuple[datetime, datetime]]:
    cursor = start
    while cursor < end:
        window_end = min(cursor + timedelta(days=days), end)
        yield cursor, window_end
        cursor = window_end


def merge_records(records: Iterable[dict[str, str]]) -> list[dict[str, str]]:
    keyed: dict[tuple[str, str, str, str], dict[str, str]] = {}
    for record in records:
        key = (
            record.get("logger_sn", ""),
            record.get("sensor_sn", ""),
            record.get("timestamp_utc", ""),
            record.get("data_type_id", ""),
        )
        keyed[key] = {field: record.get(field, "") for field in FIELDNAMES}
    return sorted(
        keyed.values(),
        key=lambda row: (row["timestamp_utc"], row["sensor_sn"], row["data_type_id"]),
    )


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="data/licor_observations.csv")
    parser.add_argument("--logger", default=os.getenv("LICOR_LOGGER_SN", DEFAULT_LOGGER))
    parser.add_argument(
        "--initial-days",
        type=int,
        default=int(os.getenv("LICOR_INITIAL_DAYS", "180")),
        help="History requested when the output file has no observations.",
    )
    args = parser.parse_args()

    token = os.getenv("LICOR_API_TOKEN", "").strip()
    if not token:
        print("LICOR_API_TOKEN is not set", file=sys.stderr)
        return 2

    output = Path(args.output)
    existing = read_existing(output)
    now = datetime.now(timezone.utc).replace(microsecond=0)

    timestamps = []
    for row in existing:
        try:
            timestamps.append(parse_timestamp(row["timestamp_utc"]))
        except (KeyError, TypeError, ValueError):
            continue

    start = max(timestamps) - timedelta(days=2) if timestamps else now - timedelta(days=args.initial_days)

    downloaded: list[dict[str, str]] = []
    with requests.Session() as session:
        for window_start, window_end in windows(start, now):
            print(f"Fetching {api_timestamp(window_start)} through {api_timestamp(window_end)}")
            downloaded.extend(
                fetch_window(session, token, args.logger, window_start, window_end)
            )

    merged = merge_records([*existing, *downloaded])
    write_csv(output, merged)
    print(f"Wrote {len(merged)} total observations ({len(downloaded)} returned this run) to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
