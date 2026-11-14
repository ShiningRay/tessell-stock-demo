#!/usr/bin/env python3
"""Convert a Tessell TSRAW capture (top-down RGBA) to PNG.

Usage:
    uv run --with pillow python tools/tsraw_to_png.py shot.tsraw shot.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tsraw_to_png.py <input.tsraw> <output.png>", file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    data = src.read_bytes()
    header, _, pixels = data.partition(b"\n")
    parts = header.split()
    if len(parts) != 4 or parts[0] != b"TSRAW" or parts[3] != b"RGBA":
        print(f"invalid TSRAW header: {header!r}", file=sys.stderr)
        return 1
    width, height = int(parts[1]), int(parts[2])
    expected = width * height * 4
    if len(pixels) != expected:
        print(
            f"pixel payload mismatch: got {len(pixels)}, expected {expected}",
            file=sys.stderr,
        )
        return 1
    image = Image.frombytes("RGBA", (width, height), pixels)
    dst.parent.mkdir(parents=True, exist_ok=True)
    image.save(dst)
    print(f"{dst} ({width}x{height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
