#!/usr/bin/env python3
"""Train a self-supervised motion model from unlabeled IMU logs."""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


FEATURE_NAMES = [
    "user_accel_magnitude",
    "gyro_magnitude",
    "tilt_gyro_magnitude",
    "filtered_accel",
    "active_threshold",
    "threshold_margin",
    "threshold_margin_ratio",
    "heading_change_degrees",
    "angular_velocity_dps",
    "window_mean_user_accel",
    "window_std_user_accel",
    "window_mean_gyro",
    "window_std_gyro",
    "window_max_heading_change",
    "seconds_since_prev_step",
    "heading_change_since_prev_step",
    "recent_step_interval_mean",
    "recent_step_interval_std",
    "heading_change_rate_since_prev_step",
    "filtered_to_user_accel_ratio",
    "accel_to_gyro_ratio",
]

WINDOW_SIZE = 9


@dataclass
class Sample:
    features: list[float]
    timestamp: datetime
    peak_height: float
    prominence: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, help="Directory containing IMU CSV logs.")
    parser.add_argument(
        "--output",
        default="models/self_supervised_step_model.json",
        help="Output JSON model path.",
    )
    parser.add_argument("--seed", type=int, default=13)
    parser.add_argument("--clusters", type=int, default=3)
    parser.add_argument("--min-length", type=float, default=0.5)
    parser.add_argument("--max-length", type=float, default=0.95)
    parser.add_argument("--epochs", type=int, default=3600, help="Regression training epochs.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    random.seed(args.seed)

    input_dir = Path(args.input_dir)
    csv_paths = sorted(path for path in input_dir.rglob("*.csv") if path.is_file())
    if not csv_paths:
        raise SystemExit(f"No CSV logs found in {input_dir}")

    print(f"[1/6] Found {len(csv_paths)} CSV file(s) in {input_dir}")
    all_samples: list[Sample] = []
    for index, path in enumerate(csv_paths, start=1):
        print(f"  - [{index}/{len(csv_paths)}] Extracting candidates from {path.name}")
        samples = load_candidate_samples(path)
        all_samples.extend(samples)
        print(f"    -> candidates: {len(samples)} (cumulative {len(all_samples)})")

    if not all_samples:
        raise SystemExit("No candidate windows were found in the input logs.")

    print(f"[2/6] Normalizing {len(all_samples)} candidate windows...")
    means, stds = fit_normalization(all_samples)
    normalized = [normalize(sample.features, means, stds) for sample in all_samples]

    print(f"[3/6] Running k-means with k={args.clusters}...")
    centroids, assignments = kmeans(normalized, args.clusters, args.seed)

    cluster_stats = compute_cluster_stats(all_samples, assignments)
    step_cluster_index = max(range(args.clusters), key=lambda idx: cluster_stats[idx]["cluster_score"])
    step_probabilities = [
        softmax_step_probability(normalized[i], centroids, step_cluster_index)
        for i in range(len(all_samples))
    ]
    step_threshold = clamp(
        mean(step_probabilities) - 0.25 * stddev(step_probabilities),
        0.3,
        0.8,
    )

    print(f"[4/6] Selected cluster {step_cluster_index} as the step prototype")
    print(f"      Threshold set to {step_threshold:.3f}")

    pseudo_targets = build_pseudo_step_lengths(
        all_samples,
        step_probabilities,
        assignments,
        step_cluster_index,
        args.min_length,
        args.max_length,
    )

    print("[5/6] Fitting length projection on pseudo step lengths...")
    length_weights, length_bias = fit_linear_regression(
        normalized,
        pseudo_targets,
        means,
        stds,
        seed=args.seed,
        epochs=args.epochs,
    )

    print("[6/6] Evaluating and writing model...")
    length_predictions = [
        clamp(
            dot(length_weights, normalized[i]) + length_bias,
            args.min_length,
            args.max_length,
        )
        for i in range(len(all_samples))
    ]
    length_mae = mean(
        abs(pred - target) for pred, target in zip(length_predictions, pseudo_targets)
    )
    length_rmse = math.sqrt(
        mean((pred - target) ** 2 for pred, target in zip(length_predictions, pseudo_targets))
    )

    output = {
        "model_type": "self_supervised_prototype_step_model_v1",
        "feature_names": FEATURE_NAMES,
        "normalization": {"means": means, "stds": stds},
        "clusters": [
            {
                "centroid": centroid,
                "score": cluster_stats[index]["cluster_score"],
                "size": cluster_stats[index]["size"],
                "mean_peak_height": cluster_stats[index]["mean_peak_height"],
                "mean_prominence": cluster_stats[index]["mean_prominence"],
                "mean_cadence_seconds": cluster_stats[index]["mean_cadence_seconds"],
            }
            for index, centroid in enumerate(centroids)
        ],
        "step_cluster_index": step_cluster_index,
        "step_decision_threshold": step_threshold,
        "minimum_step_length_meters": args.min_length,
        "maximum_step_length_meters": args.max_length,
        "length_weights": length_weights,
        "length_bias": length_bias,
        "metrics": {
            "candidate_windows": len(all_samples),
            "regression_epochs": args.epochs,
            "length_mae": length_mae,
            "length_rmse": length_rmse,
        },
        "training_summary": {
            "files": [path.name for path in csv_paths],
            "candidate_count": len(all_samples),
            "cluster_count": args.clusters,
            "step_cluster_index": step_cluster_index,
        },
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"Wrote model to {output_path}")
    print(f"Length pseudo-MAE: {length_mae:.4f}")
    print(f"Length pseudo-RMSE: {length_rmse:.4f}")


def load_candidate_samples(path: Path) -> list[Sample]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = [row for row in reader]

    filtered_values = [float_or_default(row.get("filtered_accel")) for row in rows]
    candidates = find_candidate_indices(filtered_values)

    samples: list[Sample] = []
    user_buffer: list[float] = []
    gyro_buffer: list[float] = []
    heading_change_buffer: list[float] = []
    recent_step_intervals: list[float] = []
    previous_candidate_index: int | None = None
    previous_candidate_heading: float | None = None

    for index in candidates:
        row = rows[index]
        timestamp = parse_timestamp(row.get("timestamp"))
        heading_radians = float_or_default(row.get("heading_radians"))
        user_accel = float_or_default(row.get("user_accel_magnitude"))
        gyro = float_or_default(row.get("gyro_magnitude"))
        tilt_gyro = float_or_default(row.get("tilt_gyro_magnitude"))
        filtered_accel = float_or_default(row.get("filtered_accel"))
        active_threshold = estimate_active_threshold(filtered_values, index)
        threshold_margin = filtered_accel - active_threshold
        threshold_margin_ratio = threshold_margin / max(active_threshold, 1e-3)
        if previous_candidate_index is None:
            seconds_since_prev_step = 0.0
        else:
            seconds_since_prev_step = seconds_between(
                timestamp,
                parse_timestamp(rows[previous_candidate_index].get("timestamp")),
            )
        heading_change_since_prev_step = 0.0
        if previous_candidate_heading is not None:
            heading_change_since_prev_step = heading_delta_degrees(
                heading_radians,
                previous_candidate_heading,
            )
        heading_change_rate_since_prev_step = (
            0.0
            if seconds_since_prev_step <= 1e-6
            else heading_change_since_prev_step / seconds_since_prev_step
        )
        heading_change_degrees = heading_change_since_prev_step
        angular_velocity_dps = (
            0.0
            if seconds_since_prev_step <= 1e-6
            else heading_change_degrees / seconds_since_prev_step
        )
        filtered_to_user_accel_ratio = filtered_accel / max(user_accel, 0.05)
        accel_to_gyro_ratio = user_accel / max(gyro, 0.05)

        window_start = max(0, index - WINDOW_SIZE + 1)
        window_rows = rows[window_start : index + 1]
        window_user = [float_or_default(row.get("user_accel_magnitude")) for row in window_rows]
        window_gyro = [float_or_default(row.get("gyro_magnitude")) for row in window_rows]
        prominence = estimate_prominence(filtered_values, index)

        features = [
            user_accel,
            gyro,
            tilt_gyro,
            filtered_accel,
            active_threshold,
            threshold_margin,
            threshold_margin_ratio,
            heading_change_degrees,
            angular_velocity_dps,
            mean(user_buffer),
            stddev(user_buffer),
            mean(gyro_buffer),
            stddev(gyro_buffer),
            max(heading_change_buffer) if heading_change_buffer else 0.0,
            seconds_since_prev_step,
            heading_change_since_prev_step,
            mean(recent_step_intervals),
            stddev(recent_step_intervals),
            heading_change_rate_since_prev_step,
            filtered_to_user_accel_ratio,
            accel_to_gyro_ratio,
        ]

        samples.append(
            Sample(
                features=features,
                timestamp=timestamp,
                peak_height=filtered_accel,
                prominence=prominence,
            )
        )

        user_buffer.append(user_accel)
        gyro_buffer.append(gyro)
        heading_change_buffer.append(heading_change_degrees)
        if previous_candidate_index is not None:
            interval = seconds_since_prev_step
            if interval > 0:
                recent_step_intervals.append(interval)
                if len(recent_step_intervals) > 5:
                    recent_step_intervals.pop(0)
        previous_candidate_index = index
        previous_candidate_heading = heading_radians

    return samples


def find_candidate_indices(values: list[float]) -> list[int]:
    if len(values) < 5:
        return list(range(len(values)))

    baseline_window = 20
    candidates: list[int] = []
    last_candidate_index = -1000
    for index in range(2, len(values) - 2):
        window = values[max(0, index - baseline_window) : index]
        baseline = mean(window) + 0.25 * stddev(window) if window else values[index]
        value = values[index]
        if value < baseline or value < 0.12:
            continue
        if not (value >= values[index - 1] and value >= values[index + 1]):
            continue
        if value < max(values[index - 2], values[index + 2]):
            continue
        if index - last_candidate_index < 2:
            continue
        candidates.append(index)
        last_candidate_index = index
    return candidates


def estimate_active_threshold(values: list[float], index: int) -> float:
    window = values[max(0, index - 20) : index]
    if not window:
        return max(1.1, values[index])
    return max(0.8, mean(window) + 0.3 * stddev(window))


def estimate_prominence(values: list[float], index: int) -> float:
    left_min = min(values[max(0, index - 3) : index + 1])
    right_min = min(values[index : min(len(values), index + 4)])
    return values[index] - max(left_min, right_min)


def build_pseudo_step_lengths(
    samples: list[Sample],
    step_probabilities: list[float],
    assignments: list[int],
    step_cluster_index: int,
    min_length: float,
    max_length: float,
) -> list[float]:
    pseudo_targets: list[float] = []
    step_samples = [sample for sample, assignment in zip(samples, assignments) if assignment == step_cluster_index]
    step_probs = [prob for prob, assignment in zip(step_probabilities, assignments) if assignment == step_cluster_index]
    if not step_samples:
        step_samples = samples
        step_probs = step_probabilities

    for sample, step_prob in zip(step_samples, step_probs):
        cadence_seconds = sample.features[14]
        cadence_component = 1.0 - clamp((cadence_seconds - 0.95) / 1.1, 0.0, 1.0)
        intensity_component = clamp(sample.peak_height / 4.5, 0.0, 1.0)
        prominence_component = clamp(sample.prominence / 2.5, 0.0, 1.0)
        pseudo = min_length + (max_length - min_length) * (
            0.42 * cadence_component +
            0.30 * intensity_component +
            0.18 * prominence_component +
            0.10 * step_prob
        )
        pseudo_targets.append(clamp(pseudo, min_length, max_length))

    return pseudo_targets


def compute_cluster_stats(samples: list[Sample], assignments: list[int]) -> list[dict[str, float]]:
    cluster_count = max(assignments) + 1 if assignments else 0
    stats: list[dict[str, float]] = []
    for cluster_index in range(cluster_count):
        cluster_samples = [
            sample for sample, assignment in zip(samples, assignments) if assignment == cluster_index
        ]
        if not cluster_samples:
            stats.append(
                {
                    "size": 0,
                    "cluster_score": -1e9,
                    "mean_peak_height": 0.0,
                    "mean_prominence": 0.0,
                    "mean_cadence_seconds": 0.0,
                }
            )
            continue
        mean_peak_height = mean(sample.peak_height for sample in cluster_samples)
        mean_prominence = mean(sample.prominence for sample in cluster_samples)
        cadence_seconds = [sample.features[14] for sample in cluster_samples if sample.features[14] > 0]
        mean_cadence = mean(cadence_seconds) if cadence_seconds else 0.0
        cadence_consistency = 1.0 / (1.0 + stddev(cadence_seconds)) if len(cadence_seconds) >= 2 else 0.5
        gyro_penalty = mean(sample.features[1] for sample in cluster_samples)
        cluster_score = (
            0.38 * mean_peak_height
            + 0.24 * mean_prominence
            + 0.20 * cadence_consistency
            + 0.12 * (1.0 - clamp(abs(mean_cadence - 0.9) / 1.3, 0.0, 1.0))
            - 0.06 * gyro_penalty
        )
        stats.append(
            {
                "size": len(cluster_samples),
                "cluster_score": cluster_score,
                "mean_peak_height": mean_peak_height,
                "mean_prominence": mean_prominence,
                "mean_cadence_seconds": mean_cadence,
            }
        )
    return stats


def kmeans(values: list[list[float]], k: int, seed: int) -> tuple[list[list[float]], list[int]]:
    rng = random.Random(seed)
    centroids = [list(values[i]) for i in rng.sample(range(len(values)), k)]
    assignments = [0] * len(values)

    for _ in range(50):
        changed = False
        for index, value in enumerate(values):
            distances = [_distance(value, centroid) for centroid in centroids]
            assignment = min(range(k), key=lambda idx: distances[idx])
            if assignments[index] != assignment:
                assignments[index] = assignment
                changed = True

        new_centroids = []
        for cluster_index in range(k):
            cluster_values = [value for value, assignment in zip(values, assignments) if assignment == cluster_index]
            if not cluster_values:
                new_centroids.append(list(values[rng.randrange(len(values))]))
                continue
            new_centroids.append([
                mean(column)
                for column in zip(*cluster_values)
            ])
        centroids = new_centroids
        if not changed:
            break

    return centroids, assignments


def fit_linear_regression(
    normalized_features: list[list[float]],
    targets: list[float],
    means: list[float],
    stds: list[float],
    *,
    seed: int,
    epochs: int = 3600,
) -> tuple[list[float], float]:
    rng = random.Random(seed)
    weights = [0.0] * len(normalized_features[0])
    bias = 0.9
    samples = list(zip(normalized_features, targets))

    for epoch in range(epochs):
        rng.shuffle(samples)
        learning_rate = 0.004 / (1.0 + epoch / 500.0)
        for features, target in samples:
            prediction = dot(weights, features) + bias
            error = clamp(prediction - target, -0.75, 0.75)
            for i, value in enumerate(features):
                weights[i] -= learning_rate * (error * value + 0.001 * weights[i])
            bias -= learning_rate * error

        if epoch == 0 or (epoch + 1) % max(1, epochs // 39) == 0 or epoch + 1 == epochs:
            mae = mean(
                abs(clamp(dot(weights, features) + bias, 0.0, 1.0) - target)
                for features, target in samples
            )
            print(f"    regression epoch {epoch + 1}/{epochs}: pseudo_mae={mae:.4f}")

    return weights, bias


def softmax_step_probability(value: list[float], centroids: list[list[float]], step_cluster_index: int) -> float:
    distances = [_distance(value, centroid) for centroid in centroids]
    inverted = [-distance for distance in distances]
    max_score = max(inverted)
    exps = [math.exp(score - max_score) for score in inverted]
    total = sum(exps)
    if total <= 1e-9:
        return 0.5
    return exps[step_cluster_index] / total


def fit_normalization(samples: list[Sample]) -> tuple[list[float], list[float]]:
    feature_count = len(samples[0].features)
    means = []
    stds = []
    for index in range(feature_count):
        values = [sample.features[index] for sample in samples]
        means.append(mean(values))
        sigma = stddev(values)
        stds.append(sigma if sigma > 1e-9 else 1.0)
    return means, stds


def normalize(features: list[float], means: list[float], stds: list[float]) -> list[float]:
    return [
        (value - means[index]) / stds[index]
        for index, value in enumerate(features)
    ]


def _distance(a: list[float], b: list[float]) -> float:
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def dot(weights: list[float], features: list[float]) -> float:
    return sum(weight * feature for weight, feature in zip(weights, features))


def mean(values: Iterable[float]) -> float:
    values = list(values)
    if not values:
        return 0.0
    return sum(values) / len(values)


def stddev(values: Iterable[float]) -> float:
    values = list(values)
    if len(values) < 2:
        return 0.0
    mu = mean(values)
    variance = sum((value - mu) ** 2 for value in values) / len(values)
    return math.sqrt(variance)


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def parse_timestamp(value: str | None) -> datetime:
    if not value:
        return datetime.fromtimestamp(0)
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return datetime.fromtimestamp(0)


def seconds_between(current: datetime, previous: datetime | None) -> float:
    if previous is None:
        return 0.0
    return max(0.0, (current - previous).total_seconds())


def float_or_default(value: str | None, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        return default


def heading_delta_degrees(a: float, b: float) -> float:
    delta = abs(a - b)
    normalized = (2 * math.pi) - delta if delta > math.pi else delta
    return normalized * 180.0 / math.pi


if __name__ == "__main__":
    main()
