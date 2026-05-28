#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Step 3. Build a 3D indoor graph from image-space indoor structure nodes.

Input:
- registration JSON from step 2
- indoor structure JSON containing nodes and edges in image coordinates
- optional station base JSON for depth hints

Output:
- 3D graph JSON
- 3D node GeoJSON, with z_m as a property and XYZ geometry where supported
- 3D edge GeoJSON, with distance_2d_m and distance_3d_m
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Dict, List, Optional

import geopandas as gpd
import numpy as np
from shapely.geometry import LineString, Point


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def apply_transform(matrix, xy) -> List[float]:
    pt = np.array([float(xy[0]), float(xy[1]), 1.0], dtype=float)
    mat = np.array(matrix, dtype=float)
    out = mat @ pt
    if mat.shape == (3, 3):
        if abs(out[2]) < 1e-12:
            raise ZeroDivisionError("homogeneous transform produced near-zero scale")
        out = out / out[2]
    return [float(out[0]), float(out[1])]


def parse_floor_depths(value: Optional[str], station_base: Optional[dict]) -> Dict[str, float]:
    depths = {
        "ground": 0.0,
        "G": 0.0,
        "1F": 0.0,
        "B1": -4.0,
        "B2": -8.0,
        "B3": -12.0,
        "B4": -16.0,
    }
    if station_base:
        station_depth = station_base.get("depth_station_ref_m")
        track_depth = station_base.get("depth_track_ref_m")
        floor_text = station_base.get("floor_text")
        if floor_text and station_depth is not None:
            depths[str(floor_text)] = -float(station_depth)
        if track_depth is not None:
            # Most Seoul Metro station guide maps mark platform as B2 for
            # shallow underground line stations. This is a heuristic until
            # floor-specific elevation data is available.
            depths.setdefault("platform", -float(track_depth))
            depths["B2_platform"] = -float(track_depth)
    if value:
        for item in value.split(","):
            if "=" not in item:
                continue
            floor, z = item.split("=", 1)
            depths[floor.strip()] = float(z)
    return depths


def z_for_node(node: dict, depths: Dict[str, float]) -> float:
    if "z_m" in node and node["z_m"] is not None:
        return float(node["z_m"])
    floor = node.get("floor")
    kind = node.get("kind")
    if floor in depths:
        return depths[floor]
    if kind == "platform" and "platform" in depths:
        return depths["platform"]
    if isinstance(floor, str) and "-" in floor:
        parts = [part.strip() for part in floor.split("-") if part.strip() in depths]
        if parts:
            return float(sum(depths[part] for part in parts) / len(parts))
    if isinstance(floor, str) and floor.startswith("B") and floor[1:].isdigit():
        return -4.0 * int(floor[1:])
    return 0.0


def distance_3d(a: dict, b: dict) -> float:
    ax, ay, az = a["map_xyz"]
    bx, by, bz = b["map_xyz"]
    return float(math.dist((ax, ay, az), (bx, by, bz)))


def distance_2d(a: dict, b: dict) -> float:
    ax, ay = a["map_xy"]
    bx, by = b["map_xy"]
    return float(math.dist((ax, ay), (bx, by)))


def build_3d_graph(registration: dict, structure: dict, station_base: Optional[dict], floor_depths: Dict[str, float]) -> dict:
    matrix = registration.get("image_to_map_transform", registration["image_to_map_affine"])
    nodes = []
    for node in structure.get("nodes", []):
        if "image_xy" not in node:
            raise ValueError(f"node에 image_xy가 없습니다: {node.get('id')}")
        map_xy = apply_transform(matrix, node["image_xy"])
        z_m = z_for_node(node, floor_depths)
        out = {
            "id": node["id"],
            "kind": node.get("kind"),
            "floor": node.get("floor"),
            "image_xy": node["image_xy"],
            "map_xy": map_xy,
            "z_m": z_m,
            "map_xyz": [map_xy[0], map_xy[1], z_m],
        }
        for key in ("entrance_no", "direction", "accessibility"):
            if key in node:
                out[key] = node[key]
        nodes.append(out)

    node_map = {node["id"]: node for node in nodes}
    edges = []
    for edge in structure.get("edges", []):
        from_id = edge["from"]
        to_id = edge["to"]
        if from_id not in node_map or to_id not in node_map:
            raise ValueError(f"edge가 없는 node를 참조합니다: {from_id} -> {to_id}")
        a = node_map[from_id]
        b = node_map[to_id]
        edges.append({
            "from": from_id,
            "to": to_id,
            "kind": edge.get("kind"),
            "distance_2d_m": distance_2d(a, b),
            "distance_3d_m": distance_3d(a, b),
        })

    return {
        "station_name": registration["station_name"],
        "crs": registration["crs"],
        "registration": registration,
        "floor_depths_m": floor_depths,
        "nodes": nodes,
        "edges": edges,
    }


def write_outputs(graph: dict, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    station_name = graph["station_name"]
    with (output_dir / f"{station_name}_indoor_3d_graph.json").open("w", encoding="utf-8") as f:
        json.dump(graph, f, ensure_ascii=False, indent=2)

    node_gdf = gpd.GeoDataFrame(
        [
            {
                "id": node["id"],
                "kind": node.get("kind"),
                "floor": node.get("floor"),
                "z_m": node["z_m"],
                "geometry": Point(node["map_xyz"]),
            }
            for node in graph["nodes"]
        ],
        geometry="geometry",
        crs=graph["crs"],
    )
    node_gdf.to_file(output_dir / f"{station_name}_indoor_3d_nodes.geojson", driver="GeoJSON")

    node_map = {node["id"]: node for node in graph["nodes"]}
    edge_gdf = gpd.GeoDataFrame(
        [
            {
                "from_id": edge["from"],
                "to_id": edge["to"],
                "kind": edge.get("kind"),
                "distance_2d_m": edge["distance_2d_m"],
                "distance_3d_m": edge["distance_3d_m"],
                "geometry": LineString([node_map[edge["from"]]["map_xyz"], node_map[edge["to"]]["map_xyz"]]),
            }
            for edge in graph["edges"]
        ],
        columns=["from_id", "to_id", "kind", "distance_2d_m", "distance_3d_m", "geometry"],
        geometry="geometry",
        crs=graph["crs"],
    )
    edge_gdf.to_file(output_dir / f"{station_name}_indoor_3d_edges.geojson", driver="GeoJSON")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build 3D indoor graph from registered image-space structure.")
    parser.add_argument("--registration", required=True)
    parser.add_argument("--indoor-structure", required=True, help="JSON containing nodes and edges in image coordinates.")
    parser.add_argument("--station-base")
    parser.add_argument("--floor-depths", help='Comma-separated mapping, e.g. "B1=-4,B2=-9.5,ground=0"')
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    registration = load_json(Path(args.registration))
    structure = load_json(Path(args.indoor_structure))
    station_base = load_json(Path(args.station_base)) if args.station_base else None
    floor_depths = parse_floor_depths(args.floor_depths, station_base)

    graph = build_3d_graph(registration, structure, station_base, floor_depths)
    write_outputs(graph, Path(args.output_dir))
    print(f"[OK] {graph['station_name']}: {len(graph['nodes'])} 3D nodes, {len(graph['edges'])} 3D edges")


if __name__ == "__main__":
    main()
