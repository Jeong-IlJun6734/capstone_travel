#!/usr/bin/env python3
"""Train the step-length regression model from exported IMU logs."""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
from collections import deque
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
    target: float
    weight: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, help="Directory containing IMU CSV logs.")
    parser.add_argument("--output", required=True, help="Output JSON model path.")
    parser.add_argument(
        "--target-column",
        default="manual_step_length_m",
        help="Preferred target column. Falls back to last_step_length_m when absent.",
    )
    parser.add_argument("--test-split", type=float, default=0.2)
    parser.add_argument("--epochs", type=int, default=1600)
    parser.add_argument("--learning-rate", type=float, default=0.03)
    parser.add_argument("--l2", type=float, default=0.0005)
    parser.add_argument("--seed", type=int, default=11)
    parser.add_argument("--min-length", type=float, default=0.832)
    parser.add_argument("--max-length", type=float, default=0.95)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    random.seed(args.seed)

    input_dir = Path(args.input_dir)
    csv_paths = sorted(path for path in input_dir.rglob("*.csv") if path.is_file())
    if not csv_paths:
        raise SystemExit(f"No CSV logs found in {input_dir}")

    print(f"[1/5] Found {len(csv_paths)} CSV file(s) in {input_dir}")
    train_files, val_files = split_files(csv_paths, args.test_split, args.seed)
    print(
        f"[2/5] Split files into {len(train_files)} train and {len(val_files)} validation file(s)"
    )
    print("[3/5] Loading training samples...")
    train_samples = load_samples(train_files, args.target_column, args.min_length, args.max_length)
    print("[4/5] Loading validation samples...")
    val_samples = load_samples(val_files, args.target_column, args.min_length, args.max_length)
    if not train_samples:
        raise SystemExit("No training samples were produced from the input logs.")

    print(f"[5/5] Fitting regression model on {len(train_samples)} training samples...")
    means, stds = fit_normalization(train_samples)
    weights, bias = fit_linear_regression(
        train_samples,
        means=means,
        stds=stds,
        epochs=args.epochs,
        learning_rate=args.learning_rate,
        l2=args.l2,
    )

    train_metrics = evaluate(train_samples, weights, bias, means, stds, args.min_length, args.max_length)
    val_metrics = evaluate(val_samples, weights, bias, means, stds, args.min_length, args.max_length)

    output = {
        "model_type": "linear_regression_sgd_v1",
        "feature_names": FEATURE_NAMES,
        "weights": weights,
        "bias": bias,
        "normalization": {"means": means, "stds": stds},
        "minimum_step_length_meters": args.min_length,
        "maximum_step_length_meters": args.max_length,
        "metrics": {
            "train": train_metrics,
            "validation": val_metrics,
        },
        "training_summary": {
            "files": [path.name for path in csv_paths],
            "train_files": [path.name for path in train_files],
            "validation_files": [path.name for path in val_files],
            "train_samples": len(train_samples),
            "validation_samples": len(val_samples),
            "target_column": args.target_column,
        },
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"Wrote model to {output_path}")
    print(f"Validation MAE: {val_metrics['mae']:.4f}")
    print(f"Validation RMSE: {val_metrics['rmse']:.4f}")


def split_files(paths: list[Path], test_split: float, seed: int) -> tuple[list[Path], list[Path]]:
    shuffled = list(paths)
    random.Random(seed).shuffle(shuffled)
    validation_count = max(1, int(round(len(shuffled) * test_split))) if len(shuffled) > 1 else 0
    validation_files = shuffled[:validation_count]
    train_files = shuffled[validation_count:] or shuffled[:1]
    if not validation_files:
        validation_files = train_files[-1:]
        train_files = train_files[:-1] or validation_files
    return train_files, validation_files


def load_samples(paths: Iterable[Path], target_column: str, min_length: float, max_length: float) -> list[Sample]:
    samples: list[Sample] = []
    paths = list(paths)
    for index, path in enumerate(paths, start=1):
        print(f"  - [{index}/{len(paths)}] Parsing {path.name}")
        samples.extend(load_samples_from_file(path, target_column, min_length, max_length))
        print(f"    -> cumulative samples: {len(samples)}")
    return samples


