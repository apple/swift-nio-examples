#!/usr/bin/env bash
#
# collect_benchmarks.sh
#
# Description:
#   Reads “Request handled in XX ms” lines from a SwiftNIO HTTPResponsivenessServer
#   log file (produced when started with --collect-benchmarks) and computes
#   p0, p25, p50, p75, p90, p99 and p100 statistics.
#   
#   Called from run_benchmarks.sh
#
#

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <LOGFILE> <ENDPOINT> <SAMPLES>" >&2
  exit 1
fi

LOGFILE="$1"
ENDPOINT="$2"
SAMPLES="$3"

# extract exactly the first N timings
mapfile -t times < <(
  grep "Request handled in" "$LOGFILE" \
    | head -n "$SAMPLES" \
    | sed -E 's/.*Request handled in ([0-9]+(\.[0-9]+)?) ms/\1/'
)

if [ "${#times[@]}" -lt "$SAMPLES" ]; then
  echo "ERROR: only found ${#times[@]} samples in $LOGFILE" >&2
  exit 1
fi

# compute percentiles in Python
python3 - "$ENDPOINT" "${times[@]}" << 'PYCODE'
import sys, numpy as np

# parse float timings from command-line args (skip the first entry which is '-')
data = [float(x) for x in sys.argv[2:]]
arr  = np.array(data)

# compute percentiles
pcts = [ np.percentile(arr, p) for p in (0, 25, 50, 75, 90, 99, 100) ]
samples = arr.size
metric = sys.argv[1]

# nice Unicode table
print("╒═══════════════════════╤══════════╤══════════╤══════════╤══════════╤══════════╤══════════╤══════════╤══════════╕")
print("│ Metric                │     p0   │    p25   │    p50   │    p75   │    p90   │    p99   │   p100   │ Samples  │")
print("╞═══════════════════════╪══════════╪══════════╪══════════╪══════════╪══════════╪══════════╪══════════╪══════════╡")
print(f"│ {metric:20s}  │ " +
      " │ ".join(f"{v:7.6f}" for v in pcts) +
      f" │ {samples:7d}  │")
print("╘═══════════════════════╧══════════╧══════════╧══════════╧══════════╧══════════╧══════════╧══════════╧══════════╛")
PYCODE
