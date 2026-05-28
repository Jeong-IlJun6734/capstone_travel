#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


COLORS = {
    "entrance_connection": (30, 170, 60),
    "hall": (30, 90, 220),
    "stairs_start": (20, 120, 220),
    "stairs_end": (20, 80, 180),
    "elevator": (180, 80, 30),
    "platform": (170, 40, 150),
    "information": (80, 80, 80),
    "qr": (0, 150, 200),
}


def read_image(path: Path):
    data = np.fromfile(str(path), dtype=np.uint8)
    image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"image read failed: {path}")
    return image


def put_text(image, text: str, xy, color):
    x, y = int(xy[0]), int(xy[1])
    cv2.putText(image, text, (x + 10, y - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 4, cv2.LINE_AA)
    cv2.putText(image, text, (x + 10, y - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2, cv2.LINE_AA)


def main() -> None:
    parser = argparse.ArgumentParser(description="Draw routing annotation nodes/edges over a station guide image.")
    parser.add_argument("--image", required=True)
    parser.add_argument("--annotation", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    image = read_image(Path(args.image))
    with Path(args.annotation).open("r", encoding="utf-8") as f:
        annotation = json.load(f)

    nodes = {node["id"]: node for node in annotation.get("nodes", [])}
    for edge in annotation.get("edges", []):
        a = nodes.get(edge.get("from"))
        b = nodes.get(edge.get("to"))
        if not a or not b:
            continue
        ax, ay = map(int, a["image_xy"])
        bx, by = map(int, b["image_xy"])
        color = (210, 90, 40) if edge.get("kind") in {"stairs", "elevator"} else (70, 120, 230)
        cv2.line(image, (ax, ay), (bx, by), color, 4, cv2.LINE_AA)

    for node in annotation.get("nodes", []):
        xy = node["image_xy"]
        kind = node.get("kind", "")
        color = COLORS.get(kind, (40, 40, 40))
        x, y = map(int, xy)
        radius = 12 if kind == "entrance_connection" else 9
        cv2.circle(image, (x, y), radius, color, -1, cv2.LINE_AA)
        cv2.circle(image, (x, y), radius + 2, (255, 255, 255), 2, cv2.LINE_AA)
        label = node.get("entrance_no") or node["id"].replace("_connection", "")
        put_text(image, str(label), xy, color)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    ok, encoded = cv2.imencode(out.suffix or ".png", image)
    if not ok:
        raise RuntimeError(f"image encode failed: {out}")
    encoded.tofile(str(out))
    print(f"[OK] overlay saved: {out}")


if __name__ == "__main__":
    main()
