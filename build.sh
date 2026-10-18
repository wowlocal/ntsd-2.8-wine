#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# Native ARM64 Wine/FEX is the default. The legacy Intel runtime remains an
# explicit option; the ARM64 target never installs or falls back to Rosetta.
case "${NTSD_RUNTIME:-arm64}" in
    arm64|fex) exec "$ROOT/build-arm64.sh" "$@" ;;
    intel|rosetta) exec "$ROOT/build-intel.sh" "$@" ;;
    both)
        OUTPUT="${NTSD_BUILD_DIR:-$ROOT/build}"
        NTSD_RUNTIME=arm64 NTSD_BUILD_DIR="$OUTPUT/fex" "$ROOT/build-arm64.sh" "$@"
        NTSD_RUNTIME=intel NTSD_BUILD_DIR="$OUTPUT/rosetta" "$ROOT/build-intel.sh" "$@"
        ;;
    *) echo 'NTSD_RUNTIME must be arm64/fex, intel/rosetta, or both' >&2; exit 1 ;;
esac
