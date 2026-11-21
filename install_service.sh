#!/usr/bin/env bash
# Compatibility entrypoint for older instructions; installs the current CiaNet Self package.
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/install.sh" "$@"
