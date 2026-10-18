#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# Keep the established runtime available while the ARM64 compatibility gate is
# open. The experimental build is selected explicitly, without a Rosetta fallback.
case "${NTSD_RUNTIME:-intel}" in
    arm64) exec "$ROOT/build-arm64.sh" "$@" ;;
    intel) exec "$ROOT/build-intel.sh" "$@" ;;
    *) echo 'NTSD_RUNTIME must be arm64 or intel' >&2; exit 1 ;;
esac