def load_samples_from_file(path: Path, target_column: str, min_length: float, max_length: float) -> list[Sample]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)

    samples: list[Sample] = []
    user_buffer: deque[float] = deque(maxlen=WINDOW_SIZE)
    gyro_buffer: deque[float] = deque(maxlen=WINDOW_SIZE)
    heading_change_buffer: deque[float] = deque(maxlen=WINDOW_SIZE)
    recent_step_intervals: deque[float] = deque(maxlen=5)
    previous_timestamp: datetime | None = None
    previous_heading_radians: float | None = None
    last_positive_timestamp: datetime | None = None
    last_positive_heading_radians: float | None = None

    for row in rows:
        timestamp = parse_timestamp(row.get("timestamp"))
        heading_radians = float_or_default(row.get("heading_radians"))
        user_accel = float_or_default(row.get("user_accel_magnitude"))
        gyro = float_or_default(row.get("gyro_magnitude"))
        tilt_gyro = float_or_default(row.get("tilt_gyro_magnitude"))
        filtered_accel = float_or_default(row.get("filtered_accel"))
        active_threshold = float_or_default(row.get("active_threshold"))
        threshold_margin = float_or_default(
            row.get("threshold_margin"),
            filtered_accel - active_threshold,
        )
        threshold_margin_ratio = float_or_default(
            row.get("threshold_margin_ratio"),
            threshold_margin / max(active_threshold, 1e-3),
        )
        seconds_since_prev_step = seconds_between(timestamp, last_positive_timestamp)
        heading_change_since_prev_step = 0.0
        if last_positive_heading_radians is not None:
            heading_change_since_prev_step = heading_delta_degrees(
                heading_radians,
                last_positive_heading_radians,
            )
        heading_change_rate_since_prev_step = (
            0.0
            if seconds_since_prev_step <= 1e-6
            else heading_change_since_prev_step / seconds_since_prev_step
        )
        heading_change_degrees = 0.0
        angular_velocity_dps = 0.0
        if previous_heading_radians is not None and previous_timestamp is not None:
            delta = heading_delta_degrees(heading_radians, previous_heading_radians)
            heading_change_degrees = delta
            dt = seconds_between(timestamp, previous_timestamp)
            angular_velocity_dps = 0.0 if dt <= 1e-6 else delta / dt
        filtered_to_user_accel_ratio = filtered_accel / max(user_accel, 0.05)
        accel_to_gyro_ratio = user_accel / max(gyro, 0.05)

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

        target = float_or_default(row.get(target_column))
        if target <= 0:
            target = float_or_default(row.get("last_step_length_m"))
        if target <= 0:
            continue

        weight = 0.65
        if row.get("step_source", "").lower().find("learned classifier") >= 0:
          weight += 0.15

        samples.append(Sample(features=features, target=target, weight=weight))

        user_buffer.append(user_accel)
        gyro_buffer.append(gyro)
        heading_change_buffer.append(heading_change_degrees)
        if row.get("imu_step_detected", "").strip().lower() in {"true", "1", "yes"}:
            if last_positive_timestamp is not None:
                interval = seconds_between(timestamp, last_positive_timestamp)
                if interval > 0:
                    recent_step_intervals.append(interval)
            last_positive_timestamp = timestamp
            last_positive_heading_radians = heading_radians

        previous_timestamp = timestamp
        previous_heading_radians = heading_radians

    return samples


def fit_normalization(samples: list[Sample]) -> tuple[list[float], list[float]]:
    feature_count = len(samples[0].features)
    means = []
    stds = []
    for index in range(feature_count):
        values = [sample.features[index] for sample in samples]
        mu = mean(values)
        sigma = stddev(values)
        means.append(mu)
        stds.append(sigma if sigma > 1e-9 else 1.0)
    return means, stds


def fit_linear_regression(
    samples: list[Sample],
    *,
    means: list[float],
    stds: list[float],
    epochs: int,
    learning_rate: float,
    l2: float,
) -> tuple[list[float], float]:
    weights = [0.0] * len(samples[0].features)
    bias = 0.917
    best_weights = list(weights)
    best_bias = bias
    best_score = float("inf")
    indexed = list(enumerate(samples))

    for epoch in range(epochs):
        random.shuffle(indexed)
        step_lr = learning_rate / (1.0 + epoch / 500.0)
        for _, sample in indexed:
            x = normalize(sample.features, means, stds)
            prediction = dot(weights, x) + bias
            error = (prediction - sample.target) * sample.weight
            for i, value in enumerate(x):
                weights[i] -= step_lr * (error * value + l2 * weights[i])
            bias -= step_lr * error

        if epoch == 0 or (epoch + 1) % max(1, epochs // 10) == 0 or epoch + 1 == epochs:
            metrics = evaluate(samples, weights, bias, means, stds, 0.832, 0.95)
            print(
                f"    epoch {epoch + 1}/{epochs}: "
                f"mae={metrics['mae']:.4f} "
                f"rmse={metrics['rmse']:.4f} "
                f"r2={metrics['r2']:.4f}"
            )

        metrics = evaluate(samples, weights, bias, means, stds, 0.832, 0.95)
        score = metrics["mae"] + metrics["rmse"]
        if score < best_score:
            best_score = score
            best_weights = list(weights)
            best_bias = bias

    return best_weights, best_bias


def evaluate(
    samples: list[Sample],
    weights: list[float],
    bias: float,
    means: list[float],
    stds: list[float],
    min_length: float,
    max_length: float,
) -> dict[str, float]:
    if not samples:
        return {"samples": 0, "mae": 0.0, "rmse": 0.0, "r2": 0.0}

    predictions = [
        clamp(dot(weights, normalize(sample.features, means, stds)) + bias, min_length, max_length)
        for sample in samples
    ]
    targets = [sample.target for sample in samples]
    errors = [pred - target for pred, target in zip(predictions, targets)]
    mae = sum(abs(error) for error in errors) / len(errors)
    rmse = math.sqrt(sum(error * error for error in errors) / len(errors))
    target_mean = mean(targets)
    ss_tot = sum((target - target_mean) ** 2 for target in targets)
    ss_res = sum(error * error for error in errors)
    r2 = 1.0 - (ss_res / ss_tot) if ss_tot > 1e-9 else 0.0
    return {"samples": len(samples), "mae": mae, "rmse": rmse, "r2": r2}


def normalize(features: list[float], means: list[float], stds: list[float]) -> list[float]:
    return [
        (value - means[index]) / stds[index]
        for index, value in enumerate(features)
    ]


def dot(weights: list[float], features: list[float]) -> float:
    return sum(weight * feature for weight, feature in zip(weights, features))


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def float_or_default(value: str | None, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        return default


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


def heading_delta_degrees(a: float, b: float) -> float:
    delta = abs(a - b)
    normalized = (2 * math.pi) - delta if delta > math.pi else delta
    return normalized * 180.0 / math.pi


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


if __name__ == "__main__":
    main()
