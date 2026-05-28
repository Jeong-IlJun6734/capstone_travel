
#!/usr/bin/env python3
"""
Build a station-level indoor map base from:
1) station polygon SHP
2) entrance point SHP
3) optional station metadata CSV/XLSX
4) optional guide-map image annotations JSON

What this script does
---------------------
Step 1. Integrate GIS + station metadata
- Reads station polygons and entrance points
- Fixes common DBF/Korean encoding issues when possible
- Assigns each entrance to the nearest station polygon
- Computes station geometry metrics:
  * centroid
  * area
  * major/minor axis length from oriented minimum bounding rectangle
  * station major-axis angle
- Merges optional station metadata:
  * station length
  * platform length
  * depth
  * floor count
  * area
- Writes per-station base information JSON / GeoJSON

Step 2. Map a guide image to real-world coordinates
- Requires a manual annotation JSON for one station:
  * control_points: image exit-number points matched to real entrances
  * nodes: indoor nodes in image pixel coordinates
  * edges: graph connectivity
- Estimates an affine transform from image pixels -> projected map coordinates
- Transforms indoor nodes into projected coordinates
- Writes an indoor graph JSON / GeoJSON

Important
---------
This does NOT automatically recover full indoor geometry from the guide map.
It gives you a practical workflow:
- GIS gives outer shape, direction, exits, metric scale hints
- guide map gives indoor topology and facility placement
- manual control points align the guide map to the real world

Dependencies
------------
pip install geopandas shapely pyproj pandas openpyxl opencv-python numpy

Example
-------
python build_indoor_map.py \
  --station-shp Total.JUSUBG.20260401.TL_SPRL_STATN.11000.shp \
  --entrance-shp Total.JUSUBG.20260401.TL_SPSB_ENTRC.11000.shp \
  --metadata station_meta.csv \
  --station-name "신설동역" \
  --guide-annotations sinsel_annotations.json \
  --output-dir output

Guide annotation JSON example
-----------------------------
{
  "station_name": "신설동역",
  "image_width": 2480,
  "image_height": 3508,
  "control_points": [
    {"entrance_no": "1", "image_xy": [2100, 520]},
    {"entrance_no": "3", "image_xy": [1700, 430]},
    {"entrance_no": "6", "image_xy": [900, 610]}
  ],
  "nodes": [
    {"id": "hall_b1_center", "kind": "hall", "floor": "B1", "image_xy": [1450, 1200]},
    {"id": "exit_1", "kind": "exit", "floor": "B1", "image_xy": [2100, 520]},
    {"id": "stairs_a", "kind": "stairs", "floor": "B1", "image_xy": [1300, 1100]}
  ],
  "edges": [
    {"from": "hall_b1_center", "to": "exit_1"},
    {"from": "hall_b1_center", "to": "stairs_a"}
  ]
}
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import geopandas as gpd
import numpy as np
import pandas as pd
from shapely.geometry import LineString, Point, Polygon, mapping

try:
    import cv2
except Exception:
    cv2 = None


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def clean_text(value):
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None

    # Common mojibake repair path for Korean DBF fields read with latin-1/cp1252-like decoding.
    # If repair fails, return original.
    for src in ("cp949", "euc-kr"):
        try:
            repaired = s.encode("latin1", errors="strict").decode(src, errors="strict")
            # basic sanity check: if Hangul appears, keep repaired
            if any("\uac00" <= ch <= "\ud7a3" for ch in repaired):
                return repaired
        except Exception:
            pass
    return s


def load_gdf(path: str, force_crs: Optional[str] = None) -> gpd.GeoDataFrame:
    gdf = gpd.read_file(path)
    if force_crs:
        if gdf.crs is None:
            gdf = gdf.set_crs(force_crs)
        else:
            gdf = gdf.to_crs(force_crs)
    return gdf


def normalize_station_name(name: Optional[str]) -> Optional[str]:
    if name is None:
        return None
    s = clean_text(name)
    if s is None:
        return None
    s = s.replace(" ", "")
    if not s.endswith("역"):
        s += "역"
    return s


def oriented_metrics(poly: Polygon) -> Dict[str, float]:
    """
    Compute major/minor axis lengths and angle from minimum rotated rectangle.
    """
    mr = poly.minimum_rotated_rectangle
    coords = list(mr.exterior.coords)[:-1]
    if len(coords) != 4:
        return {
            "major_axis_m": float("nan"),
            "minor_axis_m": float("nan"),
            "major_axis_angle_deg": float("nan"),
        }

    edges = []
    for i in range(4):
        p1 = np.array(coords[i], dtype=float)
        p2 = np.array(coords[(i + 1) % 4], dtype=float)
        vec = p2 - p1
        length = float(np.linalg.norm(vec))
        edges.append((length, vec, p1, p2))

    edges = sorted(edges, key=lambda x: x[0], reverse=True)
    major_len, major_vec, _, _ = edges[0]
    minor_len = edges[-1][0]

    angle = math.degrees(math.atan2(major_vec[1], major_vec[0]))
    return {
        "major_axis_m": major_len,
        "minor_axis_m": minor_len,
        "major_axis_angle_deg": angle,
    }


def assign_entrances_to_stations(
    stations: gpd.GeoDataFrame,
    entrances: gpd.GeoDataFrame,
    nearest_max_distance_m: Optional[float] = None,
) -> gpd.GeoDataFrame:
    """
    Assign each entrance point to nearest station polygon.
    Works even if entrance is not strictly inside polygon.
    """
    stations = stations.copy()
    entrances = entrances.copy()

    if stations.crs is None or entrances.crs is None:
        raise ValueError("CRS is missing. Pass --crs, e.g. EPSG:5179.")

    if stations.crs != entrances.crs:
        entrances = entrances.to_crs(stations.crs)

    stations["station_name"] = stations["KOR_STA_NM"].apply(normalize_station_name)
    entrances["entrance_no"] = entrances["ENTRC_NO"].apply(lambda x: clean_text(x))

    # Use centroids for nearest join against polygons.
    station_cent = stations[["station_name", "geometry"]].copy()
    station_cent["geometry"] = station_cent.geometry.centroid

    joined = gpd.sjoin_nearest(
        entrances,
        station_cent,
        how="left",
        distance_col="distance_to_station_m",
    )

    if nearest_max_distance_m is not None:
        joined = joined[joined["distance_to_station_m"] <= nearest_max_distance_m].copy()

    return joined


def read_metadata(path: str) -> pd.DataFrame:
    path = str(path)
    if path.lower().endswith(".csv"):
        # Try common encodings for Korean CSV
        for enc in ("utf-8-sig", "cp949", "euc-kr"):
            try:
                df = pd.read_csv(path, encoding=enc)
                return df
            except Exception:
                continue
        raise ValueError(f"Could not read CSV with common encodings: {path}")

    if path.lower().endswith((".xlsx", ".xls")):
        return pd.read_excel(path)

    raise ValueError("metadata must be .csv, .xlsx, or .xls")


def standardize_metadata_columns(df: pd.DataFrame) -> pd.DataFrame:
    """
    Expected minimal columns (you can rename from your own source):
    - station_name
    Optional:
    - station_length_m
    - platform_length_m
    - depth_m
    - floor_count
    - area_m2
    """
    df = df.copy()
    renamed = {}
    for col in df.columns:
        c = str(col).strip()
        if c in ("역명", "역이름", "정거장명", "station_name"):
            renamed[col] = "station_name"
        elif c in ("역사길이", "길이", "station_length_m"):
            renamed[col] = "station_length_m"
        elif c in ("승강장길이", "platform_length_m"):
            renamed[col] = "platform_length_m"
        elif c in ("심도", "depth_m"):
            renamed[col] = "depth_m"
        elif c in ("층수", "floor_count"):
            renamed[col] = "floor_count"
        elif c in ("면적", "area_m2"):
            renamed[col] = "area_m2"

    df = df.rename(columns=renamed)
    if "station_name" not in df.columns:
        raise ValueError("metadata needs a station_name-like column (e.g. 역명).")

    df["station_name"] = df["station_name"].apply(normalize_station_name)
    return df


def build_station_base(
    station_shp: str,
    entrance_shp: str,
    metadata_path: Optional[str] = None,
    crs: Optional[str] = "EPSG:5179",
    nearest_max_distance_m: Optional[float] = None,
) -> Tuple[gpd.GeoDataFrame, gpd.GeoDataFrame]:
    stations = load_gdf(station_shp, force_crs=crs)
    entrances = load_gdf(entrance_shp, force_crs=crs)

    print("station columns:", list(stations.columns))
    print(stations.head())
    print("entrance columns:", list(entrances.columns))
    print(entrances.head())

    stations["KOR_STA_NM"] = stations["KOR_STA_NM"].apply(clean_text)
    stations["station_name"] = stations["KOR_STA_NM"].apply(normalize_station_name)

    # basic geometry stats
    stations["centroid_x"] = stations.geometry.centroid.x
    stations["centroid_y"] = stations.geometry.centroid.y
    stations["area_geom_m2"] = stations.geometry.area

    metrics = stations.geometry.apply(oriented_metrics)
    stations["major_axis_m"] = metrics.apply(lambda d: d["major_axis_m"])
    stations["minor_axis_m"] = metrics.apply(lambda d: d["minor_axis_m"])
    stations["major_axis_angle_deg"] = metrics.apply(lambda d: d["major_axis_angle_deg"])

    if metadata_path:
        meta = read_metadata(metadata_path)
        meta = standardize_metadata_columns(meta)
        stations = stations.merge(meta, on="station_name", how="left")

    # entrance mapping
    entrances_joined = assign_entrances_to_stations(
        stations=stations,
        entrances=entrances,
        nearest_max_distance_m=nearest_max_distance_m,
    )

    return stations, entrances_joined


def station_summary_dict(stations: gpd.GeoDataFrame, entrances_joined: gpd.GeoDataFrame) -> Dict[str, dict]:
    result = {}

    for _, row in stations.iterrows():
        name = row["station_name"]
        station_entrances = entrances_joined[entrances_joined["station_name"] == name].copy()

        entrance_list = []
        for _, er in station_entrances.iterrows():
            pt = er.geometry
            entrance_list.append({
                "entrance_no": clean_text(er.get("ENTRC_NO")),
                "sub_ent_sn": int(er.get("SUB_ENT_SN")) if pd.notna(er.get("SUB_ENT_SN")) else None,
                "x": float(pt.x),
                "y": float(pt.y),
                "distance_to_station_m": float(er.get("distance_to_station_m", np.nan)),
            })

        d = {
            "station_name": name,
            "station_sn": int(row["RLR_STA_SN"]) if pd.notna(row["RLR_STA_SN"]) else None,
            "sig_cd": clean_text(row["SIG_CD"]),
            "centroid": [float(row["centroid_x"]), float(row["centroid_y"])],
            "area_geom_m2": float(row["area_geom_m2"]),
            "major_axis_m": float(row["major_axis_m"]),
            "minor_axis_m": float(row["minor_axis_m"]),
            "major_axis_angle_deg": float(row["major_axis_angle_deg"]),
            "station_length_m": float(row["station_length_m"]) if "station_length_m" in row and pd.notna(row["station_length_m"]) else None,
            "platform_length_m": float(row["platform_length_m"]) if "platform_length_m" in row and pd.notna(row["platform_length_m"]) else None,
            "depth_m": float(row["depth_m"]) if "depth_m" in row and pd.notna(row["depth_m"]) else None,
            "floor_count": int(row["floor_count"]) if "floor_count" in row and pd.notna(row["floor_count"]) else None,
            "area_m2": float(row["area_m2"]) if "area_m2" in row and pd.notna(row["area_m2"]) else None,
            "entrances": sorted(
                entrance_list,
                key=lambda x: (
                    float("inf") if x["entrance_no"] is None else float(str(x["entrance_no"]).replace("-", "").replace("_", "") if str(x["entrance_no"]).replace("-", "").replace("_", "").isdigit() else 1e9),
                    str(x["entrance_no"]),
                )
            ),
            "station_polygon_geojson": mapping(row.geometry),
        }
        result[name] = d

    return result


# ---------------------------------------------------------------------
# Guide map alignment
# ---------------------------------------------------------------------

def estimate_affine_from_control_points(
    control_points: List[dict],
    station_entrances: List[dict],
) -> np.ndarray:
    """
    Build affine transform: image pixel -> projected CRS coordinates.
    Requires at least 3 matched exits.
    """
    if cv2 is None:
        raise RuntimeError("opencv-python is required for image alignment.")

    ent_map = {str(e["entrance_no"]): e for e in station_entrances if e["entrance_no"] is not None}

    src = []
    dst = []
    missing = []

    for cp in control_points:
        eno = str(cp["entrance_no"])
        if eno not in ent_map:
            missing.append(eno)
            continue
        src.append(cp["image_xy"])
        dst.append([ent_map[eno]["x"], ent_map[eno]["y"]])

    if missing:
        raise ValueError(f"Control-point entrance numbers not found in mapped station entrances: {missing}")

    if len(src) < 3:
        raise ValueError("At least 3 matched control points are required for affine transform.")

    src = np.array(src, dtype=np.float32)
    dst = np.array(dst, dtype=np.float32)

    M, inliers = cv2.estimateAffinePartial2D(src, dst, method=cv2.LMEDS)
    if M is None:
        raise RuntimeError("Could not estimate affine transform.")
    return M


def apply_affine(M: np.ndarray, x: float, y: float) -> Tuple[float, float]:
    pt = np.array([x, y, 1.0], dtype=float)
    out = M @ pt
    return float(out[0]), float(out[1])


def build_indoor_graph_for_station(
    station_base: dict,
    guide_annotation_path: str,
    output_dir: Path,
) -> dict:
    with open(guide_annotation_path, "r", encoding="utf-8") as f:
        ann = json.load(f)

    station_name = normalize_station_name(ann.get("station_name"))
    if station_name != station_base["station_name"]:
        raise ValueError(
            f"Annotation station ({station_name}) and station base ({station_base['station_name']}) do not match."
        )

    M = estimate_affine_from_control_points(
        control_points=ann["control_points"],
        station_entrances=station_base["entrances"],
    )

    nodes_out = []
    node_index = {}
    for node in ann.get("nodes", []):
        ix, iy = node["image_xy"]
        x, y = apply_affine(M, ix, iy)
        out = {
            "id": node["id"],
            "kind": node.get("kind"),
            "floor": node.get("floor"),
            "image_xy": [float(ix), float(iy)],
            "map_xy": [x, y],
        }
        nodes_out.append(out)
        node_index[out["id"]] = out

    edges_out = []
    for edge in ann.get("edges", []):
        u = edge["from"]
        v = edge["to"]
        if u not in node_index or v not in node_index:
            raise ValueError(f"Edge references unknown node: {u} -> {v}")
        ux, uy = node_index[u]["map_xy"]
        vx, vy = node_index[v]["map_xy"]
        dist = math.dist((ux, uy), (vx, vy))
        edges_out.append({
            "from": u,
            "to": v,
            "distance_m": dist,
        })

    result = {
        "station_name": station_name,
        "transform_image_to_map": M.tolist(),
        "nodes": nodes_out,
        "edges": edges_out,
        "control_points": ann["control_points"],
    }

    ensure_dir(output_dir)
    out_json = output_dir / f"{station_name}_indoor_graph.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    # Also save nodes/edges as GeoJSON
    node_gdf = gpd.GeoDataFrame(
        [
            {
                "id": n["id"],
                "kind": n.get("kind"),
                "floor": n.get("floor"),
                "geometry": Point(n["map_xy"][0], n["map_xy"][1]),
            }
            for n in nodes_out
        ],
        crs="EPSG:5179",  # override if you used another target CRS
    )
    edge_gdf = gpd.GeoDataFrame(
        [
            {
                "from_id": e["from"],
                "to_id": e["to"],
                "distance_m": e["distance_m"],
                "geometry": LineString([
                    tuple(node_index[e["from"]]["map_xy"]),
                    tuple(node_index[e["to"]]["map_xy"]),
                ]),
            }
            for e in edges_out
        ],
        crs="EPSG:5179",
    )

    node_gdf.to_file(output_dir / f"{station_name}_indoor_nodes.geojson", driver="GeoJSON")
    edge_gdf.to_file(output_dir / f"{station_name}_indoor_edges.geojson", driver="GeoJSON")

    return result


# ---------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Build a station indoor map base from SHP + metadata + guide map.")
    parser.add_argument("--station-shp", required=True, help="Station polygon SHP path")
    parser.add_argument("--entrance-shp", required=True, help="Entrance point SHP path")
    parser.add_argument("--metadata", required=False, help="Optional metadata CSV/XLSX path")
    parser.add_argument("--station-name", required=False, help="Target station name, e.g. 신설동역")
    parser.add_argument("--guide-annotations", required=False, help="Guide annotation JSON for the target station")
    parser.add_argument("--output-dir", required=True, help="Output directory")
    parser.add_argument("--crs", default="EPSG:5179", help="Target CRS, default EPSG:5179")
    parser.add_argument("--nearest-max-distance-m", type=float, default=120.0, help="Max distance to assign entrance -> station")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    ensure_dir(out_dir)

    stations, entrances_joined = build_station_base(
        station_shp=args.station_shp,
        entrance_shp=args.entrance_shp,
        metadata_path=args.metadata,
        crs=args.crs,
        nearest_max_distance_m=args.nearest_max_distance_m,
    )

    # Save raw merged layers
    stations.to_file(out_dir / "stations_merged.geojson", driver="GeoJSON")
    entrances_joined.to_file(out_dir / "entrances_mapped.geojson", driver="GeoJSON")

    base = station_summary_dict(stations, entrances_joined)

    with open(out_dir / "station_base_summary.json", "w", encoding="utf-8") as f:
        json.dump(base, f, ensure_ascii=False, indent=2)

    print(f"[OK] Wrote station base summary for {len(base)} stations.")

    if args.station_name:
        station_name = normalize_station_name(args.station_name)
        if station_name not in base:
            raise ValueError(f"Station not found in base summary: {station_name}")

        with open(out_dir / f"{station_name}_base.json", "w", encoding="utf-8") as f:
            json.dump(base[station_name], f, ensure_ascii=False, indent=2)
        print(f"[OK] Wrote base info for station: {station_name}")

        if args.guide_annotations:
            graph = build_indoor_graph_for_station(
                station_base=base[station_name],
                guide_annotation_path=args.guide_annotations,
                output_dir=out_dir,
            )
            print(f"[OK] Built indoor graph for {station_name}: "
                  f"{len(graph['nodes'])} nodes, {len(graph['edges'])} edges")

    print(f"[DONE] Output directory: {out_dir.resolve()}")


if __name__ == "__main__":
    main()
