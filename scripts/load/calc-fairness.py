#!/usr/bin/env python3

import argparse
import json
import math
import sys
from typing import Any


def _to_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def compute_fairness(distribution: list[dict[str, Any]]) -> dict[str, Any]:
    values = [_to_float(item.get("value", 0)) for item in distribution]
    positive_values = [v for v in values if v > 0]

    total = sum(values)
    n = len(values)
    active_n = len(positive_values)
    mean = (total / n) if n else 0.0

    if n == 0:
        stddev = 0.0
        min_value = 0.0
        max_value = 0.0
        jain_index = 0.0
        fairness_score = 0.0
        skew_ratio = 0.0
    else:
        variance = sum((v - mean) ** 2 for v in values) / n
        stddev = math.sqrt(variance)
        min_value = min(values)
        max_value = max(values)

        square_sum = sum(values)
        sum_squares = sum(v * v for v in values)
        if sum_squares == 0:
            jain_index = 0.0
        else:
            jain_index = (square_sum * square_sum) / (n * sum_squares)

        # Main fairness score for reports, bounded to [0, 1].
        fairness_score = max(0.0, min(1.0, jain_index))

        if min_value <= 0:
            skew_ratio = float("inf") if max_value > 0 else 0.0
        else:
            skew_ratio = max_value / min_value

    cv = (stddev / mean) if mean > 0 else 0.0

    return {
        "consumer_count": n,
        "active_consumer_count": active_n,
        "total_messages": total,
        "mean_messages": mean,
        "stddev_messages": stddev,
        "coefficient_of_variation": cv,
        "min_messages": min_value,
        "max_messages": max_value,
        "skew_ratio_max_to_min": skew_ratio,
        "jain_fairness_index": jain_index,
        "fairness_score": fairness_score,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Compute per-consumer fairness metrics")
    parser.add_argument("--input", required=True, help="Path to distribution JSON file")
    parser.add_argument(
        "--min-fairness",
        type=float,
        default=None,
        help="Optional threshold for pass/fail annotation",
    )
    args = parser.parse_args()

    try:
        with open(args.input, "r", encoding="utf-8") as f:
            distribution = json.load(f)
    except OSError as exc:
        print(f"ERROR: cannot read input file: {exc}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON input: {exc}", file=sys.stderr)
        return 2

    if not isinstance(distribution, list):
        print("ERROR: input must be a JSON array of {pod,value} objects", file=sys.stderr)
        return 2

    result = compute_fairness(distribution)

    if args.min_fairness is not None:
        result["min_fairness_threshold"] = args.min_fairness
        result["fairness_pass"] = result["fairness_score"] >= args.min_fairness

    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
