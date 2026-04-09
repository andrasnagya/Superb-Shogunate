#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# setup.sh - Compatibility wrapper script
# ═══════════════════════════════════════════════════════════════════════════════
# This script has been consolidated into shutsujin_departure.sh.
# For compatibility, all arguments are forwarded to shutsujin_departure.sh.
#
# Recommended: Use ./shutsujin_departure.sh directly.
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/shutsujin_departure.sh" "$@"
