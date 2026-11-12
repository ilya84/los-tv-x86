#!/usr/bin/env python3
"""make-ota-index.py — JSON для LineageOS Updater (v2) из full-OTA zip.

Пример:
  ./scripts/make-ota-index.py \
      --url-prefix https://ota.example.com/ota/ \
      --out /srv/ota/x86_64_tv.json \
      out/target/product/x86_64_tv/lineage_x86_64_tv-ota-full.zip

Updater (packages/apps/Updater) ожидает массив объектов:
  datetime, type, version, files[{filename, os_patch_level, os_sdk_level,
  ota_property_files, sha256, size, url}].

Важно:
  * URL должен быть HTTPS (Updater проверяет префикс https://);
  * type должен совпадать с ro.lineage.releasetype (сейчас UNOFFICIAL);
  * datetime должен быть больше ro.build.date.utc текущей системы, иначе
    Updater скроет обновление; по умолчанию берётся post-timestamp из
    META-INF/com/android/metadata, для теста можно --datetime $(date +%s);
  * ota_property_files берётся из metadata OTA (готовый диапазон для
    streaming); если его нет — вычисляется по zip для payload.bin /
    payload_properties.txt.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import zipfile


def parse_metadata(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def zip_ranges(zf: zipfile.ZipFile, names: list[str]) -> str:
    """Fallback для ota_property_files: offset:size только для stored-файлов."""
    parts: list[str] = []
    for name in names:
        try:
            info = zf.getinfo(name)
        except KeyError:
            continue
        if info.compress_type != zipfile.ZIP_STORED:
            raise SystemExit(
                f"{name}: сжат внутри zip; streaming невозможен, нужен ota_property_files"
            )
        offset = info.header_offset + 30 + len(info.filename.encode()) + len(info.extra)
        parts.append(f"{name}:{offset}:{info.compress_size}")
    return ",".join(parts)


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def build_entry(
    path: str,
    url: str,
    release_type: str,
    version: str,
    datetime_override: int | None,
) -> dict:
    with zipfile.ZipFile(path) as zf:
        try:
            meta = parse_metadata(
                zf.read("META-INF/com/android/metadata").decode("utf-8", "replace")
            )
        except KeyError:
            meta = {}
        prop_files = meta.get("ota-property-files", "")
        if not prop_files:
            prop_files = zip_ranges(zf, ["payload.bin", "payload_properties.txt"])
        if not prop_files:
            raise SystemExit(f"{path}: нет payload.bin/payload_properties.txt")

    if datetime_override is not None:
        dt = datetime_override
    else:
        try:
            dt = int(meta.get("post-timestamp", "0"))
        except ValueError:
            dt = 0
        if dt <= 0:
            dt = int(os.path.getmtime(path))

    file_entry: dict = {
        "filename": os.path.basename(path),
        "sha256": sha256(path),
        "size": os.path.getsize(path),
        "url": url,
        "ota_property_files": prop_files.replace("\n", "").replace("\t", "").strip(),
    }
    if meta.get("post-security-patch-level"):
        file_entry["os_patch_level"] = meta["post-security-patch-level"]
    if meta.get("post-sdk-level"):
        try:
            file_entry["os_sdk_level"] = int(meta["post-sdk-level"])
        except ValueError:
            pass

    return {
        "datetime": dt,
        "type": release_type,
        "version": version,
        "files": [file_entry],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("zips", nargs="+", help="full-OTA zip (lineage_* -ota-full.zip)")
    ap.add_argument("--url-prefix", required=True,
                    help="префикс URL; к нему добавляется basename zip")
    ap.add_argument("--out", help="куда писать JSON (по умолчанию stdout)")
    ap.add_argument("--type", default="UNOFFICIAL",
                    help="тип релиза, должен совпадать с ro.lineage.releasetype")
    ap.add_argument("--version", default="23.2", help="версия LineageOS")
    ap.add_argument("--datetime", type=int,
                    help="переопределить datetime (Unix time) для теста")
    args = ap.parse_args()

    entries = []
    for path in args.zips:
        if not os.path.isfile(path):
            raise SystemExit(f"нет файла: {path}")
        url = args.url_prefix.rstrip("/") + "/" + os.path.basename(path)
        entries.append(build_entry(path, url, args.type, args.version, args.datetime))

    text = json.dumps(entries, ensure_ascii=False, indent=2) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
