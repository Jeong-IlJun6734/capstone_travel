#!/usr/bin/env python3
"""Validate the self-supervised step model on exported IMU logs."""

from __future__ import annotations

import argparse
import csv
import json
import math
from datetime import datetime
from pathlib import Path


MIN_STEP_GAP_SECONDS = 0.42
MAX_GYRO_MAGNITUDE = 3.2
MINIMUM_STEP_DETECTION_PEAK = 1.2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="models/self_supervised_step_model.json")
    parser.add_argument("logs", nargs="+", help="CSV logs to validate.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model = json.loads(Path(args.model).read_text(encoding="utf-8"))

    for log_path in args.logs:
        result = validate_log(Path(log_path), model)
        print(
            f"{result['name']}: predicted={result['predicted_steps']} "
            f"previous_app={result['previous_app_steps']} "
            f"rows={result['rows']} "
            f"prob_p50={result['prob_p50']:.3f} prob_p90={result['prob_p90']:.3f} "
            f"motion_p50={result['motion_p50']:.3f} motion_p90={result['motion_p90']:.3f}"
        )


def validate_log(path: Path, model: dict) -> dict[str, object]:
    with path.open(encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))

    last_step_timestamp: datetime | None = None
    predicted_steps = 0
    probabilities: list[float] = []
    motion_scores: list[float] = []
    previous_magnitude: float | None = None
    previous_delta = 0.0

    for row in rows:
        probability = step_probability(row, model)
        motion_score = compute_motion_score(row)
        magnitude = float_or_default(row.get("filtered_accel"))
        probabilities.append(probability)
        motion_scores.append(motion_score)

        timestamp = parse_timestamp(row.get("timestamp"))
        gyro = float_or_default(row.get("gyro_magnitude"))
        spacing_ok = (
            last_step_timestamp is None
            or (timestamp - last_step_timestamp).total_seconds() >= MIN_STEP_GAP_SECONDS
        )
        magnitude_delta = 0.0 if previous_magnitude is None else magnitude - previous_magnitude
        is_acceleration_peak = (
            previous_magnitude is not None
            and previous_delta > 0
            and magnitude_delta <= 0
            and previous_magnitude >= MINIMUM_STEP_DETECTION_PEAK
        )
        previous_magnitude = magnitude
        previous_delta = magnitude_delta
        accepted = (
            probability >= model["step_decision_threshold"]
            and is_acceleration_peak
            and (row.get("phone_flat") or "").strip().lower() != "true"
            and spacing_ok
            and gyro <= MAX_GYRO_MAGNITUDE
        )
        if accepted:
            predicted_steps += 1
            last_step_timestamp = timestamp

    previous_app_steps = sum(
        (row.get("imu_step_detected") or "").strip().lower() == "true"
        for row in rows
    )
    return {
        "name": path.name,
        "rows": len(rows),
        "predicted_steps": predicted_steps,
        "previous_app_steps": previous_app_steps,
        "prob_p50": percentile(probabilities, 0.50),
        "prob_p90": percentile(probabilities, 0.90),
        "motion_p50": percentile(motion_scores, 0.50),
        "motion_p90": percentile(motion_scores, 0.90),
    }


def step_probability(row: dict[str, str], model: dict) -> float:
    features = [
        feature_value(row, name)
        for name in model["feature_names"]
    ]
    means = model["normalization"]["means"]
    stds = model["normalization"]["stds"]
    weights = model.get("feature_weights") or [1.0] * len(features)
    normalized = [
        ((value - means[index]) / stds[index]) * weights[index]
        for index, value in enumerate(features)
    ]
    centroids = [cluster["centroid"] for cluster in model["clusters"]]
    distances = [
        math.sqrt(sum((a - b) ** 2 for a, b in zip(normalized, centroid)))
        for centroid in centroids
    ]
    inverted = [-distance for distance in distances]
    max_score = max(inverted)
    exp_scores = [math.exp(score - max_score) for score in inverted]
    total = sum(exp_scores)
    if total <= 1e-9:
        return 0.5
    selected = model.get("step_cluster_indices") or [model["step_cluster_index"]]
    return sum(exp_scores[index] for index in selected) / total


def compute_motion_score(row: dict[str, str]) -> float:
    magnitude = float_or_default(row.get("filtered_accel"))
    active_threshold = float_or_default(row.get("active_threshold"), 0.8)
    user_accel = float_or_default(row.get("user_accel_magnitude"))
    gyro = float_or_default(row.get("gyro_magnitude"))
    threshold_margin_ratio = (magnitude - active_threshold) / max(active_threshold, 1e-3)
    filtered_to_user = magnitude / max(user_accel, 0.05)
    accel_to_gyro = user_accel / max(gyro, 0.05)

    threshold_score = normalized_progress(threshold_margin_ratio, -0.18, 0.62)
    filtered_score = normalized_progress(filtered_to_user, 0.65, 1.65)
    accel_score = normalized_progress(user_accel, 0.72, 3.8)
    gyro_penalty = 1.0 - normalized_progress(gyro, 0.0, 2.2)
    accel_gyro_balance = normalized_progress(accel_to_gyro, 1.0, 8.5)
    absolute_motion_score = normalized_progress(
        magnitude,
        active_threshold - 0.25,
        active_threshold + 0.75,
    )
    return clamp01(
        0.30 * threshold_score
        + 0.20 * filtered_score
        + 0.20 * accel_score
        + 0.14 * accel_gyro_balance
        + 0.10 * absolute_motion_score
        + 0.06 * gyro_penalty
    )


def feature_value(row: dict[str, str], name: str) -> float:
    aliases = {
        "heading_change_degrees": "heading_change_since_prev_step",
        "angular_velocity_dps": "heading_change_rate_since_prev_step",
    }
    return float_or_default(row.get(name) or row.get(aliases.get(name, "")))


def normalized_progress(value: float, minimum: float, maximum: float) -> float:
    if maximum <= minimum:
        return 0.5
    return clamp01((value - minimum) / (maximum - minimum))


def percentile(values: list[float], ratio: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(len(ordered) * ratio)))
    return ordered[index]


def parse_timestamp(value: str | None) -> datetime:
    if not value:
        return datetime.fromtimestamp(0)
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return datetime.fromtimestamp(0)


def float_or_default(value: str | None, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        return default


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


if __name__ == "__main__":
    main()
