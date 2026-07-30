#!/usr/bin/env python3

from pathlib import Path

try:
    from PIL import Image
except ImportError as error:
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from error


project_dir = Path(__file__).resolve().parent.parent
source_png = project_dir / "Resources" / "AppIcon" / "AeroPeek-1024.png"
output_icns = project_dir / "Resources" / "AeroPeek.icns"

sizes = [
    (16, 16),
    (32, 32),
    (64, 64),
    (128, 128),
    (256, 256),
    (512, 512),
    (1024, 1024),
]

with Image.open(source_png) as source:
    source.convert("RGBA").save(output_icns, format="ICNS", sizes=sizes)

print(output_icns)
