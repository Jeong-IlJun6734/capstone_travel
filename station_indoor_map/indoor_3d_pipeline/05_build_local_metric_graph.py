#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build an indoor routing graph in a local metric coordinate system.

This does not project indoor nodes into EPSG/map coordinates. Instead it keeps
the guide image as the coordinate source and estimates one meters-per-pixel
scale from known entrance distances in the SHP 2D graph.

Output coordinates are relative metric coordinates:
- local_xy_m = image pixel coordinates scaled by meters_per_pixel, with an
  optional y-axis projection correction for oblique 3D guide maps
- local_xyz_m = local_xy_m plus floor z_m

The result is useful for routing because edge costs are in meters, while the
graph shape still follows the manually annotated guide-image paths.
"""

from __future__ import annotations

import argparse
import json
import math
from itertools import combinations
from pathlib import Path
from typing import Dict, List, Optional

import geopandas as gpd
import numpy as np
from shapely.geometry import LineString, Point


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def graph_entrance_map(shp_2d_graph: dict) -> Dict[str, dict]:
    result = {}
    for node in shp_2d_graph.get("nodes", []):
        if node.get("kind") == "entrance" and node.get("entrance_no") is not None:
            result[str(node["entrance_no"])] = node
    return result


def matched_control_points(annotation: dict, entrance_nodes: Dict[str, dict]) -> List[dict]:
    rows = []
    for cp in annotation.get("control_points", []):
        entrance_no = str(cp.get("entrance_no"))
        entrance = entrance_nodes.get(entrance_no)
        if not entrance:
            continue
        rows.append({
            "entrance_no": entrance_no,
            "image_xy": [float(cp["image_xy"][0]), float(cp["image_xy"][1])],
            "map_xy": [float(entrance["map_xy"][0]), float(entrance["map_xy"][1])],
        })
    if len(rows) < 2:
        raise ValueError("At least two matched control points are required to estimate scale.")
    return rows


def estimate_meters_per_pixel(matches: List[dict]) -> dict:
    pair_scales = []
    for a, b in combinations(matches, 2):
        image_dist_px = math.dist(a["image_xy"], b["image_xy"])
        map_dist_m = math.dist(a["map_xy"], b["map_xy"])
        if image_dist_px <= 1e-9 or map_dist_m <= 1e-9:
            continue
        pair_scales.append({
            "from_entrance_no": a["entrance_no"],
            "to_entrance_no": b["entrance_no"],
            "image_dist_px": image_dist_px,
            "map_dist_m": map_dist_m,
            "meters_per_pixel": map_dist_m / image_dist_px,
        })
    if not pair_scales:
        raise ValueError("No usable control point pairs for scale estimation.")

    values = np.array([row["meters_per_pixel"] for row in pair_scales], dtype=float)
    scale = float(np.median(values))
    residuals = []
    for row in pair_scales:
        estimated_m = row["image_dist_px"] * scale
        residuals.append({
            **row,
            "estimated_m": estimated_m,
            "error_m": estimated_m - row["map_dist_m"],
            "abs_error_m": abs(estimated_m - row["map_dist_m"]),
        })
    rmse = float(np.sqrt(np.mean(np.square([r["error_m"] for r in residuals]))))
    return {
        "method": "median_pairwise_entrance_distance_scale",
        "meters_per_pixel": scale,
        "pair_count": len(pair_scales),
        "rmse_m": rmse,
        "pair_scales": residuals,
    }


def parse_floor_depths(value: Optional[str]) -> Dict[str, float]:
    depths = {
        "ground": 0.0,
        "G": 0.0,
        "1F": 0.0,
        "B1": -4.0,
        "B2": -8.0,
        "B3": -12.0,
        "B4": -16.0,
        "B5": -20.0,
        "B6": -24.0,
    }
    if value:
        for item in value.split(","):
            if "=" not in item:
                continue
            floor, z = item.split("=", 1)
            depths[floor.strip()] = float(z)
    return depths


def z_for_node(node: dict, depths: Dict[str, float]) -> float:
    if node.get("z_m") is not None:
        return float(node["z_m"])
    floor = node.get("floor")
    if floor in depths:
        return depths[floor]
    if isinstance(floor, str) and "-" in floor:
        parts = [part.strip() for part in floor.split("-") if part.strip() in depths]
        if parts:
            return float(sum(depths[part] for part in parts) / len(parts))
    if isinstance(floor, str) and floor.startswith("B") and floor[1:].isdigit():
        return -4.0 * int(floor[1:])
    return 0.0


def local_xy_from_image(image_xy, scale: float, origin_xy, projection_y_scale: float) -> List[float]:
    x = (float(image_xy[0]) - origin_xy[0]) * scale
    # Flip y so positive local y points upward in a conventional metric view.
    # Seoul Metro evacuation maps are often oblique 3D drawings compressed into
    # a 2D image. projection_y_scale lets us stretch that image-depth axis
    # before distances are calculated.
    y = -(float(image_xy[1]) - origin_xy[1]) * scale * projection_y_scale
    return [x, y]


def edge_distance(a: dict, b: dict) -> tuple[float, float]:
    d2 = float(math.dist(a["local_xy_m"], b["local_xy_m"]))
    d3 = float(math.dist(a["local_xyz_m"], b["local_xyz_m"]))
    return d2, d3


def is_vertical_edge(kind: Optional[str]) -> bool:
    value = (kind or "").lower()
    return any(token in value for token in ("stairs", "elevator", "escalator"))


def same_floor(a: dict, b: dict) -> bool:
    return a.get("floor") == b.get("floor")


def validate_edges(nodes: List[dict], edges: List[dict], long_edge_threshold_m: float) -> List[dict]:
    node_map = {node["id"]: node for node in nodes}
    warnings = []
    for edge in edges:
        a = node_map[edge["from"]]
        b = node_map[edge["to"]]
        kind = edge.get("kind")
        if not same_floor(a, b) and not is_vertical_edge(kind):
            warnings.append({
                "type": "cross_floor_non_vertical_edge",
                "from": edge["from"],
                "to": edge["to"],
                "kind": kind,
                "from_floor": a.get("floor"),
                "to_floor": b.get("floor"),
            })
        if edge["distance_2d_m"] > long_edge_threshold_m:
            warnings.append({
                "type": "long_edge_review",
                "from": edge["from"],
                "to": edge["to"],
                "kind": kind,
                "distance_2d_m": edge["distance_2d_m"],
                "message": "Review whether this edge should be split by bend/landing nodes.",
            })
    return warnings


def build_graph(
    annotation: dict,
    shp_2d_graph: dict,
    floor_depths: Dict[str, float],
    origin_mode: str,
    projection_y_scale: float,
    long_edge_threshold_m: float,
) -> dict:
    entrances = graph_entrance_map(shp_2d_graph)
    matches = matched_control_points(annotation, entrances)
    scale_info = estimate_meters_per_pixel(matches)
    scale = scale_info["meters_per_pixel"]

    if origin_mode == "control_centroid":
        origin_xy = [
            float(np.mean([row["image_xy"][0] for row in matches])),
            float(np.mean([row["image_xy"][1] for row in matches])),
        ]
    else:
        origin_xy = [0.0, 0.0]

    nodes = []
    for node in annotation.get("nodes", []):
        local_xy = local_xy_from_image(node["image_xy"], scale, origin_xy, projection_y_scale)
        z_m = z_for_node(node, floor_depths)
        out = {
            "id": node["id"],
            "kind": node.get("kind"),
            "floor": node.get("floor"),
            "image_xy": node["image_xy"],
            "local_xy_m": local_xy,
            "z_m": z_m,
            "local_xyz_m": [local_xy[0], local_xy[1], z_m],
        }
        for key in ("click_index", "entrance_no", "direction", "accessibility"):
            if key in node:
                out[key] = node[key]
        nodes.append(out)

    node_map = {node["id"]: node for node in nodes}
    edges = []
    for edge in annotation.get("edges", []):
        from_id = edge["from"]
        to_id = edge["to"]
        if from_id not in node_map or to_id not in node_map:
            raise ValueError(f"edge references missing node: {from_id} -> {to_id}")
        d2, d3 = edge_distance(node_map[from_id], node_map[to_id])
        out = {
            "from": from_id,
            "to": to_id,
            "kind": edge.get("kind"),
            "distance_px": float(math.dist(node_map[from_id]["image_xy"], node_map[to_id]["image_xy"])),
            "distance_2d_m": d2,
            "distance_3d_m": d3,
            "cost_m": d3,
        }
        if edge.get("cost_m") is not None:
            out["cost_m"] = float(edge["cost_m"])
            out["cost_source"] = "annotation_override"
        edges.append(out)

    validation_warnings = validate_edges(nodes, edges, long_edge_threshold_m)

    return {
        "station_name": annotation.get("matched_station_name") or annotation.get("station_name") or shp_2d_graph.get("station_name"),
        "graph_type": "local_metric_from_image_annotation",
        "crs": "LOCAL_IMAGE_METRIC",
        "coordinate_policy": {
            "uses_epsg_for_node_coordinates": False,
            "scale_calibrated_from_epsg_entrance_distances": True,
            "origin_mode": origin_mode,
            "origin_image_xy": origin_xy,
            "y_axis": "positive_up_from_image",
            "projection_y_scale": projection_y_scale,
            "projection_note": "Use projection_y_scale > 1 for oblique 3D guide maps where image depth is visually compressed.",
        },
        "scale": scale_info,
        "floor_depths_m": floor_depths,
        "validation": {
            "long_edge_threshold_m": long_edge_threshold_m,
            "warnings": validation_warnings,
        },
        "nodes": nodes,
        "edges": edges,
    }


def write_outputs(graph: dict, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    station_name = graph["station_name"]

    graph_path = output_dir / f"{station_name}_local_metric_graph.json"
    with graph_path.open("w", encoding="utf-8") as f:
        json.dump(graph, f, ensure_ascii=False, indent=2)

    node_gdf = gpd.GeoDataFrame(
        [
            {
                "id": node["id"],
                "kind": node.get("kind"),
                "floor": node.get("floor"),
                "z_m": node["z_m"],
                "geometry": Point(node["local_xyz_m"]),
            }
            for node in graph["nodes"]
        ],
        geometry="geometry",
    )
    node_gdf.to_file(output_dir / f"{station_name}_local_metric_nodes.geojson", driver="GeoJSON")

    node_map = {node["id"]: node for node in graph["nodes"]}
    edge_gdf = gpd.GeoDataFrame(
        [
            {
                "from_id": edge["from"],
                "to_id": edge["to"],
                "kind": edge.get("kind"),
                "distance_2d_m": edge["distance_2d_m"],
                "distance_3d_m": edge["distance_3d_m"],
                "cost_m": edge["cost_m"],
                "geometry": LineString([
                    node_map[edge["from"]]["local_xyz_m"],
                    node_map[edge["to"]]["local_xyz_m"],
                ]),
            }
            for edge in graph["edges"]
        ],
        geometry="geometry",
    )
    edge_gdf.to_file(output_dir / f"{station_name}_local_metric_edges.geojson", driver="GeoJSON")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build local metric indoor graph from image annotation.")
    parser.add_argument("--annotation", required=True)
    parser.add_argument("--shp-2d-graph", required=True, help="Used only to calibrate meters-per-pixel from entrance distances.")
    parser.add_argument("--floor-depths", help='Comma-separated mapping, e.g. "B1=-4,B2=-8"')
    parser.add_argument("--origin-mode", choices=["image_origin", "control_centroid"], default="image_origin")
    parser.add_argument(
        "--projection-y-scale",
        type=float,
        default=1.0,
        help="Stretch image y-axis before distance calculation. Use >1 for oblique 3D guide maps.",
    )
    parser.add_argument("--long-edge-threshold-m", type=float, default=25.0)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    annotation = load_json(Path(args.annotation))
    shp_2d_graph = load_json(Path(args.shp_2d_graph))
    floor_depths = parse_floor_depths(args.floor_depths)
    graph = build_graph(
        annotation,
        shp_2d_graph,
        floor_depths,
        args.origin_mode,
        args.projection_y_scale,
        args.long_edge_threshold_m,
    )
    write_outputs(graph, Path(args.output_dir))

    print(f"[OK] {graph['station_name']}: {len(graph['nodes'])} local nodes, {len(graph['edges'])} local edges")
    print(f"[OK] meters_per_pixel: {graph['scale']['meters_per_pixel']:.6f}, scale_rmse_m: {graph['scale']['rmse_m']:.3f}")
    print(f"[OK] projection_y_scale: {args.projection_y_scale}, validation_warnings: {len(graph['validation']['warnings'])}")


if __name__ == "__main__":
    main()
