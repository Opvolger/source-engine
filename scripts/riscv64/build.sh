#!/bin/sh
# Cross-compile the engine for riscv64 inside the container from ./Containerfile.
#
#   scripts/riscv64/build.sh [extra waf configure args]
#
# Output: build-riscv64/ (objects) and install-riscv64/ (installed game dir layout).
# Uses its own waf lock file, so it does not disturb the native ./build directory.
#
# Optional: MARCH selects the target ISA and builds into separate directories
# (build-riscv64-<variant>/, install-riscv64-<variant>/), e.g. for the RVV build:
#
#   MARCH=rv64gcv_zvl256b_zba_zbb_zbs VARIANT=rvv scripts/riscv64/build.sh
#
# VARIANT alone also selects separate directories, e.g. the DXVK-native (Vulkan) build
# (needs dxvk-riscv64/ from scripts/dxvk/build.sh):
#
#   VARIANT=dxvk scripts/riscv64/build.sh --use-dxvk
#
# With a vector ISA, -mrvv-vector-bits=zvl is added so GCC uses the fixed VLEN from zvl*b
# (lets SIMDe's / GCC's generic 128-bit vector types map to RVV). The auto-vectorizer is
# switched off for riscv in wscript (misaligned vector accesses SIGBUS on the K1). Such binaries only run on
# CPUs that have those extensions (the SpacemiT K1 / X60 has RVV 1.0 with VLEN=256).
set -e
cd "$(dirname "$0")/../.."
IMAGE=${IMAGE:-source-engine-riscv64}

SUFFIX=${VARIANT:+-$VARIANT}
FLAGS=
if [ -n "$MARCH" ]; then
	SUFFIX=-${VARIANT:-$MARCH}
	FLAGS="-march=$MARCH -mabi=lp64d"
	case "$MARCH" in
	rv64gcv*|*_v_*|*_zve*)
		# (the auto-vectorizer is switched off for riscv in wscript: -fno-tree-vectorize)
		FLAGS="$FLAGS -mrvv-vector-bits=zvl" ;;
	esac
fi

exec podman run --rm -v "$PWD":/src:Z -w /src \
	-e WAFLOCK=.lock-waf_riscv64$SUFFIX \
	-e CFLAGS="$FLAGS" -e CXXFLAGS="$FLAGS" -e LINKFLAGS="$FLAGS" \
	"$IMAGE" sh -c "
	set -e
	./waf configure -T release --build-games=hl2 -o build-riscv64$SUFFIX --prefix=/src/install-riscv64$SUFFIX $*
	./waf build
	./waf install
"
