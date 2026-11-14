#!/usr/bin/env python3
"""Convert the Natural Earth 1:110m land shapefile into MapMethod's compact outline JSON."""

from __future__ import annotations

import json
import struct
import sys
import zipfile
from pathlib import Path


def ring_area(points: list[tuple[float, float]]) -> float:
    return sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    ) / 2


def main() -> None:
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    with zipfile.ZipFile(source) as archive:
        data = archive.read("ne_110m_land.shp")

    rings: list[dict[str, object]] = []
    offset = 100
    while offset + 8 <= len(data):
        _, content_words = struct.unpack_from(">ii", data, offset)
        content_start = offset + 8
        content_end = content_start + content_words * 2
        content = memoryview(data)[content_start:content_end]
        offset = content_end
        shape_type = struct.unpack_from("<i", content, 0)[0]
        if shape_type == 0:
            continue
        if shape_type != 5:
            raise ValueError(f"Unexpected shape type {shape_type}; expected Polygon (5)")

        part_count, point_count = struct.unpack_from("<ii", content, 36)
        part_offset = 44
        parts = list(struct.unpack_from(f"<{part_count}i", content, part_offset))
        point_offset = part_offset + part_count * 4
        coordinates = [
            struct.unpack_from("<dd", content, point_offset + index * 16)
            for index in range(point_count)
        ]
        for part_index, start in enumerate(parts):
            end = parts[part_index + 1] if part_index + 1 < len(parts) else point_count
            points = coordinates[start:end]
            if len(points) < 4:
                continue
            # ESRI polygon rings use clockwise winding for land shells and CCW for holes.
            is_hole = ring_area(points) > 0
            rings.append({
                "points": [{"x": (longitude + 180) / 360, "y": (90 - latitude) / 360} for longitude, latitude in points],
                "isHole": is_hole,
            })

    outline = {
        "rings": rings,
        "width": 1,
        "height": 0.5,
        "sourceName": "Земля",
        "source": "Natural Earth",
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(outline, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"wrote {len(rings)} rings to {destination}")


if __name__ == "__main__":
    main()
