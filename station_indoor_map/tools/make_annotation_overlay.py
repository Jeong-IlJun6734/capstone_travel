#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
Draw an annotation JSON on top of its station guide image.

Example:
  .\.venv\Scripts\python.exe tools\make_annotation_overlay.py

Custom input:
  .\.venv\Scripts\python.exe tools\make_annotation_overlay.py `
    --annotation annotations\auto_draft_refined_test4\7_숭실대입구역_annotation_draft_with_turns.json `
    --image station_image\7\숭실대입구.jpg `
    --output indoor_3d_output\overlays\숭실대입구역_overlay.png
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


DEFAULT_ANNOTATION = Path("annotations/auto_draft_refined_test4/7_숭실대입구역_annotation_draft_with_turns.json")
DEFAULT_IMAGE = Path("station_image/7/숭실대입구.jpg")
DEFAULT_OUTPUT = Path("indoor_3d_output/overlays/숭실대입구역_annotation_overlay.png")

NODE_COLORS = {
    "entrance_connection": (30, 170, 60),
    "exit": (30, 170, 60),
    "hall": (30, 90, 220),
    "turn": (45, 45, 45),
    "platform_turn": (120, 40, 150),
    "stairs_start": (20, 120, 220),
    "stairs_landing": (0, 145, 220),
    "stairs_end": (20, 80, 180),
    "elevator": (180, 80, 30),
    "elevator_landing": (150, 95, 30),
    "platform": (170, 40, 150),
    "information": (80, 80, 80),
}

EDGE_COLORS = {
    "stairs": (210, 90, 40),
    "elevator": (180, 80, 30),
    "platform_walk": (190, 80, 190),
    "platform": (190, 80, 190),
    "walk": (70, 120, 230),
}


def read_image(path: Path):
    data = np.fromfile(str(path), dtype=np.uint8)
    image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"image read failed: {path}")
    return image


def write_image(path: Path, image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    suffix = path.suffix or ".png"
    ok, encoded = cv2.imencode(suffix, image)
    if not ok:
        raise RuntimeError(f"image encode failed: {path}")
    encoded.tofile(str(path))


def put_label(image, text: str, xy, color, scale: float) -> None:
    x, y = int(xy[0]), int(xy[1])
    origin = (x + 10, y - 8)
    cv2.putText(image, text, origin, cv2.FONT_HERSHEY_SIMPLEX, scale, (255, 255, 255), 4, cv2.LINE_AA)
    cv2.putText(image, text, origin, cv2.FONT_HERSHEY_SIMPLEX, scale, color, 2, cv2.LINE_AA)


def draw_overlay(image, annotation: dict, label_mode: str, label_scale: float):
    nodes = {node["id"]: node for node in annotation.get("nodes", [])}

    for edge in annotation.get("edges", []):
        start = nodes.get(edge.get("from"))
        end = nodes.get(edge.get("to"))
        if not start or not end:
            continue

        sx, sy = map(int, start["image_xy"])
        ex, ey = map(int, end["image_xy"])
        kind = edge.get("kind", "walk")
        color = EDGE_COLORS.get(kind, EDGE_COLORS["walk"])
        cv2.line(image, (sx, sy), (ex, ey), color, 4, cv2.LINE_AA)

    for node in annotation.get("nodes", []):
        xy = node["image_xy"]
        kind = node.get("kind", "")
        color = NODE_COLORS.get(kind, (40, 40, 40))
        x, y = map(int, xy)
        radius = 12 if kind in {"entrance_connection", "exit"} else 9

        cv2.circle(image, (x, y), radius, color, -1, cv2.LINE_AA)
        cv2.circle(image, (x, y), radius + 2, (255, 255, 255), 2, cv2.LINE_AA)

        if label_mode == "none":
            continue
        if label_mode == "entrance":
            label = node.get("entrance_no")
            if not label:
                continue
        elif label_mode == "kind":
            label = kind
        else:
            label = node.get("entrance_no") or node["id"]
        put_label(image, str(label), xy, color, label_scale)

    return image


def validate_annotation(annotation: dict) -> None:
    node_ids = {node["id"] for node in annotation.get("nodes", [])}
    missing = [
        (edge.get("from"), edge.get("to"))
        for edge in annotation.get("edges", [])
        if edge.get("from") not in node_ids or edge.get("to") not in node_ids
    ]
    if missing:
        raise ValueError(f"edge references missing node ids: {missing}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Draw route annotation nodes and edges over a station guide image.")
    parser.add_argument("--annotation", type=Path, default=DEFAULT_ANNOTATION)
    parser.add_argument("--image", type=Path, default=DEFAULT_IMAGE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--label-mode", choices=["id", "entrance", "kind", "none"], default="id")
    parser.add_argument("--label-scale", type=float, default=0.45)
    args = parser.parse_args()

    annotation = json.loads(args.annotation.read_text(encoding="utf-8"))
    validate_annotation(annotation)

    image = read_image(args.image)
    overlay = draw_overlay(image, annotation, args.label_mode, args.label_scale)
    write_image(args.output, overlay)

    print(f"[OK] annotation: {args.annotation}")
    print(f"[OK] image: {args.image}")
    print(f"[OK] output: {args.output}")
    print(f"[OK] nodes: {len(annotation.get('nodes', []))}, edges: {len(annotation.get('edges', []))}")


if __name__ == "__main__":
    main()
