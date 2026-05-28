#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
서울교통공사 실내 지도 기초 데이터 생성 스크립트

기능
1) 역사 polygon SHP + 출입구 point SHP + 서울교통공사 CSV 3종 통합
2) 역이용안내도 이미지 파일 자동 탐색
3) 특정 역의 안내도 annotation JSON이 있으면 이미지 -> 실좌표 정합 후 실내 그래프 생성
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import geopandas as gpd
import numpy as np
import pandas as pd
from shapely.geometry import LineString, Point, mapping

try:
    import cv2
except Exception:
    cv2 = None


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def clean_text(value):
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    for src in ("cp949", "euc-kr"):
        try:
            repaired = s.encode("latin1", errors="strict").decode(src, errors="strict")
            if any("\uac00" <= ch <= "\ud7a3" for ch in repaired):
                return repaired
        except Exception:
            pass
    return s


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


def read_csv_korean(path: str) -> pd.DataFrame:
    for enc in ("utf-8-sig", "cp949", "euc-kr"):
        try:
            return pd.read_csv(path, encoding=enc)
        except Exception:
            pass
    raise ValueError(f"CSV 읽기 실패: {path}")


def load_gdf(path: str, force_crs: Optional[str] = None) -> gpd.GeoDataFrame:
    gdf = gpd.read_file(path)
    if force_crs:
        if gdf.crs is None:
            gdf = gdf.set_crs(force_crs)
        else:
            gdf = gdf.to_crs(force_crs)
    return gdf


def oriented_metrics(geom) -> Dict[str, float]:
    mr = geom.minimum_rotated_rectangle
    coords = list(mr.exterior.coords)[:-1]
    edges = []
    for i in range(4):
        p1 = np.array(coords[i], dtype=float)
        p2 = np.array(coords[(i + 1) % 4], dtype=float)
        vec = p2 - p1
        length = float(np.linalg.norm(vec))
        edges.append((length, vec))
    edges.sort(key=lambda x: x[0], reverse=True)
    major_len, major_vec = edges[0]
    minor_len = edges[-1][0]
    angle = math.degrees(math.atan2(major_vec[1], major_vec[0]))
    return {
        "major_axis_m": major_len,
        "minor_axis_m": minor_len,
        "major_axis_angle_deg": angle,
    }


def load_official_metadata(
    architecture_csv: Optional[str],
    depth_csv: Optional[str],
    area_csv: Optional[str],
) -> pd.DataFrame:
    dfs = []

    if architecture_csv:
        df = read_csv_korean(architecture_csv).copy()
        df["station_name"] = df["역명"].apply(normalize_station_name)
        df = df.rename(columns={
            "호선": "line_no",
            "승강장유형": "platform_type",
            "길이": "station_length_m",
            "층수": "floor_text",
            "면적": "station_area_m2",
        })
        dfs.append(df[["station_name", "line_no", "platform_type", "station_length_m", "floor_text", "station_area_m2"]])

    if depth_csv:
        df = read_csv_korean(depth_csv).copy()
        df["station_name"] = df["역명"].apply(normalize_station_name)
        df = df.rename(columns={
            "호선": "depth_line_no",
            "층수": "depth_floor_text",
            "형식": "depth_platform_type",
            "선로기준정거장깊이": "depth_track_ref_m",
            "정거장깊이": "depth_station_ref_m",
        })
        dfs.append(df[["station_name", "depth_line_no", "depth_floor_text", "depth_platform_type", "depth_track_ref_m", "depth_station_ref_m"]])

    if area_csv:
        df = read_csv_korean(area_csv).copy()
        df["station_name"] = df["역명"].apply(normalize_station_name)
        df = df.rename(columns={
            "호선": "area_line_no",
            "대합실면적": "hall_area_m2",
            "승강장면적": "platform_area_m2",
        })
        dfs.append(df[["station_name", "area_line_no", "hall_area_m2", "platform_area_m2"]])

    if not dfs:
        return pd.DataFrame(columns=["station_name"])

    meta = dfs[0]
    for df in dfs[1:]:
        meta = meta.merge(df, on="station_name", how="outer")

    agg = {c: "first" for c in meta.columns if c != "station_name"}
    return meta.groupby("station_name", as_index=False).agg(agg)


