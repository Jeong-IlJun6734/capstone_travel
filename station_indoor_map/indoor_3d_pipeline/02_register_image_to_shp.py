#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Step 2. Register a guide image to the SHP-based 2D graph.

Input:
- SHP 2D graph from step 1
- image control points, usually exit number positions in the image

Output:
- image-to-map affine transform
- map-to-image transform
- pixel-to-meter scale estimate
- residual errors for each control point
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Optional

import cv2
import numpy as np


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def read_image_size(path: Optional[Path]) -> Optional[List[int]]:
    if path is None:
        return None
    data = np.fromfile(str(path), dtype=np.uint8)
    img = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"이미지를 읽을 수 없음: {path}")
    height, width = img.shape[:2]
    return [int(width), int(height)]


def graph_entrance_map(graph: dict) -> Dict[str, dict]:
    result = {}
    for node in graph["nodes"]:
        if node.get("kind") == "entrance" and node.get("entrance_no") is not None:
            result[str(node["entrance_no"])] = node
    return result


def extract_control_points(path: Path) -> List[dict]:
    data = load_json(path)
    if "control_points" not in data:
        raise ValueError("control point JSON에는 control_points 배열이 필요합니다.")
    return data["control_points"]


def collect_matched_points(control_points: List[dict], entrance_nodes: Dict[str, dict]):
    src = []
    dst = []
    for cp in control_points:
        entrance_no = str(cp["entrance_no"])
        if entrance_no not in entrance_nodes:
            continue
        src.append(cp["image_xy"])
        dst.append(entrance_nodes[entrance_no]["map_xy"])
    if len(src) < 3:
        raise ValueError(f"정합에 사용할 수 있는 control point가 {len(src)}개입니다. 최소 3개가 필요합니다.")
    return np.array(src, dtype=np.float32), np.array(dst, dtype=np.float32)


def estimate_transform(control_points: List[dict], entrance_nodes: Dict[str, dict], transform_type: str) -> np.ndarray:
    src_np, dst_np = collect_matched_points(control_points, entrance_nodes)
    if transform_type == "partial_affine":
        matrix, _ = cv2.estimateAffinePartial2D(src_np, dst_np, method=cv2.LMEDS)
    elif transform_type == "affine":
        matrix, _ = cv2.estimateAffine2D(src_np, dst_np, method=cv2.LMEDS)
    elif transform_type == "homography":
        if len(src_np) < 4:
            raise ValueError("homography 정합에는 최소 4개의 control point가 필요합니다.")
        matrix, _ = cv2.findHomography(src_np, dst_np, method=cv2.RANSAC)
    else:
        raise ValueError(f"지원하지 않는 transform type: {transform_type}")
    if matrix is None:
        raise RuntimeError(f"{transform_type} image -> map transform 추정 실패")
    return matrix


def invert_transform(matrix: np.ndarray) -> np.ndarray:
    if matrix.shape == (2, 3):
        return cv2.invertAffineTransform(matrix)
    return np.linalg.inv(matrix)


def apply_transform(matrix: np.ndarray, xy) -> List[float]:
    pt = np.array([float(xy[0]), float(xy[1]), 1.0], dtype=float)
    out = matrix @ pt
    if matrix.shape == (3, 3):
        if abs(out[2]) < 1e-12:
            raise ZeroDivisionError("homogeneous transform produced near-zero scale")
        out = out / out[2]
    return [float(out[0]), float(out[1])]


def scale_from_transform(matrix: np.ndarray) -> float:
    a = matrix[:2, :2]
    sx = float(np.linalg.norm(a[:, 0]))
    sy = float(np.linalg.norm(a[:, 1]))
    return float((sx + sy) / 2.0)


def residuals(matrix: np.ndarray, control_points: List[dict], entrance_nodes: Dict[str, dict]) -> List[dict]:
    rows = []
    for cp in control_points:
        entrance_no = str(cp["entrance_no"])
        if entrance_no not in entrance_nodes:
            rows.append({
                "entrance_no": entrance_no,
                "status": "missing_in_shp_graph",
                "image_xy": cp["image_xy"],
            })
            continue
        predicted = apply_transform(matrix, cp["image_xy"])
        expected = entrance_nodes[entrance_no]["map_xy"]
        error = float(np.linalg.norm(np.array(predicted) - np.array(expected)))
        rows.append({
            "entrance_no": entrance_no,
            "status": "used",
            "image_xy": cp["image_xy"],
            "expected_map_xy": expected,
            "predicted_map_xy": predicted,
            "error_m": error,
        })
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Register guide image coordinates to SHP graph coordinates.")
    parser.add_argument("--shp-2d-graph", required=True)
    parser.add_argument("--control-points", required=True, help="JSON containing control_points; annotation draft format is accepted.")
    parser.add_argument("--image")
    parser.add_argument(
        "--transform",
        choices=["partial_affine", "affine", "homography"],
        default="homography",
        help="partial_affine: rotation/scale only, affine: shear allowed, homography: perspective tilt allowed.",
    )
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    graph = load_json(Path(args.shp_2d_graph))
    control_points = extract_control_points(Path(args.control_points))
    entrance_nodes = graph_entrance_map(graph)
    image_to_map = estimate_transform(control_points, entrance_nodes, args.transform)
    map_to_image = invert_transform(image_to_map)
    rows = residuals(image_to_map, control_points, entrance_nodes)
    used_errors = [row["error_m"] for row in rows if row["status"] == "used"]
    rmse = float(np.sqrt(np.mean(np.square(used_errors)))) if used_errors else None

    output = {
        "station_name": graph["station_name"],
        "crs": graph["crs"],
        "image": args.image,
        "image_size": read_image_size(Path(args.image)) if args.image else None,
        "transform_type": args.transform,
        "image_to_map_transform": image_to_map.tolist(),
        "map_to_image_transform": map_to_image.tolist(),
        # Backward-compatible names for older scripts. For homography these are
        # transforms, not affine matrices.
        "image_to_map_affine": image_to_map.tolist(),
        "map_to_image_affine": map_to_image.tolist(),
        "meters_per_pixel_estimate": scale_from_transform(image_to_map),
        "control_point_count": len([row for row in rows if row["status"] == "used"]),
        "rmse_m": rmse,
        "residuals": rows,
    }

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    print(f"[OK] registration saved: {out_path}")
    print(f"[OK] used control points: {output['control_point_count']}, rmse_m: {rmse}")


if __name__ == "__main__":
    main()
