#!/usr/bin/env bash
#
# run_benchmarks.sh
#
# Description:
# Sends HTTP GETs to a running HTTPResponsivenessServer (started with --collect-benchmarks)
# then invokes collect-benchmarks.sh on its log.
#
# Prerequisites:
#   1. Build your server with benchmarking support:
#        swift build -c release
#
#   2. Start it in the background, redirecting stdout+stderr to a log:
#        .build/release/HTTPResponsivenessServer \
#          --host 127.0.0.1 \
#          --insecure-port 8080 \
#          --collect-benchmarks \
#        > server.log 2>&1 &
#
# Usage:
#   In the root directory of this App
#
#   Examples/ping-benchmarks/run_benchmarks.sh \
#     --host 127.0.0.1 \
#     --port 8080 \
#     --endpoint /ping \
#     --samples 100 \
#     --logfile server.log
#

set -euo pipefail

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --host)      HOST="$2";     shift 2 ;;
    --port)      PORT="$2";     shift 2 ;;
    --endpoint)  ENDPOINT="$2"; shift 2 ;;
    --samples)   SAMPLES="$2";  shift 2 ;;
    --logfile)   LOGFILE="$2";  shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo "→ Sending $SAMPLES requests to http://$HOST:$PORT$ENDPOINT"
for i in $(seq 1 "$SAMPLES"); do
  curl -s "http://$HOST:$PORT$ENDPOINT" > /dev/null
done

# give the server a moment to flush
sleep 0.1

# hand off to the collector
Examples/ping-benchmarks/collect_benchmarks.sh "$LOGFILE" "$ENDPOINT" "$SAMPLES"
