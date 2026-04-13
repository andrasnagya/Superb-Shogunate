#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# install_state_dir.sh — Create Shogunate mutable state directory
# ═══════════════════════════════════════════════════════════════
# Creates ~/.shogunate/ with the full directory structure for
# mutable state (queue, context, config, projects, logs, etc.)
#
# The plugin cache (under ~/.claude/plugins/) holds IMMUTABLE code.
# Mutable state lives here, outside ~/.claude/, to avoid:
# - Permission prompts (Claude Code protects ~/.claude/)
# - State loss on plugin reinstall
#
# Usage: bash scripts/install_state_dir.sh [--from PLUGIN_PATH]
#   --from PLUGIN_PATH: copy initial config from plugin cache
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SHOGUNATE_STATE="${HOME}/.shogunate"
FROM_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --from) FROM_PATH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo "[INFO] Creating Shogunate state directory at ${SHOGUNATE_STATE}..."

# Create directory structure
mkdir -p "${SHOGUNATE_STATE}/config"
mkdir -p "${SHOGUNATE_STATE}/context"
mkdir -p "${SHOGUNATE_STATE}/projects"
mkdir -p "${SHOGUNATE_STATE}/queue/tasks"
mkdir -p "${SHOGUNATE_STATE}/queue/reports"
mkdir -p "${SHOGUNATE_STATE}/queue/inbox"
mkdir -p "${SHOGUNATE_STATE}/queue/metrics"
mkdir -p "${SHOGUNATE_STATE}/logs"
mkdir -p "${SHOGUNATE_STATE}/status"
mkdir -p "${SHOGUNATE_STATE}/saytask"
mkdir -p "${SHOGUNATE_STATE}/memory"
mkdir -p "${SHOGUNATE_STATE}/reports"
mkdir -p "${SHOGUNATE_STATE}/ipc/startup"
mkdir -p "${SHOGUNATE_STATE}/ipc/env"

# Initialize config files if they don't exist
if [ ! -f "${SHOGUNATE_STATE}/config/projects.yaml" ]; then
    cat > "${SHOGUNATE_STATE}/config/projects.yaml" << 'EOF'
projects: []

current_project: null
EOF
    echo "[OK] Created config/projects.yaml"
fi

if [ ! -f "${SHOGUNATE_STATE}/config/settings.yaml" ] && [ -n "$FROM_PATH" ] && [ -f "$FROM_PATH/config/settings.yaml" ]; then
    cp "$FROM_PATH/config/settings.yaml" "${SHOGUNATE_STATE}/config/settings.yaml"
    echo "[OK] Copied config/settings.yaml from plugin"
elif [ ! -f "${SHOGUNATE_STATE}/config/settings.yaml" ]; then
    cat > "${SHOGUNATE_STATE}/config/settings.yaml" << 'EOF'
language: en
bloom_routing: auto
EOF
    echo "[OK] Created default config/settings.yaml"
fi

# Initialize empty queue file
if [ ! -f "${SHOGUNATE_STATE}/queue/shogun_to_karo.yaml" ]; then
    echo "[]" > "${SHOGUNATE_STATE}/queue/shogun_to_karo.yaml"
    echo "[OK] Created empty queue/shogun_to_karo.yaml"
fi

# Initialize dashboard
if [ ! -f "${SHOGUNATE_STATE}/dashboard.md" ]; then
    cat > "${SHOGUNATE_STATE}/dashboard.md" << 'EOF'
# Dashboard
Last updated: —

## In Progress
(none)

## Battle Results
(none)

## Action Required
(none)
EOF
    echo "[OK] Created dashboard.md"
fi

# Create .venv in state dir (not plugin cache)
if [ ! -d "${SHOGUNATE_STATE}/.venv" ]; then
    if python3 -m venv "${SHOGUNATE_STATE}/.venv" 2>/dev/null; then
        if [ -n "$FROM_PATH" ] && [ -f "$FROM_PATH/requirements.txt" ]; then
            "${SHOGUNATE_STATE}/.venv/bin/pip" install -r "$FROM_PATH/requirements.txt" -q 2>/dev/null || true
        fi
        echo "[OK] Created .venv in state directory"
    else
        echo "[WARN] Failed to create .venv (python3-venv may need installing)"
    fi
fi

echo "[OK] Shogunate state directory ready at ${SHOGUNATE_STATE}"
echo ""
echo "  Immutable code:  ~/.claude/plugins/cache/.../shogunate/ (plugin)"
echo "  Mutable state:   ${SHOGUNATE_STATE}/"
echo "  Agents work in plugin cache (trusted), write to ${SHOGUNATE_STATE}/ via absolute paths"
