# Port to RISC-V

> **For a new Claude session:** read this whole file first. It is the single source of
> truth for this project. Continue from the first unchecked item under **Status / next steps**,
> and update this file (status, findings, commands that worked) as you make progress, so the
> next session can pick up where you left off.

## Goal and current state

Run Half-Life 2 on a **Milk-V Jupiter (SpacemiT K1, RV64GCV)** using the engine built from this
repository (fork of `nillerusr/source-engine`, TF2 2018 leak based, **waf** build system).

| Stage | What | State (2026-11-04, end of session 2) |
| --- | --- | --- |
| 1 | Build + play locally on the x86_64 laptop with the Steam game data | **Done** — plays fine |
| 2 | Cross-compile for riscv64 (code changes + build environment) | **Done** |
| 3 | Run on the real board | **Done** — HL2 plays on the Jupiter (~52 fps timedemo, 1280x720) |
| 4 | Performance: RVV (vector) build | **Done, no gain** — RVV build works but is not faster; the game is CPU-bound elsewhere |
| 5 | Measure the bottleneck | **Done**: perf built + installed; main thread ~100% (engine/client), render thread ~87% (shaderapi/materialsystem), Mesa threads ~70% of a core |
| 6 | Vulkan via DXVK-native | **Done, works**: HL2 runs on the board with DXVK 3.1.1 + RADV, **57–59 fps vs 51–52 with ToGL (+12%)**; laptop 1004 vs 725 fps |

**Quick start for a new session:**
1. Read this file. Board: `ssh 192.168.2.32` (check `milkv-tools/power.sh state` if it does not answer).
2. Build for the board: `scripts/riscv64/build.sh` (plain) or
   `MARCH=rv64gcv_zvl256b_zba_zbb_zbs VARIANT=rvv scripts/riscv64/build.sh` (vector), ~22 min each.
3. Deploy with rsync (stage 3) — and **verify** with `sha256sum` that the board has the new binaries.
4. Measure with `hl2-timedemo.sh` (stage 4); the user can also start the game from the board's app menu.
5. DXVK (Vulkan) build: `scripts/dxvk/build.sh ../dxvk riscv64` (once), then
   `VARIANT=dxvk scripts/riscv64/build.sh --use-dxvk` → `install-riscv64-dxvk/` → board `~/games/hl2-source-dxvk/`
   (stage 6). Profile with `hl2-perf.sh` (stage 5).
6. **Next session:** user tests the DXVK build ("Half-Life 2 (RISC-V DXVK Vulkan)" in the app menu), then pick
   from **Status / next steps**. The main game thread is the bottleneck in both renderers. Ask the user before
   installing anything on the laptop or the board.

## Git

Branch **`feature/riscv64-support`** (local, not pushed), on top of `master` (`ed8209cc`):

| Commit | What |
| --- | --- |
| `e39e05aa` | togl: fix crash on startup under Wayland |
| `8ba18ef0` | engine, gameui: use system jpeglib headers on Linux |
| `958b18df` | Add riscv64 (RV64GC) Linux support |
| `e41f0fcb` | scripts/riscv64: container-based cross build for riscv64 |
| `0a94226b` | riscv64: support RVV builds (MARCH variant), avoid vector faults on the K1 |
| `8d8a1025` | scripts/riscv64: benchmark helpers for the board (`hl2-timedemo.sh`, `hl2-bench.sh`) |
| `5d8f3a65` | Add DXVK-native (D3D9 on Vulkan) as an alternative to ToGL on Linux (`--use-dxvk`) |
| `1cbdd3f6` | scripts: DXVK-native build container, riscv64 dxvk variant, perf helper (`hl2-perf.sh`) |

All code changes are committed; the working tree is clean apart from this file.
This file (`port-to-riscv.md`) is intentionally **not committed**.

## Machines

### Laptop (build host)

- Fedora 44, x86_64, GCC 16.2.1 (no clang), Python 3, podman 5.8, KDE Plasma on Wayland.
- Repo: `/home/opvolger/code/source-engine`. Submodules (`ivp`, `lib`, `thirdparty`) are initialized.
- Claude has **no sudo** (password needed): when a package is needed, ask the user with the exact
  `sudo dnf install ...` command.
- Installed for this project (by the user): `freetype-devel fontconfig-devel libjpeg-turbo-devel
  libpng-devel libedit-devel opus-devel` (on top of the already present `sdl2-compat-devel`,
  `openal-soft-devel`, `bzip2-devel`, `libcurl-devel`, `zlib-ng-compat-devel`), and
  `qemu-user-static-riscv` (binfmt registered; not needed so far because the board is available).
- Fedora's `gcc-riscv64-linux-gnu` has no glibc/sysroot (kernel-only) → not usable for this; the
  cross build runs in a Debian container instead (stage 2).
- Pulling from docker.io fails with `invalid username/password` (stale registry login on this machine).
  Work-around: `echo '{}' > /tmp/empty-auth.json; REGISTRY_AUTH_FILE=/tmp/empty-auth.json podman build ...`
  (anonymous pull).

### Half-Life 2 game data (Steam, on the laptop)

- `~/.local/share/Steam/steamapps/common/Half-Life 2/` (`hl2/` 3.6 GB, `platform/` 13 MB).
- **The Steam beta branch must be `steam_legacy`** (pre-20th-anniversary build). The current Steam
  release (Nov 2024 anniversary update) has new shaders that do not match this 2018 engine: all UI
  text renders as white blocks (see Problems). The legacy layout has no `hl2_complete/`.
- Never write into the Steam install: game dirs link or copy the data.

### Milk-V Jupiter (target board)

