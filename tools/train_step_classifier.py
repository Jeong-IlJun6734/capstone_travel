#!/usr/bin/env python3
"""Train the indoor step classifier from exported IMU logs.

Usage:
  py tools/train_step_classifier.py --input-dir "C:\\path\\to\\logs" --output models/step_classifier.json

The script accepts either a manually labeled column or the app's inferred
`imu_step_detected` fallback label.
"""

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
    label: int
    weight: float
    file_name: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, help="Directory containing IMU CSV logs.")
    parser.add_argument("--output", required=True, help="Output JSON model path.")
    parser.add_argument(
        "--label-column",
        default="manual_step_label",
        help="Preferred label column. Falls back to imu_step_detected when absent.",
    )
    parser.add_argument(
        "--test-split",
        type=float,
        default=0.2,
        help="Fraction of log files reserved for validation.",
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=1800,
        help="Maximum SGD epochs.",
    )
    parser.add_argument(
        "--learning-rate",
        type=float,
        default=0.035,
        help="Initial SGD learning rate.",
    )
    parser.add_argument(
        "--l2",
        type=float,
        default=0.0004,
        help="L2 regularization strength.",
    )
    parser.add_argument(
        "--target-specificity",
        type=float,
        default=0.7,
        help="Minimum validation specificity for threshold selection.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=7,
        help="Deterministic random seed.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    random.seed(args.seed)

    input_dir = Path(args.input_dir)
    csv_paths = sorted(path for path in input_dir.rglob("*.csv") if path.is_file())
    if not csv_paths:
        raise SystemExit(f"No CSV logs found in {input_dir}")

    print(f"[1/6] Found {len(csv_paths)} CSV file(s) in {input_dir}")
    train_files, val_files = split_files(csv_paths, args.test_split, args.seed)
    print(
        f"[2/6] Split files into {len(train_files)} train and {len(val_files)} validation file(s)"
    )
    print("[3/6] Loading training samples...")
    train_samples = load_samples(train_files, args.label_column)
    print("[4/6] Loading validation samples...")
    val_samples = load_samples(val_files, args.label_column)
    if not train_samples:
        raise SystemExit("No training samples were produced from the input logs.")

    print(f"[5/6] Fitting model on {len(train_samples)} training samples...")
    means, stds = fit_normalization(train_samples)
    class_weights = compute_class_weights(train_samples)
    weights, bias = fit_logistic_regression(
        train_samples,
        means=means,
        stds=stds,
        class_weights=class_weights,
        epochs=args.epochs,
        learning_rate=args.learning_rate,
        l2=args.l2,
    )

    print("[6/6] Evaluating and selecting threshold...")
    train_metrics = evaluate(train_samples, weights, bias, means, stds, 0.5)
    val_threshold, val_metrics = select_threshold(
        val_samples,
        weights,
        bias,
        means,
        stds,
        target_specificity=args.target_specificity,
    )
    val_metrics = evaluate(val_samples, weights, bias, means, stds, val_threshold)

    output = {
        "model_type": "enhanced_logistic_regression_sgd_v2",
        "feature_names": FEATURE_NAMES,
        "weights": weights,
        "bias": bias,
        "decision_threshold": val_threshold,
        "normalization": {
            "means": means,
            "stds": stds,
        },
        "metrics": {
            "train": train_metrics,
            "validation": val_metrics,
        },
        "label_meaning": {
            "0": "no_step",
            "1": "step",
        },
        "selected_hyperparameters": {
            "epochs": args.epochs,
            "learning_rate": args.learning_rate,
            "l2": args.l2,
            "threshold": val_threshold,
            "target_specificity": args.target_specificity,
            "validation_balanced_accuracy": val_metrics["balanced_accuracy"],
            "validation_f1": val_metrics["f1"],
            "validation_specificity": val_metrics["specificity"],
        },
        "training_summary": {
            "files": [path.name for path in csv_paths],
            "train_files": [path.name for path in train_files],
            "validation_files": [path.name for path in val_files],
            "train_samples": len(train_samples),
            "validation_samples": len(val_samples),
            "label_column": args.label_column,
            "positive_samples": sum(sample.label for sample in train_samples + val_samples),
            "negative_samples": sum(1 - sample.label for sample in train_samples + val_samples),
        },
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"Wrote model to {output_path}")
    print(f"Validation balanced accuracy: {val_metrics['balanced_accuracy']:.4f}")
    print(f"Validation F1: {val_metrics['f1']:.4f}")


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


def load_samples(paths: Iterable[Path], label_column: str) -> list[Sample]:
    samples: list[Sample] = []
    paths = list(paths)
    for index, path in enumerate(paths, start=1):
        print(f"  - [{index}/{len(paths)}] Parsing {path.name}")
        samples.extend(load_samples_from_file(path, label_column))
        print(f"    -> cumulative samples: {len(samples)}")
    return samples


def load_samples_from_file(path: Path, label_column: str) -> list[Sample]:
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
        heading_degrees = float_or_default(row.get("heading_degrees"))
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
        filtered_to_user_accel_ratio = (
            filtered_accel / max(user_accel, 0.05)
        )
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

        label = resolved_label(row, label_column)
        confidence = float_or_default(row.get("step_confidence"), 0.5)
        source = (row.get("step_source") or "").strip()
        weight = sample_weight(source, confidence, label)
        samples.append(
            Sample(
                features=features,
                label=label,
                weight=weight,
                file_name=path.name,
            )
        )

        user_buffer.append(user_accel)
        gyro_buffer.append(gyro)
        heading_change_buffer.append(heading_change_degrees)
        if label == 1:
            if last_positive_timestamp is not None:
                interval = seconds_between(timestamp, last_positive_timestamp)
                if interval > 0:
                    recent_step_intervals.append(interval)
            last_positive_timestamp = timestamp
            last_positive_heading_radians = heading_radians

        previous_timestamp = timestamp
        previous_heading_radians = heading_radians

    return samples


def resolved_label(row: dict[str, str], preferred: str) -> int:
    for key in (preferred, "manual_step_label", "true_step_label", "imu_step_detected"):
        value = row.get(key)
        if value is None or value == "":
            continue
        lowered = value.strip().lower()
        if lowered in {"1", "true", "yes", "step"}:
            return 1
        if lowered in {"0", "false", "no", "n", "no_step", "none"}:
            return 0
    return 0


def sample_weight(source: str, confidence: float, label: int) -> float:
    base = 0.55 + 0.9 * clamp01(confidence)
    source_lower = source.lower()
    if "learned classifier" in source_lower:
        base += 0.15
    elif "threshold gate" in source_lower:
        base -= 0.15
    elif "motion gate" in source_lower:
        base -= 0.05
    elif "heuristic" in source_lower:
        base -= 0.1
    if label == 0:
        base *= 0.85
    return max(0.2, min(base, 1.75))


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


def compute_class_weights(samples: list[Sample]) -> tuple[float, float]:
    positive = sum(sample.label for sample in samples)
    negative = len(samples) - positive
    if positive == 0 or negative == 0:
        return 1.0, 1.0
    total = len(samples)
    return total / (2.0 * negative), total / (2.0 * positive)


def fit_logistic_regression(
    samples: list[Sample],
    *,
    means: list[float],
    stds: list[float],
    class_weights: tuple[float, float],
    epochs: int,
    learning_rate: float,
    l2: float,
) -> tuple[list[float], float]:
    weights = [0.0] * len(samples[0].features)
    bias = 0.0
    best_weights = list(weights)
    best_bias = bias
    best_score = float("-inf")

    positive_weight, negative_weight = class_weights
    indexed = list(enumerate(samples))

    for epoch in range(epochs):
        random.shuffle(indexed)
        step_lr = learning_rate / (1.0 + epoch / 450.0)
        for _, sample in indexed:
            x = normalize(sample.features, means, stds)
            target = float(sample.label)
            class_weight = positive_weight if sample.label == 1 else negative_weight
            margin = dot(weights, x) + bias
            prediction = sigmoid(margin)
            error = (prediction - target) * sample.weight * class_weight
            for i, value in enumerate(x):
                weights[i] -= step_lr * (error * value + l2 * weights[i])
            bias -= step_lr * error

        if epoch == 0 or (epoch + 1) % max(1, epochs // 10) == 0 or epoch + 1 == epochs:
            metrics = evaluate(samples, weights, bias, means, stds, 0.5)
            print(
                f"    epoch {epoch + 1}/{epochs}: "
                f"balanced_accuracy={metrics['balanced_accuracy']:.4f} "
                f"f1={metrics['f1']:.4f} "
                f"precision={metrics['precision']:.4f} "
                f"recall={metrics['recall']:.4f}"
            )

        train_metrics = evaluate(samples, weights, bias, means, stds, 0.5)
        score = train_metrics["balanced_accuracy"]
        if score > best_score:
            best_score = score
            best_weights = list(weights)
            best_bias = bias

    return best_weights, best_bias


def select_threshold(
    samples: list[Sample],
    weights: list[float],
    bias: float,
    means: list[float],
    stds: list[float],
    *,
    target_specificity: float,
) -> tuple[float, dict[str, float]]:
    if not samples:
        return 0.5, {
            "accuracy": 0.0,
            "precision": 0.0,
            "recall": 0.0,
            "specificity": 0.0,
            "balanced_accuracy": 0.0,
            "f1": 0.0,
        }

    print("    selecting decision threshold...")
    best_threshold = 0.5
    best_metrics: dict[str, float] | None = None
    best_score = float("-inf")
    for threshold in [i / 100.0 for i in range(20, 81)]:
        metrics = evaluate(samples, weights, bias, means, stds, threshold)
        meets_specificity = metrics["specificity"] >= target_specificity
        score = metrics["balanced_accuracy"] + (0.01 if meets_specificity else -0.05)
        if score > best_score:
            best_score = score
            best_threshold = threshold
            best_metrics = metrics

    if best_metrics is not None:
        print(
            f"    selected threshold={best_threshold:.2f} "
            f"balanced_accuracy={best_metrics['balanced_accuracy']:.4f} "
            f"specificity={best_metrics['specificity']:.4f}"
        )

    return best_threshold, best_metrics or evaluate(samples, weights, bias, means, stds, best_threshold)


def evaluate(
    samples: list[Sample],
    weights: list[float],
    bias: float,
    means: list[float],
    stds: list[float],
    threshold: float,
) -> dict[str, float]:
    if not samples:
        return {
            "samples": 0,
            "true_positive": 0,
            "true_negative": 0,
            "false_positive": 0,
            "false_negative": 0,
            "accuracy": 0.0,
            "precision": 0.0,
            "recall": 0.0,
            "specificity": 0.0,
            "balanced_accuracy": 0.0,
            "f1": 0.0,
        }

    tp = tn = fp = fn = 0
    for sample in samples:
        prediction = sigmoid(dot(weights, normalize(sample.features, means, stds)) + bias)
        label = 1 if prediction >= threshold else 0
        if label == 1 and sample.label == 1:
            tp += 1
        elif label == 1 and sample.label == 0:
            fp += 1
        elif label == 0 and sample.label == 0:
            tn += 1
        else:
            fn += 1

    accuracy = (tp + tn) / len(samples)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    specificity = tn / (tn + fp) if tn + fp else 0.0
    balanced_accuracy = (recall + specificity) / 2.0
    f1 = (2.0 * precision * recall / (precision + recall)) if precision + recall else 0.0
    return {
        "samples": len(samples),
        "true_positive": tp,
        "true_negative": tn,
        "false_positive": fp,
        "false_negative": fn,
        "accuracy": accuracy,
        "precision": precision,
        "recall": recall,
        "specificity": specificity,
        "balanced_accuracy": balanced_accuracy,
        "f1": f1,
    }


def normalize(features: list[float], means: list[float], stds: list[float]) -> list[float]:
    return [
        (value - means[index]) / stds[index]
        for index, value in enumerate(features)
    ]


def dot(weights: list[float], features: list[float]) -> float:
    return sum(weight * feature for weight, feature in zip(weights, features))


def sigmoid(value: float) -> float:
    if value >= 0:
        exp_value = math.exp(-value)
        return 1.0 / (1.0 + exp_value)
    exp_value = math.exp(value)
    return exp_value / (1.0 + exp_value)


def float_or_default(value: str | None, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    lowered = value.strip().lower()
    if lowered == "nan":
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


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


if __name__ == "__main__":
    main()
