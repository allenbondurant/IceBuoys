#!/usr/bin/env python3
"""Copy recent SpyPoint images into the app and create a camera manifest."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from PIL import Image, ImageOps


def image_timestamp(path: Path, source_timezone: str) -> datetime:
    try:
        with Image.open(path) as image:
            exif = image.getexif()
            raw = exif.get(36867) or exif.get(306)
            if raw:
                local_time = datetime.strptime(str(raw), "%Y:%m:%d %H:%M:%S")
                return local_time.replace(tzinfo=ZoneInfo(source_timezone)).astimezone(timezone.utc)
    except (OSError, TypeError, ValueError):
        pass
    return datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)


def sanitized_name(path: Path, timestamp: datetime) -> str:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()[:10]
    return f"{timestamp.strftime('%Y%m%dT%H%M%SZ')}_{digest}.jpg"


def save_without_metadata(source: Path, destination: Path) -> None:
    with Image.open(source) as image:
        clean = ImageOps.exif_transpose(image).convert("RGB")
        clean.thumbnail((1920, 1920))
        clean.save(destination, format="JPEG", quality=88, optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", help="Folder created by the existing SpyPoint downloader")
    parser.add_argument("--site-id", default="dot-lake")
    parser.add_argument("--destination", default=None)
    parser.add_argument("--manifest", default="data/camera_manifest.csv")
    parser.add_argument("--keep", type=int, default=60)
    parser.add_argument(
        "--source-timezone",
        default=os.getenv("CAMERA_TIMEZONE", "America/Anchorage"),
        help="Timezone used by timestamps embedded in the camera photographs.",
    )
    parser.add_argument(
        "--raw-base-url",
        default=os.getenv("CAMERA_RAW_BASE_URL", ""),
        help="Public URL ending at the camera folder; blank uses Shiny's local www path.",
    )
    args = parser.parse_args()

    source = Path(args.source)
    destination = Path(args.destination or f"www/camera/{args.site_id}")
    manifest = Path(args.manifest)
    if not source.exists():
        raise SystemExit(f"SpyPoint source folder does not exist: {source}")

    candidates = [
        path for path in source.rglob("*")
        if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg"}
    ]
    ranked = sorted(
        ((image_timestamp(path, args.source_timezone), path) for path in candidates),
        key=lambda item: item[0],
        reverse=True,
    )[: args.keep]

    destination.mkdir(parents=True, exist_ok=True)
    manifest.parent.mkdir(parents=True, exist_ok=True)
    retained_names: set[str] = set()
    rows = []

    for timestamp, source_image in ranked:
        filename = sanitized_name(source_image, timestamp)
        retained_names.add(filename)
        output_image = destination / filename
        if not output_image.exists():
            save_without_metadata(source_image, output_image)

        if args.raw_base_url:
            image_url = f"{args.raw_base_url.rstrip('/')}/{filename}"
        else:
            image_url = f"camera/{args.site_id}/{filename}"

        rows.append({
            "site_id": args.site_id,
            "timestamp_utc": timestamp.strftime("%Y-%m-%d %H:%M:%SZ"),
            "image_url": image_url,
            "caption": "SpyPoint site image",
        })

    for existing in destination.glob("*.jpg"):
        if existing.name not in retained_names:
            existing.unlink()

    other_sites = []
    if manifest.exists():
        with manifest.open("r", encoding="utf-8-sig", newline="") as handle:
            for existing_row in csv.DictReader(handle):
                if existing_row.get("site_id", "dot-lake") != args.site_id:
                    other_sites.append(existing_row)

    all_rows = sorted(
        [*other_sites, *rows],
        key=lambda row: row.get("timestamp_utc", ""),
        reverse=True,
    )

    with manifest.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["site_id", "timestamp_utc", "image_url", "caption"])
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"Prepared {len(rows)} recent images and wrote {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
