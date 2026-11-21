#!/usr/bin/env bash
# Compatibility entrypoint. All installation is local and ZIP-based.
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/install.sh" "$@"
