#!/usr/bin/env bash
#
# run_benchmarks.sh
#
# Description:
#   Sends HTTP GETs to a running HTTPResponsivenessServer (started with --collect-benchmarks)
#   then invokes collect_benchmarks.sh on its log.
#
# Prerequisites:
#   1. Build your server:
#        swift build -c release
#
#   2. Start it in the background, redirecting stdout+stderr to a log:
#
#      stdbuf -oL -eL .build/release/HTTPResponsivenessServer \
#      --host 127.0.0.1 \
#      --insecure-port 8080 \
#      --collect-benchmarks \
#      &> server.log
#
# Usage:
#   In the root directory of this App
#     Examples/ping-benchmarks/run_benchmarks.sh \
#       --host 127.0.0.1 \
#       --port 8080 \
#       --endpoint /ping \
#       --samples 100 \
#       --logfile server.log
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
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- sanity check logfile ---
if [[ ! -f "$LOGFILE" ]]; then
  cat <<EOF >&2
ERROR: logfile '$LOGFILE' not found.
Make sure you started the server with:

  stdbuf -oL -eL .build/release/HTTPResponsivenessServer --host $HOST --insecure-port $PORT --collect-benchmarks &> $LOGFILE

EOF
  exit 1
fi

# --- clear out any old measurements ---
: > "$LOGFILE"

echo "→ Sending $SAMPLES requests to http://$HOST:$PORT$ENDPOINT"
for i in $(seq 1 "$SAMPLES"); do
  curl -s "http://$HOST:$PORT$ENDPOINT" > /dev/null
done

# give the server a moment to log
sleep 0.1

# --- wait for exactly SAMPLES log entries ---
echo "→ Waiting up to 5s for $SAMPLES entries in '$LOGFILE' …"
deadline=$((SECONDS + 5))
while (( SECONDS < deadline )); do
  count=$(grep -c "Request handled in" "$LOGFILE" || true)
  if (( count >= SAMPLES )); then
    break
  fi
  sleep 0.1
done

# final check
count=$(grep -c "Request handled in" "$LOGFILE" || true)
if (( count < SAMPLES )); then
  echo "ERROR: only found $count samples in '$LOGFILE' (wanted $SAMPLES)" >&2
  exit 1
fi

echo "→ Collected $count samples, now computing percentiles…"
Examples/ping-benchmarks/collect_benchmarks.sh "$LOGFILE" "$ENDPOINT" "$SAMPLES"
