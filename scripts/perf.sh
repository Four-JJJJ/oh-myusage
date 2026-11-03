#!/usr/bin/env bash
# Measure the running OhMyUsage app before tuning refresh concurrency, jitter
# or scan budgets. Nothing here changes app state.
#
#   ./scripts/perf.sh sample [seconds] [interval]
#       Samples CPU%, RSS and thread count of the running app with ps and
#       prints min/avg/max. Default: 600s every 5s. CSV lands in
#       $OMU_PERF_DIR (default ~/Library/Caches/OhMyUsage/Perf).
#       OMU_PERF_PID overrides which process is measured.
#
#   ./scripts/perf.sh trace [seconds]
#       Attaches Instruments (Time Profiler + os_signpost) for the given time
#       (default 120s). Open the .trace and filter the "OhMyUsage/Performance"
#       signposts: ProcessStart, LaunchFinished, ProviderFetch <type>,
#       AnalyticsScan <range>.
set -euo pipefail

MODE="${1:-sample}"
OUT_DIR="${OMU_PERF_DIR:-$HOME/Library/Caches/OhMyUsage/Perf}"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

app_pid() {
  pgrep -x OhMyUsage | head -n 1 || true
}

PID="${OMU_PERF_PID:-$(app_pid)}"
if [[ -z "$PID" ]]; then
  echo "OhMyUsage is not running; start it first (installed app or ./scripts/dev.sh run)." >&2
  exit 1
fi

case "$MODE" in
  sample)
    DURATION="${2:-600}"
    INTERVAL="${3:-5}"
    CSV="$OUT_DIR/sample-$STAMP.csv"
    echo "epoch,cpu_percent,rss_kb,threads" > "$CSV"
    echo "Sampling pid $PID for ${DURATION}s every ${INTERVAL}s -> $CSV"
    END=$(( $(date +%s) + DURATION ))
    while (( $(date +%s) < END )); do
      if ! kill -0 "$PID" 2>/dev/null; then
        echo "process exited during sampling" >&2
        break
      fi
      read -r CPU RSS <<<"$(ps -o %cpu=,rss= -p "$PID")"
      THREADS="$(ps -M -p "$PID" | tail -n +2 | wc -l | tr -d ' ')"
      echo "$(date +%s),$CPU,$RSS,$THREADS" >> "$CSV"
      sleep "$INTERVAL"
    done
    awk -F, 'NR > 1 {
        n++; c += $2; r += $3
        if (n == 1 || $2 < cmin) cmin = $2; if ($2 > cmax) cmax = $2
        if (n == 1 || $3 < rmin) rmin = $3; if ($3 > rmax) rmax = $3
      }
      END {
        if (n == 0) { print "no samples"; exit 1 }
        printf "samples=%d\ncpu%% min/avg/max = %.1f / %.2f / %.1f\n", n, cmin, c / n, cmax
        printf "rss MB  min/avg/max = %.1f / %.1f / %.1f\n", rmin / 1024, r / n / 1024, rmax / 1024
      }' "$CSV"
    ;;
  trace)
    DURATION="${2:-120}"
    TRACE="$OUT_DIR/trace-$STAMP.trace"
    echo "Recording pid $PID for ${DURATION}s -> $TRACE"
    xcrun xctrace record \
      --template "Time Profiler" \
      --instrument "os_signpost" \
      --attach "$PID" \
      --time-limit "${DURATION}s" \
      --output "$TRACE"
    echo "Open with: open \"$TRACE\""
    ;;
  *)
    echo "Usage: $0 {sample [seconds] [interval] | trace [seconds]}" >&2
    exit 2
    ;;
esac
