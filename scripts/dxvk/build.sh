#!/bin/sh
# Build DXVK-native (only d3d9, SDL2 WSI) in the container from ./Containerfile.
#
#   scripts/dxvk/build.sh <dxvk source dir> x86_64|riscv64 [extra meson args]
#
# Output: <source engine>/dxvk-<arch>/ (prefix: include/dxvk, lib/libdxvk_d3d9.so).
# The source dir is mounted read-only; the meson build dir is build-dxvk-<arch>/.
set -e
cd "$(dirname "$0")/../.."
DXVK=$(realpath "$1"); ARCH=$2; shift 2
IMAGE=${IMAGE:-source-engine-dxvk}
case "$ARCH" in
x86_64) CROSS= ;;
riscv64) CROSS="--cross-file /usr/local/share/meson/riscv64-cross.txt" ;;
*) echo "arch must be x86_64 or riscv64" >&2; exit 1 ;;
esac

exec podman run --rm -v "$DXVK":/dxvk:ro,Z -v "$PWD":/src:Z -w /src "$IMAGE" sh -c "
	set -e
	unset CC CXX AR STRIP PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
	[ -f build-dxvk-$ARCH/build.ninja ] || meson setup $CROSS --buildtype release \
		--prefix /src/dxvk-$ARCH --libdir lib \
		-Denable_dxgi=false -Denable_d3d8=false -Denable_d3d10=false -Denable_d3d11=false \
		-Dnative_sdl2=enabled -Dnative_sdl3=disabled -Dnative_glfw=disabled $* \
		build-dxvk-$ARCH /dxvk
	ninja -C build-dxvk-$ARCH install
"
