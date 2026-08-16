#!/usr/bin/env python3
"""Enforce the FoodMind lightweight JMeter performance policy."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def percentile(values: list[int], percentile_value: float) -> int:
    ordered = sorted(values)
    index = max(0, math.ceil(percentile_value * len(ordered)) - 1)
    return ordered[index]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("jtl", type=Path)
    parser.add_argument("--expected-samples", type=int, default=20)
    parser.add_argument("--max-error-rate", type=float, default=0.0)
    parser.add_argument("--max-p95-ms", type=int, default=2000)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()

    with args.jtl.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != args.expected_samples:
        raise SystemExit(f"JMeter gate failed: expected {args.expected_samples} samples, got {len(rows)}")

    elapsed = [int(row["elapsed"]) for row in rows]
    failures = [row for row in rows if row.get("success", "").lower() != "true"]
    error_rate = len(failures) / len(rows)
    p95_ms = percentile(elapsed, 0.95)
    summary = {
        "samples": len(rows),
        "failures": len(failures),
        "error_rate_percent": round(error_rate * 100, 2),
        "average_ms": round(sum(elapsed) / len(elapsed), 2),
        "min_ms": min(elapsed),
        "max_ms": max(elapsed),
        "p95_ms": p95_ms,
        "policy": {
            "expected_samples": args.expected_samples,
            "max_error_rate_percent": args.max_error_rate * 100,
            "max_p95_ms": args.max_p95_ms,
        },
    }
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))

    if error_rate > args.max_error_rate:
        raise SystemExit(f"JMeter gate failed: error rate {error_rate:.2%} exceeds {args.max_error_rate:.2%}")
    if p95_ms > args.max_p95_ms:
        raise SystemExit(f"JMeter gate failed: p95 {p95_ms} ms exceeds {args.max_p95_ms} ms")
    print("JMeter gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
