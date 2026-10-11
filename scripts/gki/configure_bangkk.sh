#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Resolve the inline bangkk config in Qualcomm -> Motorola -> device order.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[[ $# -ge 1 ]] || { echo "Usage: $0 OUTPUT_DIRECTORY [make assignments...]" >&2; exit 1; }
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
shift
[[ "$OUT" != "$ROOT" ]] || { echo "Use a separate output directory." >&2; exit 1; }
cd "$ROOT"
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
export CLANG_TRIPLE="${CLANG_TRIPLE:-aarch64-linux-gnu-}"
BASE=arch/arm64/configs/vendor/holi-qgki_defconfig
COMMON=arch/arm64/configs/vendor/ext_config/moto-holi.config
DEVICE=arch/arm64/configs/vendor/ext_config/moto-holi-bangkk.config
for file in "$BASE" "$COMMON" "$DEVICE" KernelSU/kernel/Kconfig; do
    [[ -f "$file" ]] || { echo "Missing config input: $file" >&2; exit 1; }
done
# Merge the raw requests before resolving dependencies. Expanding the base
# alone can discard builtin requests whose platform dependencies arrive later.
make O="$OUT" ARCH=arm64 "$@" vendor/holi-qgki_defconfig
(cd "$OUT" && "$ROOT/scripts/kconfig/merge_config.sh" -m -O "$OUT" \
    "$ROOT/$BASE" "$ROOT/$COMMON" "$ROOT/$DEVICE")
make O="$OUT" ARCH=arm64 "$@" olddefconfig
for symbol in TOUCHSCREEN_MMI TOUCHSCREEN_FTS_V3 TOUCHSCREEN_GOODIX_BERLIN_MMI; do
    grep -qx "CONFIG_${symbol}=y" "$OUT/.config" || {
        echo "Required builtin config lost: CONFIG_$symbol" >&2; exit 1;
    }
done
if grep -q '^CONFIG_TOUCHSCREEN_FOCALTECH_V3_MMI=[ym]$' "$OUT/.config"; then
    echo "Duplicate FocalTech implementation enabled" >&2
    exit 1
fi
if grep -q '^CONFIG_.*=m$' "$OUT/.config"; then
    echo "Unexpected modular config in the inline build" >&2
    exit 1
fi
