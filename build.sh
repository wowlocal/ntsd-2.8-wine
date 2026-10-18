#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# Native ARM64 Wine/FEX is the default. The legacy Intel runtime remains an
# explicit option; the ARM64 target never installs or falls back to Rosetta.
case "${NTSD_RUNTIME:-arm64}" in
    arm64) exec "$ROOT/build-arm64.sh" "$@" ;;
    intel) exec "$ROOT/build-intel.sh" "$@" ;;
    *) echo 'NTSD_RUNTIME must be arm64 or intel' >&2; exit 1 ;;
esac
