#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate draft annotation JSON files from guide-map images.

This is intentionally conservative:
- It detects yellow exit-number boxes with OpenCV.
- It attempts simple template OCR for numeric labels.
- It writes detected labels and only creates control_points when the label is
  present in the station's known entrance list.

The output still needs human review before production routing.
"""

from __future__ import annotations

import argparse
import itertools
import json
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_indoor_map_v3 import normalize_station_name


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


def imread_unicode(path: Path):
    data = np.fromfile(str(path), dtype=np.uint8)
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def safe_stem(text: str) -> str:
    return re.sub(r'[<>:"/\\\\|?*]+', "_", text)


def relaxed_station_key(name: Optional[str]) -> Optional[str]:
    normalized = normalize_station_name(name)
    if normalized is None:
        return None
    key = re.sub(r"\([^)]*\)", "", normalized)
    return key.replace("역", "").replace(" ", "")


def station_base_lookup(station_summary: Dict[str, dict]) -> Dict[str, dict]:
    lookup = {}
    for name, base in station_summary.items():
        lookup[name] = base
        relaxed = relaxed_station_key(name)
        if relaxed and relaxed not in lookup:
            lookup[relaxed] = base
    return lookup


def find_station_base(station_name: str, lookup: Dict[str, dict]) -> Optional[dict]:
    return lookup.get(station_name) or lookup.get(relaxed_station_key(station_name))


def line_no_from_path(path: Path) -> Optional[str]:
    parent = path.parent.name.strip()
    if parent.isdigit():
        return parent
    if parent.endswith("호선") and parent[:-2].isdigit():
        return parent[:-2]
    return None


def iter_images(root: Path) -> Iterable[Path]:
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def detect_yellow_boxes(img) -> List[dict]:
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, np.array([15, 60, 100]), np.array([42, 255, 255]))
    kernel = np.ones((3, 3), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    height, width = img.shape[:2]
    boxes: List[dict] = []
    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        area = w * h
        if area < 180 or area > width * height * 0.01:
            continue
        if w < 12 or h < 12:
            continue
        aspect = w / float(h)
        if aspect < 0.35 or aspect > 3.6:
            continue
        fill = cv2.contourArea(contour) / float(area)
        if fill < 0.45:
            continue
        boxes.append({
            "bbox": [int(x), int(y), int(w), int(h)],
            "image_xy": [int(x + w / 2), int(y + h / 2)],
            "area": int(area),
        })
    return suppress_nested_boxes(boxes)


def suppress_nested_boxes(boxes: List[dict]) -> List[dict]:
    kept: List[dict] = []
    for box in sorted(boxes, key=lambda b: b["area"]):
        x, y, w, h = box["bbox"]
        cx, cy = box["image_xy"]
        nested = False
        for other in kept:
            ox, oy, ow, oh = other["bbox"]
            if ox <= cx <= ox + ow and oy <= cy <= oy + oh and other["area"] > box["area"] * 1.8:
                nested = True
                break
        if not nested:
            kept.append(box)
    return sorted(kept, key=lambda b: (b["bbox"][1], b["bbox"][0]))


def digit_mask_from_crop(crop) -> Optional[np.ndarray]:
    if crop.size == 0:
        return None
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    # Black digits/borders on yellow background.
    mask = (gray < 95).astype(np.uint8) * 255
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    parts = []
    for c in contours:
        x, y, w, h = cv2.boundingRect(c)
        if w * h < 8:
            continue
        # Skip most border fragments.
        if x <= 1 or y <= 1 or x + w >= crop.shape[1] - 1 or y + h >= crop.shape[0] - 1:
            if w > crop.shape[1] * 0.7 or h > crop.shape[0] * 0.7:
                continue
        parts.append((x, y, w, h))
    if not parts:
        return None
    x1 = max(min(p[0] for p in parts) - 2, 0)
    y1 = max(min(p[1] for p in parts) - 2, 0)
    x2 = min(max(p[0] + p[2] for p in parts) + 2, crop.shape[1])
    y2 = min(max(p[1] + p[3] for p in parts) + 2, crop.shape[0])
    digit = mask[y1:y2, x1:x2]
    if digit.shape[0] < 5 or digit.shape[1] < 3:
        return None
    return digit


def make_template(text: str, size: Tuple[int, int], font, scale: float, thickness: int) -> np.ndarray:
    width, height = size
    canvas = np.zeros((height, width), dtype=np.uint8)
    (tw, th), baseline = cv2.getTextSize(text, font, scale, thickness)
    x = max((width - tw) // 2, 0)
    y = max((height + th) // 2 - baseline, th)
    cv2.putText(canvas, text, (x, y), font, scale, 255, thickness, cv2.LINE_AA)
    _, canvas = cv2.threshold(canvas, 35, 255, cv2.THRESH_BINARY)
    return canvas


def recognize_exit_candidates(crop, max_number: int = 20, top_k: int = 5) -> List[dict]:
    digit = digit_mask_from_crop(crop)
    if digit is None:
        return []
    target_size = (42, 42)
    digit = cv2.resize(digit, target_size, interpolation=cv2.INTER_AREA)
    _, digit = cv2.threshold(digit, 80, 255, cv2.THRESH_BINARY)
    scores = {}
    fonts = [cv2.FONT_HERSHEY_SIMPLEX, cv2.FONT_HERSHEY_DUPLEX]
    for label in [str(i) for i in range(1, max_number + 1)]:
        best_for_label = -1.0
        for font in fonts:
            for scale in (0.85, 0.95, 1.05, 1.15):
                for thickness in (2, 3, 4):
                    template = make_template(label, target_size, font, scale, thickness)
                    score = cv2.matchTemplate(digit, template, cv2.TM_CCOEFF_NORMED)[0][0]
                    best_for_label = max(best_for_label, float(score))
        scores[label] = best_for_label
    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)[:top_k]
    return [{"label": label, "score": round(score, 4)} for label, score in ranked]


def recognize_exit_number(crop, max_number: int = 20) -> Tuple[Optional[str], float, List[dict]]:
    candidates = recognize_exit_candidates(crop, max_number=max_number)
    if not candidates:
        return None, 0.0, []
    best = candidates[0]
    if best["score"] < 0.18:
        return None, best["score"], candidates
    return best["label"], best["score"], candidates


def estimate_affine_rmse(candidates: List[dict], entrance_map: Dict[str, dict]) -> Optional[float]:
    src, dst = [], []
    for item in candidates:
        label = str(item["label"])
        if label not in entrance_map:
            return None
        src.append(item["image_xy"])
        dst.append([entrance_map[label]["x"], entrance_map[label]["y"]])
    if len(src) < 3:
        return None
    src_np = np.array(src, dtype=np.float32)
    dst_np = np.array(dst, dtype=np.float32)
    matrix, _ = cv2.estimateAffine2D(src_np, dst_np, method=cv2.LMEDS)
    if matrix is None:
        matrix, _ = cv2.estimateAffinePartial2D(src_np, dst_np, method=cv2.LMEDS)
    if matrix is None:
        return None
    predicted = np.hstack([src_np, np.ones((len(src_np), 1), dtype=np.float32)]) @ matrix.T
    errors = np.linalg.norm(predicted - dst_np, axis=1)
    return float(np.sqrt(np.mean(np.square(errors))))


def image_spread_score(candidates: List[dict], width: int, height: int) -> float:
    if len(candidates) < 2:
        return 0.0
    pts = np.array([item["image_xy"] for item in candidates], dtype=float)
    spread_x = (float(np.max(pts[:, 0]) - np.min(pts[:, 0])) / max(float(width), 1.0))
    spread_y = (float(np.max(pts[:, 1]) - np.min(pts[:, 1])) / max(float(height), 1.0))
    return spread_x + spread_y


def control_points_from_assigned_candidates(assigned: List[dict]) -> List[dict]:
    result = []
    for item in sorted(assigned, key=lambda cp: int(cp["assigned_label"]) if str(cp["assigned_label"]).isdigit() else str(cp["assigned_label"])):
        result.append({
            "entrance_no": str(item["assigned_label"]),
            "image_xy": item["image_xy"],
            "ocr_label": item.get("label"),
            "ocr_score": item.get("ocr_score"),
            "assigned_label_ocr_score": assigned_label_score(item, str(item["assigned_label"])),
            "source_detection_id": item.get("id"),
        })
    return result


def assigned_label_score(item: dict, label: str) -> float:
    for candidate in item.get("ocr_candidates", []):
        if str(candidate.get("label")) == str(label):
            return float(candidate.get("score", 0.0))
    return 0.0


def infer_control_points_by_geometry(
    detected: List[dict],
    station_base: dict,
    width: int,
    height: int,
    max_points: int = 6,
) -> Tuple[List[dict], Optional[dict]]:
    entrance_labels = [
        str(e["entrance_no"])
        for e in station_base.get("entrances", [])
        if e.get("entrance_no") is not None
    ]
    entrance_labels = sorted(set(entrance_labels), key=lambda x: int(x) if x.isdigit() else x)
    entrance_map = {
        str(e["entrance_no"]): e
        for e in station_base.get("entrances", [])
        if e.get("entrance_no") is not None
    }
    candidates = [
        item for item in detected
        if item.get("label") is not None and item.get("ocr_score", 0.0) >= 0.18
    ]
    candidates = sorted(candidates, key=lambda item: item.get("ocr_score", 0.0), reverse=True)[:8]
    if len(candidates) < 3 or len(entrance_labels) < 3:
        return [], None

    k = min(len(candidates), len(entrance_labels), max_points)
    best = None
    best_meta = None
    candidate_subsets = list(itertools.combinations(candidates, k))
    label_subsets = list(itertools.combinations(entrance_labels, k))
    # Keep this fallback bounded. It is meant for small stations where OCR
    # misses labels but the geometry has enough structure to infer them.
    if len(candidate_subsets) * len(label_subsets) * math_factorial_limited(k, 1000000) > 400000:
        return [], None

    for candidate_subset in candidate_subsets:
        for label_subset in label_subsets:
            for label_perm in itertools.permutations(label_subset):
                assigned = []
                for item, label in zip(candidate_subset, label_perm):
                    merged = dict(item)
                    merged["assigned_label"] = label
                    merged["label"] = label
                    assigned.append(merged)
                rmse = estimate_affine_rmse(assigned, entrance_map)
                if rmse is None:
                    continue
                spread = image_spread_score(assigned, width, height)
                assigned_ocr = float(np.mean([assigned_label_score(item, str(item["assigned_label"])) for item in assigned]))
                # Prefer geometrically coherent, spatially spread anchors, but
                # avoid assignments that are very implausible for the digit crop.
                score = rmse - 2.0 * spread + 6.0 * max(0.0, 0.28 - assigned_ocr)
                if best is None or score < best_meta["score"]:
                    best = assigned
                    best_meta = {
                        "method": "geometry_assignment_without_trusting_ocr",
                        "score": score,
                        "affine_rmse_m": rmse,
                        "image_spread_score": spread,
                        "assigned_label_average_ocr_score": assigned_ocr,
                        "candidate_count": len(candidates),
                        "entrance_label_count": len(entrance_labels),
                        "selected_label_count": len(assigned),
                    }

    if best is None:
        return [], None
    return control_points_from_assigned_candidates(best), best_meta


def infer_control_points_by_angular_order(
    detected: List[dict],
    station_base: dict,
    width: int,
    height: int,
    max_points: int = 8,
) -> Tuple[List[dict], Optional[dict]]:
    entrance_labels = [
        str(e["entrance_no"])
        for e in station_base.get("entrances", [])
        if e.get("entrance_no") is not None and str(e["entrance_no"]).isdigit()
    ]
    entrance_labels = sorted(set(entrance_labels), key=lambda x: int(x))
    if not entrance_labels:
        return [], None
    expected = [str(i) for i in range(1, len(entrance_labels) + 1)]
    if entrance_labels != expected:
        return [], None

    candidates = [
        item for item in detected
        if item.get("label") is not None and item.get("ocr_score", 0.0) >= 0.18
    ]
    if len(candidates) != len(entrance_labels) or len(candidates) < 3 or len(candidates) > max_points:
        return [], None

    pts = np.array([item["image_xy"] for item in candidates], dtype=float)
    center = np.mean(pts, axis=0)
    ordered = sorted(
        candidates,
        key=lambda item: math_angle(item["image_xy"][0] - center[0], item["image_xy"][1] - center[1]),
    )
    assigned = []
    for item, label in zip(ordered, entrance_labels):
        merged = dict(item)
        merged["assigned_label"] = label
        assigned.append(merged)
    entrance_map = {
        str(e["entrance_no"]): e
        for e in station_base.get("entrances", [])
        if e.get("entrance_no") is not None
    }
    rmse = estimate_affine_rmse(assigned, entrance_map)
    meta = {
        "method": "angular_order_assignment_for_sequential_exits",
        "affine_rmse_m": rmse,
        "image_spread_score": image_spread_score(assigned, width, height),
        "candidate_count": len(candidates),
        "entrance_label_count": len(entrance_labels),
        "selected_label_count": len(assigned),
        "reason": "ocr_too_weak_but_detected_count_matches_sequential_entrances",
    }
    return control_points_from_assigned_candidates(assigned), meta


def math_angle(dx: float, dy: float) -> float:
    return float(np.arctan2(dy, dx))


def math_factorial_limited(n: int, limit: int) -> int:
    value = 1
    for i in range(2, n + 1):
        value *= i
        if value > limit:
            return value
    return value


def select_control_points(
    detected: List[dict],
    station_base: Optional[dict],
    width: int,
    height: int,
    max_candidates_per_label: int = 4,
) -> Tuple[List[dict], dict]:
    if not station_base:
        return [], {
            "method": "none",
            "reason": "station_base_not_found",
            "affine_rmse_m": None,
        }

    entrance_map = {
        str(e["entrance_no"]): e
        for e in station_base.get("entrances", [])
        if e.get("entrance_no") is not None
    }
    grouped: Dict[str, List[dict]] = {}
    for item in detected:
        label = item.get("label")
        if label is None:
            continue
        label = str(label)
        if label not in entrance_map:
            continue
        grouped.setdefault(label, []).append(item)

    grouped = {
        label: sorted(items, key=lambda item: item.get("ocr_score", 0.0), reverse=True)[:max_candidates_per_label]
        for label, items in grouped.items()
    }
    if len(grouped) < 3:
        angular, angular_meta = infer_control_points_by_angular_order(detected, station_base, width, height)
        if angular:
            angular_meta["known_exit_labels_from_ocr"] = sorted(grouped.keys(), key=lambda x: int(x) if x.isdigit() else x)
            return angular, angular_meta
        inferred, inferred_meta = infer_control_points_by_geometry(detected, station_base, width, height)
        if inferred:
            inferred_meta["reason"] = f"ocr_found_only_{len(grouped)}_known_exit_labels"
            inferred_meta["known_exit_labels_from_ocr"] = sorted(grouped.keys(), key=lambda x: int(x) if x.isdigit() else x)
            return inferred, inferred_meta
        return [], {
            "method": "known_entrance_filter",
            "reason": f"only_{len(grouped)}_known_exit_labels_detected",
            "known_exit_labels": sorted(grouped.keys(), key=lambda x: int(x) if x.isdigit() else x),
            "affine_rmse_m": None,
        }

    labels = sorted(grouped.keys(), key=lambda x: int(x) if x.isdigit() else x)
    labels_for_search = labels[:8]
    best = None
    best_meta = None

    for subset_size in range(len(labels_for_search), 2, -1):
        for subset in itertools.combinations(labels_for_search, subset_size):
            product_size = 1
            for label in subset:
                product_size *= len(grouped[label])
            if product_size > 20000:
                continue
            for combo in itertools.product(*(grouped[label] for label in subset)):
                combo = list(combo)
                rmse = estimate_affine_rmse(combo, entrance_map)
                if rmse is None:
                    continue
                avg_ocr = float(np.mean([item.get("ocr_score", 0.0) for item in combo]))
                spread = image_spread_score(combo, width, height)
                score = rmse - 2.0 * spread + 1.5 * max(0.0, 0.35 - avg_ocr)
                if best is None or score < best_meta["score"]:
                    best = combo
                    best_meta = {
                        "method": "known_entrance_filter_plus_affine_consistency",
                        "score": score,
                        "affine_rmse_m": rmse,
                        "average_ocr_score": avg_ocr,
                        "image_spread_score": spread,
                        "candidate_label_count": len(labels),
                        "selected_label_count": len(combo),
                    }
        if best is not None and best_meta["affine_rmse_m"] < 12.0:
            break

    if best is None:
        best = [grouped[label][0] for label in labels]
        best_meta = {
            "method": "highest_ocr_per_known_label",
            "score": None,
            "affine_rmse_m": estimate_affine_rmse(best, entrance_map),
            "candidate_label_count": len(labels),
            "selected_label_count": len(best),
        }

    control_points = []
    for item in sorted(best, key=lambda cp: int(cp["label"]) if str(cp["label"]).isdigit() else str(cp["label"])):
        control_points.append({
            "entrance_no": str(item["label"]),
            "image_xy": item["image_xy"],
            "ocr_score": item.get("ocr_score"),
            "source_detection_id": item.get("id"),
        })
    return control_points, best_meta


def load_station_summary(path: Path) -> Dict[str, dict]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def build_annotation_for_image(image_path: Path, station_base: Optional[dict], image_root: Path) -> dict:
    img = imread_unicode(image_path)
    if img is None:
        raise ValueError(f"이미지 읽기 실패: {image_path}")
    height, width = img.shape[:2]
    station_name = normalize_station_name(image_path.stem)
    line_no = line_no_from_path(image_path)

    entrance_numbers = set()
    if station_base:
        entrance_numbers = {str(e["entrance_no"]) for e in station_base.get("entrances", []) if e.get("entrance_no") is not None}

    detected = []
    for i, box in enumerate(detect_yellow_boxes(img), start=1):
        x, y, w, h = box["bbox"]
        pad = max(2, int(min(w, h) * 0.08))
        crop = img[max(y - pad, 0):min(y + h + pad, height), max(x - pad, 0):min(x + w + pad, width)]
        label, score, ocr_candidates = recognize_exit_number(crop, max_number=20)
        is_known = label in entrance_numbers if label else False
        item = {
            "id": f"detected_exit_label_{i:03d}",
            "label": label,
            "ocr_score": round(score, 4),
            "ocr_candidates": ocr_candidates,
            "known_station_entrance": bool(is_known),
            "bbox": box["bbox"],
            "image_xy": box["image_xy"],
        }
        detected.append(item)

    control_points, selection_meta = select_control_points(detected, station_base, width, height)
    nodes = [
        {"id": f"exit_{cp['entrance_no']}", "kind": "exit", "floor": None, "image_xy": cp["image_xy"]}
        for cp in control_points
    ]

    return {
        "station_name": station_name,
        "line_no": line_no,
        "image_width": width,
        "image_height": height,
        "source_image": str(image_path.relative_to(image_root.parent)).replace("\\", "/"),
        "annotation_status": "auto_draft_needs_review",
        "note": "Auto-generated by tools/generate_annotation_drafts.py. Yellow exit labels were detected with OpenCV, numeric labels were estimated with simple template matching, and control points were selected using known SHP entrances plus affine consistency. Review before using for routing.",
        "matched_station_name": station_base.get("station_name") if station_base else None,
        "control_point_selection": selection_meta,
        "control_points": control_points,
        "nodes": nodes,
        "edges": [],
        "detected_exit_labels": detected,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image-root", default="station_image")
    parser.add_argument("--station-summary", default="indoor_map/station_base_summary.json")
    parser.add_argument("--output-dir", default="annotations/auto_draft")
    parser.add_argument("--min-control-points", type=int, default=3)
    args = parser.parse_args()

    image_root = Path(args.image_root)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    station_summary = load_station_summary(Path(args.station_summary))
    lookup = station_base_lookup(station_summary)

    report = []
    for image_path in iter_images(image_root):
        station_name = normalize_station_name(image_path.stem)
        station_base = find_station_base(station_name, lookup)
        ann = build_annotation_for_image(image_path, station_base, image_root)
        line_no = ann.get("line_no") or "unknown_line"
        filename = f"{line_no}_{safe_stem(station_name)}_annotation_draft.json"
        out_path = output_dir / filename
        with out_path.open("w", encoding="utf-8") as f:
            json.dump(ann, f, ensure_ascii=False, indent=2)
        report.append({
            "image": ann["source_image"],
            "station_name": station_name,
            "line_no": line_no,
            "detected_exit_labels": len(ann["detected_exit_labels"]),
            "control_points": len(ann["control_points"]),
            "matched_station_name": ann.get("matched_station_name"),
            "control_point_selection": ann.get("control_point_selection"),
            "usable_for_affine": len(ann["control_points"]) >= args.min_control_points,
            "output": str(out_path).replace("\\", "/"),
        })

    with (output_dir / "_annotation_draft_report.json").open("w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    usable = sum(1 for row in report if row["usable_for_affine"])
    print(f"[OK] wrote {len(report)} annotation drafts")
    print(f"[OK] usable_for_affine >= {args.min_control_points}: {usable}")
    print(f"[OK] report: {output_dir / '_annotation_draft_report.json'}")


if __name__ == "__main__":
    main()
