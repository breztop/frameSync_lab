"""Independently audit a real export; does not launch Godot."""
import csv
import json
import math
import sys
from pathlib import Path


def summarize(values):
    values = sorted(values)
    count = len(values)
    result = {"interval_count": count}
    for percentile in (50, 95, 99):
        result[f"p{percentile}_ms"] = (
            values[math.ceil(count * percentile / 100) - 1] / 1000 if count else None
        )
    result["max_ms"] = values[-1] / 1000 if count else None
    result["average_update_fps"] = count * 1_000_000 / sum(values) if count else None
    for label, threshold in (("33_3", 33300), ("100", 100000), ("200", 200000)):
        result[f"over_{label}_ms"] = sum(value > threshold for value in values)
    if count:
        result["duration_seconds"] = sum(values) / 1_000_000
    return result


def require(condition, message):
    if not condition:
        raise ValueError(message)


def compare(actual, reported, label):
    for key, expected in actual.items():
        value = reported.get(key)
        matches = value is None if expected is None else (
            isinstance(value, (int, float))
            and math.isclose(value, expected, rel_tol=1e-8, abs_tol=1e-8)
        )
        require(matches, f"{label}.{key}: reported={value}, recomputed={expected}")


def audit(folder):
    report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
    all_values, stable_values, segments = [], [], {}
    events = {event["segment"]: event for event in report["events"]}
    previous = None
    start = None
    count = 0
    with (folder / "frames.csv").open(encoding="utf-8-sig", newline="") as stream:
        for count, row in enumerate(csv.DictReader(stream), 1):
            ticks = int(row["ticks_usec"])
            elapsed = int(row["elapsed_usec"])
            gap = int(row["interval_usec"])
            segment = int(row["segment"])
            stable = int(row["stable_sample"])
            require(row["round_id"] == report["round_id"], "Mixed round IDs")
            require(int(row["update_number"]) == count, "Nonconsecutive update number")
            require(elapsed >= 0, "Negative elapsed time")
            if start is None:
                start = ticks - elapsed
            require(ticks - elapsed == start, "Inconsistent time origin")
            require(segment in events, "Missing segment configuration event")
            require(gap == (ticks - previous if previous is not None else 0), "Incorrect interval")
            require(previous is None or ticks >= previous, "Monotonic time went backwards")
            expected_stable = int(previous is not None and gap > 0
                                  and previous >= events[segment]["excluded_until_usec"])
            require(stable == expected_stable, "Incorrect transition exclusion")
            if gap > 0:
                all_values.append(gap)
            if stable:
                stable_values.append(gap)
                segments.setdefault(str(segment), []).append(gap)
            previous = ticks
    require(count == report["sample_count"], "Incorrect sample count")
    compare(summarize(all_values), report["all_intervals"], "all_intervals")
    stable_summary = summarize(stable_values)
    compare(stable_summary, report["stable_intervals"], "stable_intervals")
    require(set(segments) == set(report["stable_by_segment"]), "Segment statistics mismatch")
    for segment, values in segments.items():
        compare(summarize(values), report["stable_by_segment"][segment], f"segment {segment}")
    print(f"PASS: {count} samples; CSV consistency and report statistics agree.")
    print(json.dumps(stable_summary, ensure_ascii=False, indent=2))
    screening = (stable_summary.get("duration_seconds", 0) >= 60
                 and 59 <= (stable_summary["average_update_fps"] or 0) <= 61
                 and (stable_summary["p99_ms"] or 0) <= 33.3
                 and stable_summary["over_100_ms"] == 0)
    print("Initial stability screening:", "PASS" if screening else "NOT MET")
    print("Check events and per-segment configuration; this is not display or video validation.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tools/check_export.py EXPORT_DIRECTORY")
    try:
        audit(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"FAIL: {error}") from error
