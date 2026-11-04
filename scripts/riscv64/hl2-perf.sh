#!/bin/sh
# Usage (on the board): hl2-perf.sh <game dir> <label> [delay] [duration]
# Runs hl2-timedemo.sh and, <delay> s after the start, samples the game for <duration> s
# with perf (cpu-clock: hardware-cycle sampling gives no samples on the K1).
DIR=$1; LABEL=$2; DELAY=${3:-45}; DUR=${4:-40}
OUT=$HOME/hl2-bench/$LABEL
~/hl2-timedemo.sh "$DIR" "$LABEL" > /tmp/td-$LABEL.txt 2>&1 &
TD=$!
sleep "$DELAY"
PID=$(pgrep -x hl2_launcher)
[ -n "$PID" ] || { echo "game not running"; wait $TD; cat /tmp/td-$LABEL.txt; exit 1; }
sudo perf record -e cpu-clock -F 999 -p "$PID" -o /tmp/perf-$LABEL.data -- sleep "$DUR" 2>&1 | tail -1
wait $TD; cat /tmp/td-$LABEL.txt
sudo chown $USER /tmp/perf-$LABEL.data; mv /tmp/perf-$LABEL.data "$OUT/perf.data"
perf report -i "$OUT/perf.data" --stdio --no-children --sort comm,dso 2>/dev/null | grep -v '^#' | grep -v '^$' | head -40 > "$OUT/perf-dso.txt"
perf report -i "$OUT/perf.data" --stdio --no-children --sort dso,sym 2>/dev/null | grep -v '^#' | grep -v '^$' | head -60 > "$OUT/perf-sym.txt"
perf report -i "$OUT/perf.data" --stdio --no-children --sort comm 2>/dev/null | grep -v '^#' | grep -v '^$' | head -20 > "$OUT/perf-comm.txt"
