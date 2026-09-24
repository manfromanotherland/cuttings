#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate a deterministic, offline mixed library. Never uses the user's library."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import zlib

VERSION = 1


def png(width, height, seed):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    rows = []
    for y in range(height):
        row = bytes(value for x in range(width) for value in (
            (x // 7 + y // 5 + seed * 31) % 256,
            (x // 13 + y // 3 + seed * 53) % 256,
            ((x // 32 ^ y // 32) * 23 + seed * 17) % 256,
        ))
        rows.append(b"\0" + row)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b"")


def generate(root, count):
    manifest_path = root / "fixture.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if manifest.get("version") == VERSION and manifest.get("count") == count:
            return manifest
        raise SystemExit("Fixture exists with different parameters; choose a new output directory.")
    if root.exists() and any(root.iterdir()):
        raise SystemExit("Refusing to generate into a nonempty directory without a fixture manifest.")
    root.mkdir(parents=True, exist_ok=True)
    media = root / "fixture-media"
    media.mkdir()

    def asset(data, extension):
        path = media / (hashlib.sha256(data).hexdigest() + extension)
        path.write_bytes(data)
        return path

    images = [asset(png(w, h, index), ".png") for index, (w, h) in enumerate([
        (1536, 1024), (1024, 1536), (1600, 900), (1200, 1200),
    ])]
    svg = asset(b'<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="700">'
                b'<rect width="1000" height="700" fill="#386078"/>'
                b'<circle cx="500" cy="350" r="240" fill="#dfbc85"/></svg>', ".svg")
    favicon = asset(png(32, 32, 9), ".png")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg is required to generate the deterministic local video fixture.")
    movie = media / "movie.mp4"
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
        "testsrc2=size=640x360:rate=30", "-t", "2", "-an", "-c:v", "libx264",
        "-pix_fmt", "yuv420p", "-threads", "1", "-fflags", "+bitexact",
        "-flags:v", "+bitexact", "-map_metadata", "-1", "-movflags", "+faststart", str(movie),
    ], check=True)
    video = asset(movie.read_bytes(), ".mp4")
    movie.unlink()
    counts = {"image": 0, "article": 0, "quote": 0, "video": 0}
    base_date = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
    digest = hashlib.sha256()
    for index in range(count):
        url = f"https://performance.invalid/reading/{index:05d}"
        reading_id = hashlib.sha256(url.encode()).hexdigest()
        directory = root / "articles" / reading_id[:2] / reading_id
        assets = directory / "assets"
        assets.mkdir(parents=True)
        slot = index % 10
        kind = "image" if slot < 6 else "article" if slot < 8 else "quote" if slot == 8 else "video"
        counts[kind] += 1
        title = f"Performance fixture {index:05d}: {kind}"
        body = (f"# {title}\n\n" + "Local files, measured interactions, deterministic content. " * (1 + index % 7))
        fields = {
            "format_version": 1, "id": reading_id, "url": url, "canonical_url": url,
            "title": title, "kind": kind, "site": "Performance fixture",
            "saved_at": (base_date + datetime.timedelta(seconds=index)).isoformat().replace("+00:00", "Z"),
            "archived": False, "favorite": False, "rating": 0,
            "tags": [f"collection-{index % 64}", f"subject-{index % 257}"],
            "excerpt": ("Measured scrolling stays responsive while saved media appears. " * (1 + index % 4)),
            "source_hash": "sha256:" + hashlib.sha256(body.encode()).hexdigest(),
        }
        selected = svg if index % 17 == 0 else images[index % len(images)]
        used = []
        if kind in ("image", "video"):
            source = video if kind == "video" else selected
            fields["media_url"] = "cuttings-asset:assets/" + source.name
            used.append(source)
        if kind == "image" or slot == 6 or (kind == "video" and index % 20 == 9):
            fields["preview_asset"] = "assets/" + selected.name
            used.append(selected)
        if kind == "article":
            fields["favicon_asset"] = "assets/" + favicon.name
            used.append(favicon)
        for source in set(used):
            os.link(source, assets / source.name)
        document = "---\n" + "".join(f"{key}: {json.dumps(value, ensure_ascii=False)}\n" for key, value in fields.items()) \
            + "---\n\n" + body + "\n"
        (directory / "article.md").write_text(document)
        digest.update(document.encode())
    manifest = {
        "version": VERSION, "count": count, "kinds": counts,
        "corpus_sha256": digest.hexdigest(), "media_sha256": sorted(p.name for p in media.iterdir()),
        "media_storage": "hardlinked within fixture; distinct per-reading cache paths",
        "limitations": "Synthetic image patterns and repeated local clips; complement with a real-library trace.",
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--count", type=int, default=10000)
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    print(json.dumps(generate(args.output.resolve(), args.count), indent=2, sort_keys=True))