def assign_entrances_to_stations(stations: gpd.GeoDataFrame, entrances: gpd.GeoDataFrame, max_dist: float = 120.0):
    stations = stations.copy()
    entrances = entrances.copy()

    stations["station_name"] = stations["KOR_SUB_NM"].apply(normalize_station_name)
    entrances["entrance_no"] = entrances["ENTRC_NO"].apply(lambda x: clean_text(x))

    joined = gpd.sjoin_nearest(
        entrances,
        stations[["station_name", "geometry"]],
        how="left",
        distance_col="distance_to_station_m",
    )
    joined = joined[joined["distance_to_station_m"] <= max_dist].copy()

    # Some entrance SHP rows are duplicated exactly. Keep one copy so later
    # entrance-number based control point matching is not ambiguous.
    joined["_geometry_wkb"] = joined.geometry.to_wkb()
    joined = joined.drop_duplicates(subset=["station_name", "entrance_no", "_geometry_wkb"])
    return joined.drop(columns=["_geometry_wkb"])


def _extract_line_no_from_path(path: Path) -> Optional[str]:
    for part in path.parts:
        s = str(part)
        if s.endswith("호선"):
            num = s.replace("호선", "").strip()
            if num.isdigit():
                return num
    return None


def find_guide_images(root_dir: Optional[str]) -> Dict[str, List[dict]]:
    if not root_dir:
        return {}
    root = Path(root_dir)
    if not root.exists():
        return {}

    mapping_dict: Dict[str, List[dict]] = {}
    for ext in ("*.jpg", "*.jpeg", "*.png", "*.webp"):
        for p in root.rglob(ext):
            station_name = normalize_station_name(p.stem)
            line_no = _extract_line_no_from_path(p)
            mapping_dict.setdefault(station_name, []).append({
                "line_no": line_no,
                "path": str(p),
            })
    return mapping_dict


def select_guide_image_for_station(station_name: str, station_row, guide_map: Dict[str, List[dict]]) -> Optional[dict]:
    candidates = guide_map.get(station_name, [])
    if not candidates:
        return None

    station_line = None
    if "line_no" in station_row and pd.notna(station_row["line_no"]):
        station_line = str(station_row["line_no"]).strip()

    if station_line:
        for c in candidates:
            if c.get("line_no") == station_line:
                return c
    return candidates[0]


def build_station_base(
    station_shp: str,
    entrance_shp: str,
    architecture_csv: Optional[str],
    depth_csv: Optional[str],
    area_csv: Optional[str],
    guide_root: Optional[str],
    crs: str = "EPSG:5179",
    max_dist: float = 120.0,
) -> Tuple[gpd.GeoDataFrame, gpd.GeoDataFrame, Dict[str, List[dict]]]:
    stations = load_gdf(station_shp, force_crs=crs)
    entrances = load_gdf(entrance_shp, force_crs=crs)

    stations["KOR_SUB_NM"] = stations["KOR_SUB_NM"].apply(clean_text)
    stations["station_name"] = stations["KOR_SUB_NM"].apply(normalize_station_name)

    stations["centroid_x"] = stations.geometry.centroid.x
    stations["centroid_y"] = stations.geometry.centroid.y
    stations["geometry_area_m2"] = stations.geometry.area

    metrics = stations.geometry.apply(oriented_metrics)
    stations["major_axis_m"] = metrics.apply(lambda d: d["major_axis_m"])
    stations["minor_axis_m"] = metrics.apply(lambda d: d["minor_axis_m"])
    stations["major_axis_angle_deg"] = metrics.apply(lambda d: d["major_axis_angle_deg"])

    meta = load_official_metadata(architecture_csv, depth_csv, area_csv)
    if len(meta) > 0:
        stations = stations.merge(meta, on="station_name", how="left")

    entrances_joined = assign_entrances_to_stations(stations, entrances, max_dist=max_dist)
    guide_map = find_guide_images(guide_root)
    return stations, entrances_joined, guide_map


