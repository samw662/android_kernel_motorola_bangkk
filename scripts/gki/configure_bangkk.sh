#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Resolve the standalone bangkk config in Qualcomm -> common -> device order.
# Additional arguments are make toolchain assignments, shared with compilation.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 OUTPUT_DIRECTORY [make toolchain assignments...]" >&2
    exit 1
fi
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
shift
[[ "$OUT" != "$ROOT" ]] || { echo "Use a separate output directory." >&2; exit 1; }
cd "$ROOT"
# Unlike the reference's newer Makefile, this stock Makefile does not infer
# Clang's target from ARCH when CROSS_COMPILE is empty. LLVM tools handle the
# actual compilation/linking; this prefix supplies the ARM64 target triple.
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
export CLANG_TRIPLE="${CLANG_TRIPLE:-aarch64-linux-gnu-}"

BASE=arch/arm64/configs/vendor/holi-qgki_defconfig
COMMON=arch/arm64/configs/vendor/ext_config/moto-holi.config
DEVICE=arch/arm64/configs/vendor/ext_config/moto-holi-bangkk.config
for f in "$BASE" "$COMMON" "$DEVICE" KernelSU/kernel/Kconfig; do
    [[ -f "$f" ]] || { echo "Missing config input: $f" >&2; exit 1; }
done

make O="$OUT" ARCH=arm64 "$@" vendor/holi-qgki_defconfig
scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" "$COMMON" "$DEVICE"
make O="$OUT" ARCH=arm64 "$@" olddefconfig

# A successful merge alone does not prove a tristate survived its dependencies.
for symbol in MODULES MODULE_UNLOAD MODVERSIONS; do
    grep -qx "CONFIG_${symbol}=y" "$OUT/.config" || {
        echo "Required builtin config lost: CONFIG_$symbol" >&2; exit 1;
    }
done
for fragment in "$COMMON" "$DEVICE"; do
    while IFS= read -r assignment; do
        [[ "$assignment" == CONFIG_*=m ]] || continue
        grep -qxF "$assignment" "$OUT/.config" || {
            echo "Required module config lost: $assignment" >&2; exit 1;
        }
    done < "$fragment"
done
grep -qx 'CONFIG_LTO_NONE=y' "$OUT/.config"
for symbol in LTO_CLANG CFI_CLANG MODULE_SIG MODULE_COMPRESS MODULE_ALLOW_MISSING_NAMESPACE_IMPORTS; do
    if grep -q "^CONFIG_${symbol}=[ym]$" "$OUT/.config"; then
        echo "Unexpected first-build policy: CONFIG_$symbol" >&2
        exit 1
    fi
done
