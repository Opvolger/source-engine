#!/bin/sh
# Cross-compile the engine for riscv64 inside the container from ./Containerfile.
#
#   scripts/riscv64/build.sh [extra waf configure args]
#
# Output: build-riscv64/ (objects) and install-riscv64/ (installed game dir layout).
# Uses its own waf lock file, so it does not disturb the native ./build directory.
set -e
cd "$(dirname "$0")/../.."
IMAGE=${IMAGE:-source-engine-riscv64}

exec podman run --rm -v "$PWD":/src:Z -w /src -e WAFLOCK=.lock-waf_riscv64 "$IMAGE" sh -c "
	set -e
	./waf configure -T release --build-games=hl2 -o build-riscv64 --prefix=/src/install-riscv64 $*
	./waf build
	./waf install
"
