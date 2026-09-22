#!/usr/bin/env python3

import json
import os
import pathlib
import sys
import urllib.parse
import urllib.request


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: download_storage.py OBJECTS_JSON OUTPUT_DIR")
    base_url = os.environ["SUPABASE_URL"].rstrip("/")
    service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    objects = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    output_root = pathlib.Path(sys.argv[2])
    for item in objects:
        bucket = item["bucket_id"]
        name = item["name"]
        relative = pathlib.PurePosixPath(bucket) / pathlib.PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeError(f"unsafe Storage object path: {relative}")
        destination = output_root.joinpath(*relative.parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        encoded_bucket = urllib.parse.quote(bucket, safe="")
        encoded_name = urllib.parse.quote(name, safe="/")
        request = urllib.request.Request(
            f"{base_url}/storage/v1/object/{encoded_bucket}/{encoded_name}",
            headers={"Authorization": f"Bearer {service_key}", "apikey": service_key},
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            destination.write_bytes(response.read())
        expected_size = int(item.get("size") or 0)
        if expected_size and destination.stat().st_size != expected_size:
            raise RuntimeError(f"size mismatch for Storage object: {relative}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