def station_summary_dict(stations: gpd.GeoDataFrame, entrances_joined: gpd.GeoDataFrame, guide_map: Dict[str, List[dict]]):
    result = {}
    for _, row in stations.iterrows():
        name = row["station_name"]
        station_entrances = entrances_joined[entrances_joined["station_name"] == name].copy()

        entrance_list = []
        for _, er in station_entrances.iterrows():
            pt = er.geometry
            entrance_list.append({
                "entrance_no": clean_text(er.get("ENTRC_NO")),
                "station_sn": int(row["SUB_STA_SN"]) if pd.notna(row["SUB_STA_SN"]) else None,
                "x": float(pt.x),
                "y": float(pt.y),
                "distance_to_station_m": float(er.get("distance_to_station_m", np.nan)),
            })

        result[name] = {
            "station_name": name,
            "station_sn": int(row["SUB_STA_SN"]) if pd.notna(row["SUB_STA_SN"]) else None,
            "sig_cd": clean_text(row["SIG_CD"]),
            "centroid": [float(row["centroid_x"]), float(row["centroid_y"])],
            "geometry_area_m2": float(row["geometry_area_m2"]),
            "major_axis_m": float(row["major_axis_m"]),
            "minor_axis_m": float(row["minor_axis_m"]),
            "major_axis_angle_deg": float(row["major_axis_angle_deg"]),
            "line_no": clean_text(row.get("line_no")),
            "station_length_m": float(row["station_length_m"]) if pd.notna(row.get("station_length_m", np.nan)) else None,
            "platform_type": clean_text(row.get("platform_type")),
            "floor_text": clean_text(row.get("floor_text")),
            "station_area_m2": float(row["station_area_m2"]) if pd.notna(row.get("station_area_m2", np.nan)) else None,
            "depth_track_ref_m": float(row["depth_track_ref_m"]) if pd.notna(row.get("depth_track_ref_m", np.nan)) else None,
            "depth_station_ref_m": float(row["depth_station_ref_m"]) if pd.notna(row.get("depth_station_ref_m", np.nan)) else None,
            "hall_area_m2": float(row["hall_area_m2"]) if pd.notna(row.get("hall_area_m2", np.nan)) else None,
            "platform_area_m2": float(row["platform_area_m2"]) if pd.notna(row.get("platform_area_m2", np.nan)) else None,
            "guide_image": select_guide_image_for_station(name, row, guide_map),
            "guide_image_candidates": guide_map.get(name, []),
            "entrances": sorted(entrance_list, key=lambda x: str(x["entrance_no"]) if x["entrance_no"] is not None else ""),
            "station_polygon_geojson": mapping(row.geometry),
        }
    return result


def estimate_affine(control_points: List[dict], station_entrances: List[dict]) -> np.ndarray:
    if cv2 is None:
        raise RuntimeError("opencv-python 필요")

    ent_map = {str(e["entrance_no"]): e for e in station_entrances if e["entrance_no"] is not None}
    src, dst = [], []

    for cp in control_points:
        eno = str(cp["entrance_no"])
        if eno not in ent_map:
            raise ValueError(f"출구 번호를 찾지 못함: {eno}")
        src.append(cp["image_xy"])
        dst.append([ent_map[eno]["x"], ent_map[eno]["y"]])

    if len(src) < 3:
        raise ValueError("Affine 정합에는 최소 3개의 출구 대응점이 필요")

    src = np.array(src, dtype=np.float32)
    dst = np.array(dst, dtype=np.float32)
    M, _ = cv2.estimateAffinePartial2D(src, dst, method=cv2.LMEDS)
    if M is None:
        raise RuntimeError("Affine 추정 실패")
    return M


def apply_affine(M: np.ndarray, x: float, y: float):
    pt = np.array([x, y, 1.0], dtype=float)
    out = M @ pt
    return float(out[0]), float(out[1])


