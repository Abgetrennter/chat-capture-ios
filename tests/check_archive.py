"""Check the Swift-generated archive with Python's ZIP reader."""
from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

def main(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "ZIP CRC mismatch"
        records = archive.read("items.jsonl").decode("utf-8").splitlines()
        items = [json.loads(record) for record in records]
        assert len(items) == 5
        assert items[1]["v"] == "\n乙\n2026年09月30日 10:00\n[图片]\n"
        assert items[2]["name"] == "原图.png"
        assert archive.read(items[2]["file"]).startswith(b"\x89PNG\r\n\x1a\n")
        assert archive.read(items[4]["file"]).decode("utf-8") == "保留原始内容\n"
        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["textItems"] == 3
        assert len(manifest["assets"]) == 2
    print("Swift -> ZIP -> Python ordered node/asset compatibility passed")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
