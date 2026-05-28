#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Step 1. Build a station-level 2D reference graph from SHP files.

This graph is not the final indoor route graph. It is a georeferenced skeleton
made from station polygons and entrance points:
- station centroid
- major-axis endpoints
- entrance nodes
- entrance projection points on the station major axis
- simple 2D reference edges
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import geopandas as gpd
import numpy as np
from shapely.geometry import LineString, Point, mapping

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_indoor_map_v3 import (  # noqa: E402
    assign_entrances_to_stations,
    build_station_base,
    clean_text,
    ensure_dir,
    normalize_station_name,
)


def major_axis_line(geom) -> Tuple[Point, Point]:
    mr = geom.minimum_rotated_rectangle
    coords = list(mr.exterior.coords)[:-1]
    edges = []
    for i in range(4):
        p1 = np.array(coords[i], dtype=float)
        p2 = np.array(coords[(i + 1) % 4], dtype=float)
        edges.append((float(np.linalg.norm(p2 - p1)), p1, p2))
    _, p1, p2 = max(edges, key=lambda item: item[0])
    return Point(float(p1[0]), float(p1[1])), Point(float(p2[0]), float(p2[1]))


def point_on_line_fraction(line: LineString, point: Point) -> float:
    if line.length == 0:
        return 0.0
    return float(line.project(point) / line.length)


def build_graph_for_station(station_row, entrances_gdf: gpd.GeoDataFrame) -> dict:
    station_name = station_row["station_name"]
    polygon = station_row.geometry
    centroid = polygon.centroid
    axis_start, axis_end = major_axis_line(polygon)
    axis = LineString([axis_start, axis_end])

    station_entrances = entrances_gdf[entrances_gdf["station_name"] == station_name].copy()
    projection_items = []
    nodes: List[dict] = [
        {
            "id": "station_centroid",
            "kind": "station_centroid",
            "map_xy": [float(centroid.x), float(centroid.y)],
        },
        {
            "id": "axis_start",
            "kind": "axis_endpoint",
            "map_xy": [float(axis_start.x), float(axis_start.y)],
        },
        {
            "id": "axis_end",
            "kind": "axis_endpoint",
            "map_xy": [float(axis_end.x), float(axis_end.y)],
        },
    ]
    edges: List[dict] = [
        {
            "from": "axis_start",
            "to": "station_centroid",
            "kind": "axis",
            "distance_m": float(axis_start.distance(centroid)),
        },
        {
            "from": "station_centroid",
            "to": "axis_end",
            "kind": "axis",
            "distance_m": float(centroid.distance(axis_end)),
        },
    ]

    for _, entrance in station_entrances.iterrows():
        entrance_no = str(entrance["entrance_no"])
        entrance_node_id = f"entrance_{entrance_no}"
        entrance_point = entrance.geometry
        projected = axis.interpolate(axis.project(entrance_point))
        projection_node_id = f"axis_projection_entrance_{entrance_no}"
        projection_items.append((point_on_line_fraction(axis, projected), projection_node_id, projected))

        nodes.append({
            "id": entrance_node_id,
            "kind": "entrance",
            "entrance_no": entrance_no,
            "map_xy": [float(entrance_point.x), float(entrance_point.y)],
            "distance_to_station_m": float(entrance.get("distance_to_station_m", 0.0)),
        })
        nodes.append({
            "id": projection_node_id,
            "kind": "axis_projection",
            "entrance_no": entrance_no,
            "map_xy": [float(projected.x), float(projected.y)],
        })
        edges.append({
            "from": entrance_node_id,
            "to": projection_node_id,
            "kind": "entrance_to_axis",
            "distance_m": float(entrance_point.distance(projected)),
        })

    projection_items.sort(key=lambda item: item[0])
    axis_chain = [("axis_start", axis_start)] + [(item[1], item[2]) for item in projection_items] + [("axis_end", axis_end)]
    for (from_id, from_pt), (to_id, to_pt) in zip(axis_chain, axis_chain[1:]):
        if from_id == to_id:
            continue
        edges.append({
            "from": from_id,
            "to": to_id,
            "kind": "axis_chain",
            "distance_m": float(from_pt.distance(to_pt)),
        })

    return {
        "station_name": station_name,
        "crs": "EPSG:5179",
        "station_polygon_geojson": mapping(polygon),
        "nodes": nodes,
        "edges": edges,
    }


def write_graph_outputs(graph: dict, output_dir: Path) -> None:
    station_name = graph["station_name"]
    ensure_dir(output_dir)
    with (output_dir / f"{station_name}_shp_2d_graph.json").open("w", encoding="utf-8") as f:
        json.dump(graph, f, ensure_ascii=False, indent=2)

    node_gdf = gpd.GeoDataFrame(
        [
            {
                "id": node["id"],
                "kind": node["kind"],
                "entrance_no": node.get("entrance_no"),
                "geometry": Point(*node["map_xy"]),
            }
            for node in graph["nodes"]
        ],
        geometry="geometry",
        crs=graph["crs"],
    )
    node_gdf.to_file(output_dir / f"{station_name}_shp_2d_nodes.geojson", driver="GeoJSON")

    node_map = {node["id"]: node for node in graph["nodes"]}
    edge_gdf = gpd.GeoDataFrame(
        [
            {
                "from_id": edge["from"],
                "to_id": edge["to"],
                "kind": edge["kind"],
                "distance_m": edge["distance_m"],
                "geometry": LineString([node_map[edge["from"]]["map_xy"], node_map[edge["to"]]["map_xy"]]),
            }
            for edge in graph["edges"]
        ],
        geometry="geometry",
        crs=graph["crs"],
    )
    edge_gdf.to_file(output_dir / f"{station_name}_shp_2d_edges.geojson", driver="GeoJSON")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build 2D reference graph from station and entrance SHP files.")
    parser.add_argument("--station-shp", required=True)
    parser.add_argument("--entrance-shp", required=True)
    parser.add_argument("--architecture-csv")
    parser.add_argument("--depth-csv")
    parser.add_argument("--area-csv")
    parser.add_argument("--guide-root")
    parser.add_argument("--station-name")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--crs", default="EPSG:5179")
    parser.add_argument("--nearest-max-distance-m", type=float, default=120.0)
    args = parser.parse_args()

    stations, entrances, _ = build_station_base(
        station_shp=args.station_shp,
        entrance_shp=args.entrance_shp,
        architecture_csv=args.architecture_csv,
        depth_csv=args.depth_csv,
        area_csv=args.area_csv,
        guide_root=args.guide_root,
        crs=args.crs,
        max_dist=args.nearest_max_distance_m,
    )

    if args.station_name:
        target_name = normalize_station_name(args.station_name)
        stations = stations[stations["station_name"] == target_name]
        if stations.empty:
            raise ValueError(f"역을 찾을 수 없음: {target_name}")

    output_dir = Path(args.output_dir)
    for _, station_row in stations.iterrows():
        graph = build_graph_for_station(station_row, entrances)
        write_graph_outputs(graph, output_dir)
        print(f"[OK] {graph['station_name']}: {len(graph['nodes'])} nodes, {len(graph['edges'])} edges")


if __name__ == "__main__":
    main()