def build_indoor_graph(station_base: dict, annotation_json: str, output_dir: Path):
    with open(annotation_json, "r", encoding="utf-8") as f:
        ann = json.load(f)

    station_name = normalize_station_name(ann["station_name"])
    if station_name != station_base["station_name"]:
        raise ValueError("annotation station_name과 station_base station_name이 다름")

    M = estimate_affine(ann["control_points"], station_base["entrances"])

    nodes = []
    node_map = {}
    for n in ann["nodes"]:
        ix, iy = n["image_xy"]
        x, y = apply_affine(M, ix, iy)
        node = {
            "id": n["id"],
            "kind": n.get("kind"),
            "floor": n.get("floor"),
            "image_xy": [float(ix), float(iy)],
            "map_xy": [x, y],
        }
        nodes.append(node)
        node_map[node["id"]] = node

    edges = []
    for e in ann["edges"]:
        u, v = e["from"], e["to"]
        ux, uy = node_map[u]["map_xy"]
        vx, vy = node_map[v]["map_xy"]
        edges.append({
            "from": u,
            "to": v,
            "distance_m": float(math.dist((ux, uy), (vx, vy))),
        })

    out = {
        "station_name": station_name,
        "transform_image_to_map": M.tolist(),
        "nodes": nodes,
        "edges": edges,
        "control_points": ann["control_points"],
    }

    ensure_dir(output_dir)
    with open(output_dir / f"{station_name}_indoor_graph.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    node_records = [
        {"id": n["id"], "kind": n["kind"], "floor": n["floor"], "geometry": Point(*n["map_xy"])}
        for n in nodes
    ]
    node_gdf = gpd.GeoDataFrame(
        node_records,
        columns=["id", "kind", "floor", "geometry"],
        geometry="geometry",
        crs="EPSG:5179",
    )

    edge_records = [
        {
            "from_id": e["from"],
            "to_id": e["to"],
            "distance_m": e["distance_m"],
            "geometry": LineString([tuple(node_map[e["from"]]["map_xy"]), tuple(node_map[e["to"]]["map_xy"])]),
        }
        for e in edges
    ]
    edge_gdf = gpd.GeoDataFrame(
        edge_records,
        columns=["from_id", "to_id", "distance_m", "geometry"],
        geometry="geometry",
        crs="EPSG:5179",
    )

    node_gdf.to_file(output_dir / f"{station_name}_indoor_nodes.geojson", driver="GeoJSON")
    edge_gdf.to_file(output_dir / f"{station_name}_indoor_edges.geojson", driver="GeoJSON")


def main():
    parser = argparse.ArgumentParser(description="Build a station indoor map base from SHP + official CSV metadata + guide map.")
    parser.add_argument("--station-shp", required=True)
    parser.add_argument("--entrance-shp", required=True)
    parser.add_argument("--architecture-csv")
    parser.add_argument("--depth-csv")
    parser.add_argument("--area-csv")
    parser.add_argument("--guide-root")
    parser.add_argument("--station-name")
    parser.add_argument("--guide-annotations")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--crs", default="EPSG:5179")
    parser.add_argument("--nearest-max-distance-m", type=float, default=120.0)
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    ensure_dir(out_dir)

    stations, entrances_joined, guide_map = build_station_base(
        station_shp=args.station_shp,
        entrance_shp=args.entrance_shp,
        architecture_csv=args.architecture_csv,
        depth_csv=args.depth_csv,
        area_csv=args.area_csv,
        guide_root=args.guide_root,
        crs=args.crs,
        max_dist=args.nearest_max_distance_m,
    )

    stations.to_file(out_dir / "stations_merged.geojson", driver="GeoJSON")
    entrances_joined.to_file(out_dir / "entrances_mapped.geojson", driver="GeoJSON")

    summary = station_summary_dict(stations, entrances_joined, guide_map)
    with open(out_dir / "station_base_summary.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print(f"[OK] 역사 기본정보 생성: {len(summary)}개 역")

    if args.station_name:
        name = normalize_station_name(args.station_name)
        if name not in summary:
            raise ValueError(f"역을 찾을 수 없음: {name}")
        with open(out_dir / f"{name}_base.json", "w", encoding="utf-8") as f:
            json.dump(summary[name], f, ensure_ascii=False, indent=2)
        print(f"[OK] 단일 역 기본정보 저장: {name}")

        if args.guide_annotations:
            build_indoor_graph(summary[name], args.guide_annotations, out_dir)
            print(f"[OK] 실내 그래프 생성 완료: {name}")


if __name__ == "__main__":
    main()
