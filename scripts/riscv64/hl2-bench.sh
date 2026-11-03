#!/bin/sh
# Usage: hl2-bench.sh <game dir> <label> [map]
# Starts HL2 in the Wayland session for 100 s with Mesa's HUD dumping fps, then prints the
# average fps of the last 40 s (first ~60 s = loading + scripted intro of the map). Player stands still at the map spawn.
set -e
DIR=$1; LABEL=$2; MAP=${3:-d1_canals_01}
OUT=$HOME/hl2-bench/$LABEL; rm -rf "$OUT"; mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
systemctl --user stop hl2 2>/dev/null || true
systemd-run --user --unit=hl2 --collect -p WorkingDirectory="$DIR" \
	-E WAYLAND_DISPLAY=wayland-0 -E SDL_VIDEODRIVER=wayland -E XDG_RUNTIME_DIR=/run/user/1000 \
	-E GALLIUM_HUD=fps -E GALLIUM_HUD_PERIOD=1 -E GALLIUM_HUD_DUMP_DIR="$OUT" \
	sh -c "exec ./hl2_launcher -game hl2 -windowed -w 1280 -h 720 -novid +map $MAP > $OUT/game.log 2>&1" >/dev/null
sleep 100
systemctl --user stop hl2 || true
f=$(ls "$OUT" | grep -i fps | head -1)
[ -n "$f" ] || { echo "no fps dump in $OUT"; ls "$OUT"; exit 1; }
tail -n 40 "$OUT/$f" | awk -v l="$LABEL" '{v=$NF; s+=v; n++; if(min==""||v<min)min=v; if(v>max)max=v} END {printf "%s: avg %.1f fps (min %.1f, max %.1f, %d samples)\n", l, s/n, min, max, n}'
