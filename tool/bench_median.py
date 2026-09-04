# tool/bench_median.py

"""Run the bench suite repeatedly and report per-report medians.

Benchmark timings on shared or frequency-scaled machines swing widely
between runs, so a single `make bench` round is easy to misread. This
builds each bench once, runs it ROUNDS times, and prints the median
runtime of every report line.

Usage: python3 tool/bench_median.py [rounds] [bench_file ...]
"""

import re
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REPORT = re.compile(r"^(.*?)\s+[\d.]+[Mk]? \(\s*([\d.]+)\s*(ns|µs|ms|s)\)")
UNITS = {"ns": 1.0, "µs": 1e3, "ms": 1e6, "s": 1e9}


def collect(binary, rounds):
    sections = []
    samples = {}

    for _ in range(rounds):
        out = subprocess.run(
            [binary], capture_output=True, text=True, check=True
        ).stdout
        section = ""
        for line in out.splitlines():
            match = REPORT.match(line.strip())
            if match:
                key = (section, match.group(1).strip())
                if key not in samples:
                    samples[key] = []
                    sections.append(key)
                samples[key].append(float(match.group(2)) * UNITS[match.group(3)])
            elif line.strip():
                section = line.strip()

    return sections, samples


def format_ns(value):
    for unit, scale in (("s", 1e9), ("ms", 1e6), ("µs", 1e3)):
        if value >= scale:
            return f"{value / scale:8.2f}{unit}"
    return f"{value:8.0f}ns"


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    benches = [Path(name) for name in sys.argv[2:]] or sorted(
        ROOT.glob("bench/*_bench.cr")
    )

    with tempfile.TemporaryDirectory() as tmp:
        for bench in benches:
            binary = Path(tmp) / bench.stem
            subprocess.run(
                ["crystal", "build", "--release", str(bench), "-o", str(binary)],
                cwd=ROOT, check=True,
            )

            sections, samples = collect(str(binary), rounds)

            print(f"== {bench.name} (median of {rounds}) ==")
            section = None
            for sec, name in sections:
                if sec != section:
                    print(f"\n{sec}")
                    section = sec
                values = samples[(sec, name)]
                spread = (max(values) - min(values)) / statistics.median(values)
                print(
                    f"  {name:>14} {format_ns(statistics.median(values))}"
                    f"   (spread {spread:.0%})"
                )
            print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
