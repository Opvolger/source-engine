#!/bin/sh
# Usage (on the board): hl2-timedemo.sh <game dir> <label> [demo]
#
# Plays <game dir>/hl2/<demo>.dem (default: bench) with `timedemoquit` in the desktop session:
# the engine renders the demo as fast as it can, prints
#   "<frames> frames <secs> seconds <fps> fps (<ms> ms/f) <var> fps variability"
# to the console and exits. The result line is taken from hl2/console.log (-condebug).
# Results and logs: ~/hl2-bench/<label>/.
set -e
DIR=$1; LABEL=$2; DEMO=${3:-bench}
OUT=$HOME/hl2-bench/$LABEL; rm -rf "$OUT"; mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
systemctl --user stop hl2 2>/dev/null || true
rm -f "$DIR/hl2/console.log"
systemd-run --user --unit=hl2 --collect -p WorkingDirectory="$DIR" \
	-E WAYLAND_DISPLAY=wayland-0 -E SDL_VIDEODRIVER=wayland -E XDG_RUNTIME_DIR=/run/user/1000 \
	sh -c "exec ./hl2_launcher -game hl2 -windowed -w 1280 -h 720 -novid -condebug +timedemoquit $DEMO > $OUT/game.log 2>&1" >/dev/null
# wait for the game to exit by itself (max 6 min)
i=0
while systemctl --user is-active -q hl2 && [ $i -lt 360 ]; do sleep 1; i=$((i+1)); done
systemctl --user stop hl2 2>/dev/null || true
cp "$DIR/hl2/console.log" "$OUT/" 2>/dev/null || true
r=$(grep -h "frames .* seconds .* fps" "$OUT/console.log" 2>/dev/null | tail -1)
if [ -n "$r" ]; then echo "$LABEL: $r (wall ${i}s)"; else echo "$LABEL: no timedemo result (wall ${i}s), see $OUT"; exit 1; fi