Reference for board handling: `/home/opvolger/code/linux-kernel-jupiter-1/milk-v-testing.md`
(the user's kernel work for this board, AMD GPU over PCIe) and its helper scripts in
`/home/opvolger/code/linux-kernel-jupiter-1/milkv-tools/`.

- Access: `ssh 192.168.2.32` (user `opvolger`, key auth; the milkv-tools use passwordless `sudo`).
- Power: Home Assistant plug: `milkv-tools/power.sh on|off|state`. **Shut down cleanly first**
  (`ssh 192.168.2.32 sudo poweroff`) before `power.sh off` — a hard power cut has corrupted dpkg files.
  After `power.sh on`, ssh is up after ~80 s. (2026-11-03: the plug itself had been unplugged; the
  user plugged it in.)
- Serial console: `picocom --baud 115200 /dev/ttyUSB0` (or `milkv-tools/ser.py`).
- OS: **Debian 13 (trixie)**, glibc 2.41, kernel `7.3.0-k1-amdgpu-debian` (custom, from the kernel repo).
- CPU: 8 cores, ISA `rv64imafdcv_zicbom_zicbop_zicboz_zicntr_zicond_zicsr_zifencei_zihintpause_zihpm_
  zaamo_zalrsc_zfh_zfhmin_zca_zcd_zba_zbb_zbc_zbs_zkt_zve32f_zve32x_zve64d_zve64f_zve64x_zvfh_zvfhmin_
  zvkt_sscofpmf_sstc_svinval_svnapot_svpbmt` → **RVV 1.0 available**, no Zacas (no 128-bit CAS).
  RAM 6.7 GiB, rootfs 52 GB.
- GPU: **AMD Radeon R9 290/390 (Hawaii) on PCIe**, `amdgpu` + Mesa 25.0.7 radeonsi → desktop OpenGL 4.6,
  so the normal `togl` backend is used (not `togles`). KDE Plasma 6 on Wayland (`wayland-0`) + SDDM,
  user session auto-logged-in on tty2. GPU/VRAM access depends on the kernel patches in the kernel repo
  (uncached VRAM BAR, unaligned-access emulation); if the game ever shows geometry glitches, suspect that
  layer first.
- Runtime libs (already installed): libsdl2-2.0-0 2.32.4, libopenal1, libjpeg62-turbo, libpng16-16t64,
  libcurl4t64, libfreetype6, libfontconfig1, libedit2, libopus0, libatomic1, Mesa 25.0.7.
- **Do not install or run Steam on the board** (x86 emulation, extremely slow). Not needed: the engine
  builds its own `libsteam_api.so` stub, and the game data is copied from the laptop.
- Screenshots of the board desktop: use spectacle on the board (see stage 3). The HDMI capture
  (`milkv-tools/screenshot.sh`, UGREEN device) only returned green noise on 2026-11-03.

## Stage 1 — local x86_64 build (done)

```bash
git submodule update --init --recursive                 # ivp, lib, thirdparty
./waf configure -T release --build-games=hl2 --prefix=$HOME/games/hl2-source
./waf build                                             # ~2.5 min, GCC 16.2.1, no changes needed
./waf install                                           # -> ~/games/hl2-source

# Game dir: link read-only data from Steam, keep writable dirs local
S=~/.local/share/Steam/steamapps/common/"Half-Life 2"; D=~/games/hl2-source
find "$D" -xtype l -delete                              # drop dangling links (e.g. after a branch switch)
cd "$D/hl2"
for f in "$S"/hl2/*; do n=$(basename "$f"); case "$n" in bin|cfg|save) continue;; esac; ln -sfn "$f" "$n"; done
cp -r "$S/hl2/cfg/." cfg/; mkdir -p save                # writable copies
mkdir -p "$D/platform"; for f in "$S"/platform/*; do ln -sfn "$f" "$D/platform/$(basename "$f")"; done
rm -f "$D/hl2/glshaders.cfg"                            # GL program cache; delete after changing game data
# hl2/bin is our own build (libclient.so / libserver.so); Steam's hl2/bin is NOT linked.
```

- 64-bit (amd64) is the waf default; do not pass `-4/--32bits`. Linux has no prebuilt libs in `lib/`
  (only `android`, `win32`), so all dependencies come from the system (pkg-config checks in `wscript`
  ~lines 389-405).
- Start: `~/games/hl2-source/run-hl2.sh [args]` (`cd` + `exec ./hl2_launcher -game hl2 "$@"`), e.g.
  `run-hl2.sh -windowed -w 1600 -h 900 -novid +map d1_canals_01` to skip the intro.
- Only one instance can run at a time (`/tmp/source_engine_*.lock`).
- Verified by the user: plays fine (sound, input, saving, map transitions).

## Stage 2 — riscv64 cross-compile (done)

### Build environment

- `scripts/riscv64/Containerfile`: **Debian 13 trixie** (same release as the board, so library sonames
  match, e.g. `libjpeg.so.62`; an Ubuntu 24.04 image would have linked `libjpeg.so.8`), riscv64
  multiarch dev packages, `crossbuild-essential-riscv64` (GCC 14.2), SIMDe 0.8.2, `python-is-python3`
  (waf's shebang wants `python`).
- `scripts/riscv64/build.sh [extra configure args]`: runs `waf configure/build/install` in the container
  → `build-riscv64/` and `install-riscv64/` (both git-ignored). Uses `WAFLOCK=.lock-waf_riscv64`, so the
  native `./build` is left alone. A full cross build takes **~22 min**.

```bash
podman build -t source-engine-riscv64 -f scripts/riscv64/Containerfile scripts/riscv64   # once
scripts/riscv64/build.sh                                                                  # -> install-riscv64/
```

### Code changes (commit `958b18df`)

- `public/tier0/platform.h`: new `PLATFORM_RISCV64`; handled next to ARM in `PLATFORM_64BITS`,
  `DebuggerBreak` (BSD/OSX branch), `SetupFPUControlWord` (no-op), little-endian, `Plat_Rdtsc`
  (`clock_gettime`).
- SIMD: new `common/sse2simde.h` → SIMDe with `SIMDE_ENABLE_NATIVE_ALIASES`, so the SSE intrinsics work
  unchanged (like `common/sse2neon.h` on ARM). Included from `public/mathlib/ssemath.h`,
  `public/mathlib/vector4d.h`, `mathlib/sse.cpp`; `sse.cpp` takes the non-inline-asm paths.
- `public/mathlib/mathlib.h`: `RoundFloatToInt` / `RoundFloatToUnsignedLong` via `lrintf` / `llrintf`
  (round-to-nearest-even like `cvtss2si`; ARM uses `(int)(f + 0.5f)`).
- `public/materialsystem/imesh.h`: intrinsics paths instead of x86 MMX inline asm (`FastVertex`,
  `Fast4VerticesSSE`).
- `public/tier0/tslist.h`: the lock-free list needs a 128-bit CAS. RISC-V has no
  `__sync_bool_compare_and_swap_16` (no Zacas) → `__atomic_compare_exchange_n` on 16 bytes, which
  libatomic implements with a lock (correct, a bit slower).
- `tier0/cpu.cpp` (no cpuid, arch "riscv64", vendor "RISC-V"), `tier0/cpu_posix.cpp`,
  `tier1/processor_detect_linux.cpp`, `tier1/reliabletimer.cpp`, `tier1/pathmatch.cpp`,
  `public/saverestoretypes.h`, `public/steam/steamtypes.h` (`X64BITS`): riscv next to ARM.
- `wscript`: waf reports `DEST_CPU = 'riscv'`. Adds `-fsigned-char` (char is unsigned on RISC-V, the code
  assumes x86) and `LIB += atomic` (as LIB, not a `-latomic` link flag: with `--as-needed` the flag came
  before the objects and was dropped).
- No `-march` yet: Debian's default `rv64gc` (no vector), so SIMDe runs its portable C code.
- The native x86_64 build was re-checked after these changes and still builds.

## Stage 3 — Milk-V Jupiter (done)

### Deploy

```bash
# 1. cross build on the laptop (stage 2)
scripts/riscv64/build.sh
# 2. game data, once (steam_legacy!), without Steam's own x86 binaries in hl2/bin
S=~/.local/share/Steam/steamapps/common/"Half-Life 2"
ssh 192.168.2.32 'mkdir -p ~/games/hl2-source/hl2 ~/games/hl2-source/platform'
rsync -a --exclude=bin/ "$S/hl2/" 192.168.2.32:games/hl2-source/hl2/
rsync -a "$S/platform/" 192.168.2.32:games/hl2-source/platform/
# 3. engine on top
rsync -a install-riscv64/ 192.168.2.32:games/hl2-source/
# check: no missing libraries
ssh -n 192.168.2.32 'cd ~/games/hl2-source && for f in hl2_launcher bin/*.so hl2/bin/*.so; do LD_LIBRARY_PATH=bin ldd $f | grep "not found"; done'
```

### What is on the board now

| Path | What |
| --- | --- |
| `~/games/hl2-source/` | plain rv64gc build + game data (copied from the laptop, steam_legacy, 3.6 GB) + `hl2/bench.dem` |
| `~/games/hl2-source-rvv/` | RVV build; `hl2/*` data symlinked to the dir above, own `cfg/`, `save/`, `bench.dem` |
| `~/games/hl2-source-dxvk/` | **DXVK (Vulkan) build** (plain rv64gc) + `bin/libdxvk_d3d9.so*`; data symlinked like the RVV dir; app-menu entry "Half-Life 2 (RISC-V DXVK Vulkan)", log `~/hl2-run-dxvk.log` |
| `/usr/bin/perf` (package `linux-perf-k1 7.3.0-1`) | perf for the custom kernel (stage 5) |
| `~/hl2-perf.sh` | copy of `scripts/riscv64/hl2-perf.sh` |
| `~/games/hl2-source*/run-hl2.sh` | start script (native Wayland, log to `~/hl2-run.log` / `~/hl2-run-rvv.log`) |
| `~/.local/share/applications/hl2-source*.desktop` | app-menu entries "Half-Life 2 (RISC-V)" and "Half-Life 2 (RISC-V RVV)" |
| `~/games/hl2-source*/hl2/cfg/autoexec.cfg` | `con_enable 1` (console key `` ` ``) |
| `~/hl2-timedemo.sh`, `~/hl2-bench.sh` | copies of the scripts in `scripts/riscv64/` |
| `~/hl2-bench/<label>/` | benchmark logs/results |
| `~/gpu-hang-20261103-2121.dmesg` | dmesg of the GPU hang |

The user starts the game themselves from the app menu (gets keyboard focus). When Claude started it
over ssh with X11 (Xwayland) the keyboard did not work (mouse did); with native Wayland it works.

### Start / stop / screenshot over ssh

Start the game as a **systemd user unit** in the board's Wayland session. A plain `nohup ... &` from
ssh got killed when the ssh session closed (no coredump, log just stops — looks like a crash but is
not; `timeout N` gives the same symptom).

```bash
ssh -n 192.168.2.32 'export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus;
  systemd-run --user --unit=hl2 --collect -p WorkingDirectory=$HOME/games/hl2-source \
    -E WAYLAND_DISPLAY=wayland-0 -E XDG_RUNTIME_DIR=/run/user/1000 \
    sh -c "exec ./hl2_launcher -game hl2 -windowed -w 1280 -h 720 -novid +map d1_canals_01 > \$HOME/hl2-run.log 2>&1"'
ssh -n 192.168.2.32 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user status hl2'
ssh -n 192.168.2.32 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop hl2'

# screenshot of the board desktop
ssh -n 192.168.2.32 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus spectacle -b -n -f -o /tmp/shot.png'
scp 192.168.2.32:/tmp/shot.png .

# after a real crash
ssh -n 192.168.2.32 'coredumpctl list --no-pager | grep hl2; tail -50 ~/hl2-run.log'
```

Always use `ssh -n` (or `< /dev/null`), otherwise ssh waits for background processes.

### Result (2026-11-03)

- `ldd`: no missing libraries.
- `OpenGL: AMD Radeon R9 200 Series (radeonsi, hawaii, ACO, DRM 3.64) 4.6 (Compatibility Profile) Mesa 25.0.7`.
- `d1_canals_01` in a 1280x720 window on the KDE Wayland desktop: world, alpha-tested fences, sky,
  viewmodel and HUD render correctly, no geometry glitches, game runs (health/ammo change).
- The game data on the board lives in `~/games/hl2-source/` (copied, not symlinked).

## Stage 4 — RVV (vector) build and benchmarking (done: works, no speed-up)

### RVV build variant

`scripts/riscv64/build.sh` takes `MARCH` (+ `VARIANT`) and then builds into separate dirs, so the
plain rv64gc build stays available for comparison:

```bash
MARCH=rv64gcv_zvl256b_zba_zbb_zbs VARIANT=rvv scripts/riscv64/build.sh   # -> install-riscv64-rvv/
```

Flags: `build.sh` passes `-march=rv64gcv_zvl256b_zba_zbb_zbs -mabi=lp64d -mrvv-vector-bits=zvl` as
CFLAGS/CXXFLAGS/LINKFLAGS; `wscript` adds `-fno-tree-vectorize` for every riscv build. It **must** be in
`wscript` (after the optimization flags): waf's release flags contain `-ftree-vectorize`, which came later
on the command line and silently re-enabled the auto-vectorizer when `-fno-tree-vectorize` was passed
via CFLAGS (2nd RVV build still had vector gathers in `R_StudioBuildMeshStrips`). Notes:

- SIMDe 0.8.2 has no hand-written RVV code for SSE, but it is built on GCC generic vector types; with a
  fixed vector length (`zvl256b` + `-mrvv-vector-bits=zvl`) GCC lowers those to RVV. Verified on a test:
  `_mm_add_ps(_mm_mul_ps(a,b),a)` → `vle32.v / vfmadd.vv / vse32.v`.
  `libmaterialsystem.so`: 3873 vector instructions in the RVV build vs 0 in rv64gc.
- **`-fno-tree-vectorize` is required.** Without it, the first RVV build died with **SIGBUS** while
  loading models: GCC auto-vectorized a plain loop in `CStudioRenderContext::R_StudioBuildMeshStrips`
  (studiorender) into `vluxei64.v` (indexed vector load) over unaligned model-file data. The K1 traps on
  **misaligned vector** accesses (misaligned scalar accesses are fine/emulated). SIMDe's explicit,
  16-byte aligned vector types still compile to RVV with the auto-vectorizer off (checked).
- **`-mstringop-strategy=libcall` is required too** (also added in `wscript` for riscv). Otherwise GCC
  inlines `memcpy`/`memset` as RVV loops (`vle8.v`/`vse8.v`). The engine copies vertex data into GPU
  buffers mapped through the PCIe BAR (`CVertexBuffer::HandleLateCreation` → `IDirect3DVertexBuffer9::Lock`),
  and on the K1 a **vector store to that uncached device memory raises a store access fault** (cause 7,
  `badaddr` = start of the mapping) — seen as SIGSEGV in `libshaderapidx9.so+0x20e16` on the serial console
  during `td-rvv-r1`; the process then hung in `do_exit`. Scalar stores there are fine, which is why the
  rv64gc build (glibc's scalar memcpy) never hit it. The earlier hard freeze while loading (`rvv-c2`) is
  probably the same thing. Watch out: explicit SIMD stores into locked GPU buffers (e.g. `FastVertexSSE`
  in `imesh.h` via SIMDe) could hit the same limitation if such a buffer is device memory.
- Deployed on the board to a separate dir `~/games/hl2-source-rvv` (binaries from `install-riscv64-rvv/`,
  game data symlinked to `~/games/hl2-source/hl2/*`, own `cfg/` + `save/`).

### Benchmark method (timedemo — preferred)

The user recorded a demo while playing (console: `record bench` … `stop`; console enabled with
`con_enable 1` in `hl2/cfg/autoexec.cfg` on the board): `~/games/hl2-source/hl2/bench.dem`
(d1_canals_01, 142 s, 9467 ticks, 5552 frames; copied to the rvv dir too).

`scripts/riscv64/hl2-timedemo.sh <game dir> <label> [demo]` (copy to the board) starts the game with
`-condebug +timedemoquit bench`: the engine renders every demo frame as fast as it can (so playback is
faster than real time), prints `N frames X seconds Y fps (Z ms/f) V fps variability` and exits; the script
takes that line from `hl2/console.log`. Both builds replay exactly the same frames — no one has to stand still.

```bash
scp scripts/riscv64/hl2-timedemo.sh 192.168.2.32:
ssh -n 192.168.2.32 '~/hl2-timedemo.sh ~/games/hl2-source td-rv64gc-1; ~/hl2-timedemo.sh ~/games/hl2-source-rvv td-rvv-1'
```

HL2 itself ships no usable benchmark: the menu benchmark loads map `test_hardware` (not in HL2), and the
demos in `hl2_pak` (`devtest.dem`, `bump3.dem`) are old `HLDEMO` (GoldSrc-era) files.

In-game fps counter: console `cl_showfps 1`. (The graph seen during the first measurements was Mesa's
`GALLIUM_HUD=fps`.)

Serial console logging during runs (to catch kernel messages if the board freezes):
`ssh -n 192.168.2.32 sudo dmesg -n 8` and on the laptop
`python3 -I /home/opvolger/code/linux-kernel-jupiter-1/milkv-tools/ser.py 1500 > serial.log &`.

### Benchmark method (old: standing still)

`scripts/riscv64/hl2-bench.sh <game dir> <label> [map]` (copy it to the board: `scp scripts/riscv64/hl2-bench.sh 192.168.2.32:`):
starts the game as systemd user unit with `SDL_VIDEODRIVER=wayland`, `GALLIUM_HUD=fps` and
`GALLIUM_HUD_DUMP_DIR` (Mesa writes one fps value per second to a file), waits 100 s, stops it and prints
the average of the last 40 s. Map `d1_canals_01`, player stands still at the spawn (the first ~60 s are
loading + the map's scripted intro). Results land in `~/hl2-bench/<label>/` on the board.

```bash
ssh -n 192.168.2.32 '~/hl2-bench.sh ~/games/hl2-source rv64gc-1; ~/hl2-bench.sh ~/games/hl2-source-rvv rvv-1'
```

- Always force `SDL_VIDEODRIVER=wayland`: the systemd user env has `DISPLAY=:0`, so SDL otherwise picks
  X11 (Xwayland).
- Recording a demo automatically via a cfg (`record` in `game.cfg`) did not work (`wait` does not delay
  during map loading); the demo for the timedemo method was recorded by the user while playing.
- After every run, check `sudo dmesg | grep "ring gfx timeout"` (see GPU hang below).

### Results (2026-11-03) and conclusion

timedemo `bench` (d1_canals_01, 5449 frames), 1280x720 window, native Wayland, board untouched:

| Build | Runs |
| --- | --- |
| rv64gc (plain) | 51.54 · 52.26 · 51.95 fps (~19.2 ms/frame) |
| rvv (`rv64gcv_zvl256b_zba_zbb_zbs`, final flags) | 51.97 · 52.02 fps |
| rv64gc at **640x480** | 54.44 fps |
| rv64gc + `+mat_queue_mode 2` | 51.14 · 50.56 fps (no change: queued mode is already the default) |
| rv64gc + **Zink** (`MESA_LOADER_DRIVER_OVERRIDE=zink`: GL on top of Vulkan/RADV) | 46.01 fps — works, no GPU hang, but ~12% slower (extra translation layer on the CPU) |

- **RVV gives no measurable speed-up.** The SSE→RVV code (SIMDe) works, but SIMD math is not where the time goes.
- **Resolution barely matters** (640x480 only +4%) → the GPU is not the limit; the game is **CPU-bound**
  (engine/game logic, and/or the GL driver path: Mesa radeonsi + kernel + uncached GPU memory over PCIe).
- Earlier numbers that looked like a gain (standing-still method: rvv 70.3 vs rv64gc 55.5–62.5) were noise:
  the user was playing during those runs. Use the timedemo numbers.
- Failed RVV attempts on the way (all fixed, see "RVV build variant"): auto-vectorizer → SIGBUS;
  `-fno-tree-vectorize` via CFLAGS overridden by waf; inline vector memcpy → store access fault / hard freeze.

**Is the PCIe riser (x1) the limit?** (question from the user, measured 2026-11-04)

- Actual link (`sudo lspci -vv -s 0002:01:00.0`): `LnkSta: Speed 5GT/s (downgraded), Width x1 (downgraded)`
  → PCIe 2.0 x1, ~500 MB/s per direction. Card: 8GT/s x16; K1 root port max 5GT/s **x2**; the riser makes it x1.
- Timedemo with Mesa HUD dump (`GALLIUM_HUD=GPU-load,cpu,num-bytes-moved,buffer-wait-time,...`,
  `GALLIUM_HUD_DUMP_DIR`, results in `~/hl2-bench/hud/`): 50.5 fps, **GPU-load avg 8.7% (max 14%)**,
  total CPU ~41% of 8 cores, `num-bytes-moved` ~0 (one 2 MB spike).
- `top -H` during the run: **main game thread 100%** of one core, a second thread ~91% (the queued
  material-system render thread, which makes the GL/Mesa calls), two more at 27–45% (Mesa threads?).
- Conclusion: the GPU is idle >90% of the time; the game is limited by **single-thread CPU speed** (main
  thread), not by the x1 link bandwidth. Caveat: stalls on uncached stores to GPU memory over PCIe also
  count as CPU time, so part of that 100% may still be PCIe latency — `perf` (stage 5) will show whether the
  time is in engine code or in driver/kernel paths writing GPU buffers. An x2 riser would be a cheap test
  (K1 max is x2), but a big gain is not expected.

Raw results are on the board in `~/hl2-bench/<label>/` (`td-*`, `td2-*`, `td3-*`, `td-lowres-*`).

### GPU hang on the board (kernel/amdgpu, not the game code)

- During the 2nd rv64gc benchmark run (2026-11-03 20:56): `amdgpu: ring gfx timeout`, soft reset failed,
  GPU reset then deadlocked in `dm_suspend` (`amdgpu_dm_irq_suspend` → `flush_work`, HPD irq worker
  waiting on the same mutex). KWin + Xwayland stuck in `D` state → no client can connect anymore
  (new game instances hang in `XOpenDisplay` / `wl_display_roundtrip`). Also at boot: `There are no
  outputs`, `Failed to setup vendor infoframe on connector HDMI-A-1`.
- Saved dmesg: `~/gpu-hang-20261103-2121.dmesg` on the board.
- Recovery: `sudo systemctl reboot` hung (D-state tasks) → after ~4 min power-cycled with
  `milkv-tools/power.sh off; sleep 5; power.sh on` (no package operations were running).
- Happened once with the plain build after a few runs; not reproduced in the next 4 runs.
- **Hard freeze, 2026-11-03 22:23:24** (boot -1): 9 s after starting the RVV run `rvv-c2` (while loading
  the map) the whole board froze: HDMI capture showed full-screen garbage (corrupt scan-out), no ssh, no
  reaction on the serial console. Power-cycled. The persistent journal has nothing after 21:30 (not
  flushed before the freeze), so no kernel trace. Next time: log the serial console during runs, e.g.
  `picocom -b 115200 --logfile serial.log /dev/ttyUSB0` (or `milkv-tools/ser.py`), with kernel console
  loglevel raised (`sudo dmesg -n 8`), to catch the last kernel messages.
- Not proven to be RVV-related: the first GPU hang was with the plain build; the RVV build renders more
  frames per second, i.e. more GPU load. Both point at the amdgpu/PCIe layer on the K1. Belongs to the
  kernel work in `linux-kernel-jupiter-1` (R9 290 on the K1, non-coherent DMA).

## Stage 6 — Vulkan via DXVK-native (done: works, +12%)

### Build

DXVK source: `/home/opvolger/code/dxvk` (git clone `--recursive` of doitsujin/dxvk, checked out at tag **v3.1.1**).
RADV on the Hawaii (GFX7) card has every feature DXVK 3.1 requires (checked against `vulkaninfo` on the board).

```bash
podman build -t source-engine-dxvk -f scripts/dxvk/Containerfile scripts/dxvk   # once (on top of source-engine-riscv64)
scripts/dxvk/build.sh ../dxvk x86_64     # -> dxvk-x86_64/  (include/dxvk, lib/libdxvk_d3d9.so*), ~3 min
scripts/dxvk/build.sh ../dxvk riscv64    # -> dxvk-riscv64/ (meson cross file, plain rv64gc: no vector code)

# laptop (native, own out dir + lock file):
WAFLOCK=.lock-waf_dxvk ./waf configure -T release --build-games=hl2 --use-dxvk -o build-dxvk --prefix=$HOME/games/hl2-dxvk
WAFLOCK=.lock-waf_dxvk ./waf install && cp -a dxvk-x86_64/lib/libdxvk_d3d9.so* ~/games/hl2-dxvk/bin/
# board:
VARIANT=dxvk scripts/riscv64/build.sh --use-dxvk                 # -> install-riscv64-dxvk/, ~22 min
cp -a dxvk-riscv64/lib/libdxvk_d3d9.so* install-riscv64-dxvk/bin/
rsync -a install-riscv64-dxvk/ 192.168.2.32:games/hl2-source-dxvk/   # then compare sha256sum
```

Laptop game dir `~/games/hl2-dxvk/` (data links like stage 1, `run-hl2.sh`, `hl2/bench.dem` copied from the board).
DXVK writes its pipeline cache to `~/.cache/dxvk/`; the first run after a new build is ~2 fps slower.

### Engine changes (commit `5d8f3a65`, ~160 lines + 2 files)

The engine already had the real D3D9 path (Windows); `--use-dxvk` compiles that on Linux against DXVK's headers
instead of ToGL (`DXVK` define, `GL`/`DX_TO_GL_ABSTRACTION` off, `togl` not built):
- `public/togl/dxvk_d3d9.h`: DXVK's `windows.h`, `d3d9.h`, `d3dx9math.h`, `d3dx9shader.h` (the full `d3dx9.h` needs GDI
  types DXVK does not have; `ID3DXBuffer` declared by hand). DXVK's `ULONG` (32-bit) and `HMODULE` are renamed while
  including, because the engine's POSIX typedefs differ; `ZeroMemory` macro undefined.
- `shaderapidx9/dxvk_d3dx9.cpp`: the D3DX functions the shader API calls (matrix math, `ID3DXMatrixStack`,
  `D3DXGetShaderVersion`; `D3DXCompileShader` → `E_NOTIMPL`), plus `GetVidMemBytes()` = 2 GB (D3D9 cannot tell).
- `winutils`: `GetClientRect`/`IsIconic`/`ClientToScreen` via SDL (HWND = `SDL_Window*`).
- `sdlmgr.cpp`: window with `SDL_WINDOW_VULKAN`, no GL context. `shaderdevicedx8.cpp`: `setenv("DXVK_WSI_DRIVER","SDL2",0)`
  (DXVK-native throws `DxvkError` without it). `sys_mainwind.cpp`: device window = SDL window.
- `platform.h`: **`IsPlatformOpenGL()` is false with DXVK**, so the Windows paths are used (SM3 shaders instead of
  "always SM2b", D3D9 vendor hacks, ...). Before this change the game also worked (same speed); the window title said
  "- OpenGL". Main menu (water reflections, fonts) and `d1_canals_01` render like ToGL.
- `imageformat.h`: on POSIX it defined a fake `D3DFORMAT` enum (ToGL values); with DXVK the real one is used, and the
  `D3DFormatToImageFormat` helpers are only declared where `dxvk_d3d9.h` is included (C++ cannot forward-declare the
  enum; including the Windows headers everywhere broke other modules).
- `strncpy=use_Q_strncpy_instead` / `_snprintf=...` command-line poison macros (materialsystem, shaderapidx9) are
  dropped for DXVK: `<cstring>` from DXVK's `windows_base.h` does `using ::strncpy`, which fails when `string.h` was
  parsed under the macro.

### Results (2026-11-04 night)

timedemo `bench` (5449 frames), 1280x720 window, native Wayland, board untouched:

| Build | Runs (fps) |
| --- | --- |
| ToGL rv64gc (same session) | 51.95 · 50.72 · (50.96 under perf) |
| DXVK, `IsPlatformOpenGL()` still true | 55.71 (first run, empty pipeline cache) · 57.41 · 58.04 |
| DXVK + `d3d9.cachedDynamicBuffers = True` (dxvk.conf) | 58.57 — no real difference |
| **DXVK, final (Windows paths)** | 56.94 · 57.61 · 59.57 · (57.28 under perf) |
| laptop x86_64 (Intel Arc B390): ToGL / DXVK / DXVK final | 724.8 / 966.1 / 1003.6 |

No GPU hang or amdgpu errors in dmesg during ~12 DXVK runs (serial console was logged to
`scratchpad/serial.log` of that session; nothing notable).

perf (`~/hl2-bench/perf-dxvk/`), compare with ToGL in stage 5 (1 core ≈ 40% of the samples):

| Thread | Share | ≈ core | Top DSOs |
| --- | --- | --- | --- |
| main | 39.8% | ~98% | libengine 14.4, libclient 10.8, libc 4.1, kernel 2.7 (was 5.3 with ToGL), materialsystem 2.2 |
| material-system render thread | 34.7% | ~86% | shaderapidx9 8.2, materialsystem 7.2, libc 6.5, **libdxvk_d3d9 6.2**, stdshader 3.2 |
| `dxvk-cs` (DXVK's command-stream thread) | 15.5% | ~38% | libvulkan_radeon 6.8, libdxvk_d3d9 5.8, libc 2.1 |
| `dxvk-submit` / `-queue` / `-descriptor` | 7.1% | ~18% | mostly kernel/amdgpu (submission) |

So DXVK+RADV (~56% of a core) is cheaper than Mesa's GL threads (`gl0` + `gdrv0`, ~69%), and the main thread waits
less. **The main game thread (engine + client code) is still at ~100% and is the limit** — further gains must
come from there (or from a faster CPU), not from the renderer.

## Stage 5 — perf on the board (done, 2026-11-04 night)

### perf package

The board kernel is custom, so Debian's `linux-perf` does not match. perf is built from the patched
kernel tree in the kernel repo and packaged as a .deb:

```bash
cd /home/opvolger/code/linux-kernel-jupiter-1
scripts/perf/build-perf.sh 7.3          # container (scripts/perf/Containerfile), -> linux-perf-k1_7.3.0-<rev>_riscv64.deb
scp linux-perf-k1_7.3.0-1_riscv64.deb 192.168.2.32:/tmp/ && ssh 192.168.2.32 sudo dpkg -i /tmp/linux-perf-k1_7.3.0-1_riscv64.deb
```

- Debian trixie container, cross-compiled (`ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-`), links only libraries
  that are already on the board (libelf, libdw, slang, zlib, zstd, libcap, lzma); built without libtraceevent,
  python, perl, numa, babeltrace, libunwind (libdw does DWARF unwinding) and BPF skeletons (need clang).
  Needs `PYTHON=python3 PYTHON_CONFIG=python3` (jevents) and a host `gcc` (fixdep) in the container.
- These scripts live in the kernel repo and are **not committed** there (user's repo; ask first).
- Installed on the board: `linux-perf-k1 7.3.0-1`, `/usr/bin/perf`, `perf version 7.3.0`.
- **K1 PMU quirk: `perf record -e cycles` gets 0 samples** (counting with `perf stat` works: cycles,
  instructions; the overflow interrupt never arrives). **Use `-e cpu-clock`** (timer based) for sampling.
- `perf report --sort tid` **segfaults** (perf bug); use `-s pid` (lists per thread) and `--tid <n>`.
- `kernel.perf_event_paranoid` is 2 → run `perf record` with sudo (the scripts do); `perf report` of kernel
  symbols needs `sudo perf report -f`.
- Game libraries have symbols (not stripped); Mesa's `libgallium` and libc only have dynamic symbols, so their
  time shows per DSO, not per function.

### Profile of the ToGL build (timedemo, `perf-togl`)

`scripts`: `hl2-perf.sh <game dir> <label> [delay=45] [duration=40]` (copy on the board in `~/`; runs
`hl2-timedemo.sh` and samples the game with `perf record -e cpu-clock -F 999 -p <pid>`). Results in
`~/hl2-bench/perf-togl/` (`perf.data`, `perf-dso.txt`, `perf-sym.txt`, `perf-comm.txt`). Timedemo 50.96 fps.

Per thread (share of all samples; 100% of one core ≈ 37%):

| Thread | Share | ≈ core | What |
| --- | --- | --- | --- |
| main (`hl2_launcher`, tid = pid) | 36.9% | ~100% | libengine 12.0, libclient 9.3, kernel 5.3 (futex/sched_yield: waiting on the render thread), libc 3.4, libmaterialsystem 1.8 |
| material-system render thread (2nd `hl2_launcher`) | 32.0% | ~87% | libshaderapidx9 7.8, libmaterialsystem 6.5, Mesa/gallium 4.4, libc 3.8, libstdshader_dx9 2.9, **libtogl only 2.1**, studiorender 1.2 |
| Mesa `gl0` (glthread) | 15.5% | ~42% | libgallium 9.4, libc 4.8 |
| Mesa `gdrv0` (gallium driver thread) | 10.0% | ~27% | libgallium 8.1 |
| `cs0` (amdgpu command submission) | 2.9% | ~8% | amdgpu kernel driver |

Conclusions:
- The main thread (game + engine logic: world/BSP traversal, shadows, client entities) is the limit; it also
  spends ~14% of its time in the kernel synchronising with the render thread (futex, `sched_yield`).
- ToGL itself is cheap (2% of samples); the render thread's time is mostly the engine's own shader API /
  material system (D3D9 state handling), then Mesa. So replacing ToGL with DXVK can only win where Mesa's GL
  path (glthread + driver thread + GL dispatch, ~30% of all samples) is more expensive than DXVK+RADV.
- No misaligned-access trap handler in the kernel profile: the unaligned-access emulation is not a hot spot.
  No vector code in the hot paths (plain build).

## Status / next steps

- [x] Stage 1: local x86_64 build, plays fine (user verified)
- [x] Stage 2: riscv64 cross build (Debian trixie container)
- [x] Stage 3: HL2 runs on the Milk-V Jupiter; user played it (keyboard + mouse work with native Wayland)
- [x] Stage 4: RVV build works (fixes for SIGBUS / store access fault) but gives no speed-up (~52 fps both)
- [x] Stage 5: `perf` built for the board kernel and installed; ToGL build profiled (see "Stage 5" section)
- [x] Stage 6: DXVK-native works on laptop and board, +12% on the board (see "Stage 6")
- [ ] **User test of the DXVK build** on the board (app menu "Half-Life 2 (RISC-V DXVK Vulkan)"): play a while,
      check visuals (water, flashlight, HDR maps), input, alt-tab/fullscreen, and whether the GPU hang returns.
- [ ] Profile the main thread with call graphs: build with `-fno-omit-frame-pointer` (or `--call-graph dwarf`,
      large data) to see which engine/client code dominates (`R_RecursiveWorldNode`, `CShadowMgr::*`,
      `C_BaseAnimating::*`, ... are in the flat profile). Then targeted optimisation, or `-march=..._zba_zbb_zbs`.
- [ ] Optional: DXVK built with `-march` (zba/zbb, **no vector**: the K1 faults on vector stores to VRAM) / LTO.
- [ ] Optional: upstream the DXVK option (nillerusr README lists "dxvk-native support" as a wish) — ask the user.
- [ ] Kernel repo: `scripts/perf/` (Containerfile, `build-perf.sh`) and the perf note in `milk-v-testing.md` are
      **uncommitted** in `linux-kernel-jupiter-1` — ask the user whether to commit them.
- [ ] Optional: `-march` with only `zba_zbb_zbs` (no V) — scalar bitmanip may help a little
- [ ] Optional: native RVV code for hot SIMD paths (`ssemath.h`) — only if profiling shows SIMD math is hot
- [ ] Optional: replace the libatomic lock-based 128-bit CAS in `tslist.h` if profiling shows contention
- [ ] Report the amdgpu GPU hang (ring gfx timeout + reset deadlock) in the kernel repo notes
      (`linux-kernel-jupiter-1/milk-v-testing.md`) — ask the user, it is their kernel work
- [ ] Optional: HDMI capture (green noise) — check cabling / capture input
- [ ] Optional: upstream / PR of the commits (ask the user first)

## Pitfalls for automation (learned the hard way)

- `pkill -f <pattern>` / `pgrep -f` also match **the shell running your own command** when the pattern is
  in that command line → it kills itself (exit code 144). Anchor the pattern, e.g.
  `pkill -f '^python3 -I .*ser\.py'`, or kill by PID.
- Put deploy (`rsync`) and other steps in separate commands; after deploying, compare `sha256sum` on the
  laptop and the board (a killed command once left old binaries on the board, and the "new" build crashed
  with the old bug).
- Start the game on the board via `systemd-run --user` (see stage 3), not `nohup … &` over ssh, and always
  force `SDL_VIDEODRIVER=wayland`.
- Only one game instance at a time (lock file); stop the `hl2` user unit before starting another.
- Full cross builds take ~22 min: run them in the background.
- Changing `wscript` flags, `CFLAGS`, or `LIB` triggers a full rebuild.

## Problems encountered and fixes

### Segfault at startup under Wayland (fixed, commit `e39e05aa`)

- Crash right after `SDL video target is 'wayland'`; backtrace `strstr` ← `CheckOpenGLExtension_internal`
  ← `COpenGLEntryPoints` (togl) ← `CSDLMgr::CreateHiddenGameWindow`. With `SDL_VIDEODRIVER=x11` it worked.
- When an extension is not in `GL_EXTENSIONS`, togl falls back to
  `glXQueryExtensionsString(glXGetCurrentDisplay())`. Under Wayland SDL uses EGL; the GLX pointers from
  `SDL_GL_GetProcAddress` are unusable stubs (a NULL check alone was not enough).
- Fix (`togl/linuxwin/glentrypoints.cpp`): only query GLX when SDL's video driver is `x11` (looked up with
  `dlsym(RTLD_DEFAULT, "SDL_GetCurrentVideoDriver")`, since togl does not link SDL), skip NULL results.
  Also needed on the board (Wayland).

### UI text as white blocks, blurred menu background (fixed: `steam_legacy`)

- Every VGUI font (menu, console) showed each glyph as a white rectangle; menu background blurred; 3D
  in maps fine. Same on llvmpipe → not a driver bug. FreeType output, the engine's glyph RGBA buffer and
  `bitmap/colorconversion.cpp` were all verified correct.
- Cause: shaders (`shaders/fxc/*.vcs`) come from the Steam VPK; the 2024 anniversary update changed them,
  so the combos no longer match the 2018 `stdshader_dx9`. The repo has only shader sources, no `.vcs`.
- Fix: Steam → Half-Life 2 → Properties → Betas → `steam_legacy`; then refresh the game dir and delete
  `hl2/glshaders.cfg`. (Alternative, not done: compile the shaders ourselves — a lot of work.)
- Ref: <https://developer.valvesoftware.com/wiki/220>

### `jpeg` console command aborts (fixed, commit `8ba18ef0`)

- `Wrong JPEG library version: library is 62, caller expects 80` + `pure virtual method called`.
- `engine/sys_getmodes.cpp` and `gameui/OptionsSubMultiplayer.cpp` included the bundled libjpeg v8 header
  (`public/jpeglib/jpeglib.h`) but link the system libjpeg-turbo (API 62). Fix: `<jpeglib.h>` on Linux
  (Windows/Android keep the bundled header), like `common/imageutils.cpp` already did.

### riscv64 build problems (fixed, commit `958b18df`)

- `#error "Unknown architecture"` in `tier0/cpu.cpp` → arch name added.
- `undefined reference to __sync_bool_compare_and_swap_16` (tier0/tslist) → `__atomic` + libatomic.
- `undefined reference to __atomic_compare_exchange_16` → `-latomic` was dropped by `--as-needed`; now LIB.
- `imesh.h: unrecognized opcode movq ... %mm0` (x86 MMX asm) → intrinsics path.
- Ubuntu image → wrong sonames for the board (Debian) → switched to Debian trixie.

### Not bugs (checked)

- **Blurry start screen / blurry engine screenshots:** during startup the engine shows
  `materials/console/backgroundXX_widescreen.vtf` (512x512 DXT1, pre-blurred by Valve; verified by decoding
  the VTF). The menu after that is sharp. `wait N` in a `+exec`'d cfg does not delay during startup/map
  loading (all waits pass within ~2 s), so `jpeg`/`screenshot` taken that way capture this loading image.
  For debugging screenshots use spectacle with a real `sleep`:
  start the game in the background, then `spectacle -b -n -a -o shot.png` (laptop) or the board command above.
- **Game "crashed" on the board:** it was ended by `timeout 180`, then by the ssh session closing — use
  `systemd-run --user` (see stage 3).
- `gl_blitmode 0` hits a debug trap in togl `StretchRect` → keep the default (1).

### Harmless log messages

- `Can't find module - sourcevr.so / video_bink / video_webm / stdshader_dx6/7/8/dbg` — optional, not built.
- `CreatePixelShader: shaderapi's centroid mask ... differs` (flashlight/shatteredglass shaders) — warnings.
- `Unable to rename cfg/touch.cfg` — no touch.cfg yet.
- Configure prints `2 test failed` for optional compiler flags — harmless.
