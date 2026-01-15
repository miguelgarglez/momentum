#!/usr/bin/env python3
import csv
import math
import os
import sys
from datetime import datetime

def read_cpu_values(path):
    values = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                values.append(float(row["cpu_percent"]))
            except (KeyError, ValueError):
                continue
    return values

def avg(values):
    return sum(values) / len(values) if values else 0.0

def p95(values):
    if not values:
        return 0.0
    values_sorted = sorted(values)
    idx = max(0, math.ceil(0.95 * len(values_sorted)) - 1)
    return values_sorted[idx]

def main():
    if len(sys.argv) != 2:
        print("Usage: parse_cpu_csv.py <run_root>")
        return 1

    run_root = sys.argv[1]
    scenarios = []
    for entry in os.listdir(run_root):
        path = os.path.join(run_root, entry)
        if os.path.isdir(path):
            cpu_path = os.path.join(path, "cpu.csv")
            if os.path.exists(cpu_path):
                values = read_cpu_values(cpu_path)
                scenarios.append({
                    "name": entry,
                    "avg": avg(values),
                    "p95": p95(values),
                    "count": len(values),
                    "path": path,
                })

    scenarios.sort(key=lambda s: s["avg"], reverse=True)

    summary_path = os.path.join(run_root, "SUMMARY.md")
    with open(summary_path, "w") as f:
        f.write("# CPU Diagnostic Summary\n\n")
        f.write(f"Run: {os.path.basename(run_root)}\n\n")
        f.write("Scenarios ordered by avg CPU (desc):\n\n")
        f.write("| Scenario | Avg CPU % | P95 CPU % | Samples | Artifacts |\n")
        f.write("| --- | ---: | ---: | ---: | --- |\n")
        for s in scenarios:
            avg_cpu = f"{s['avg']:.2f}"
            p95_cpu = f"{s['p95']:.2f}"
            artifacts = os.path.relpath(s["path"], run_root)
            f.write(f"| {s['name']} | {avg_cpu} | {p95_cpu} | {s['count']} | {artifacts} |\n")

    return 0

if __name__ == "__main__":
    sys.exit(main())
