#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# switch_cli.sh — Safely switch an agent's CLI session
#
# Usage:
#   bash scripts/switch_cli.sh <agent_id> [--type <cli_type>] [--model <model_name>]
#
# Examples:
#   # Restart with current settings.yaml values (no CLI type/model change)
#   bash scripts/switch_cli.sh ashigaru3
#
#   # Switch from Codex Spark → Claude Sonnet
#   bash scripts/switch_cli.sh ashigaru3 --type claude --model claude-sonnet-4-6
#
#   # Change model only within the same CLI (Sonnet → Opus)
#   bash scripts/switch_cli.sh ashigaru3 --model claude-opus-4-6
#
#   # Batch switch all ashigaru
#   for i in $(seq 1 7); do bash scripts/switch_cli.sh ashigaru$i --type claude --model claude-sonnet-4-6; done
#
# Flow:
#   1. (Optional) Update settings.yaml
#   2. Send /exit to the current CLI
#   3. Wait for shell prompt to return
#   4. Build new CLI command via build_cli_command()
#   5. Launch new CLI via tmux send-keys
#   6. Update tmux pane metadata (@agent_cli, @model_name)
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETTINGS_FILE="${PROJECT_ROOT}/config/settings.yaml"
LOG_FILE="${PROJECT_ROOT}/logs/switch_cli.log"

# Load cli_adapter.sh
source "${PROJECT_ROOT}/lib/cli_adapter.sh"

# ─── Logging ───
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [switch_cli] $*"
    echo "$msg" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# ─── Usage ───
usage() {
    echo "Usage: $0 <agent_id> [--type <cli_type>] [--model <model_name>]"
    echo ""
    echo "  agent_id   karo, ashigaru1-7, gunshi"
    echo "  --type     claude | codex | copilot | kimi"
    echo "  --model    claude-sonnet-4-6 | claude-opus-4-6 | gpt-5.3-codex | etc."
    echo ""
    echo "If --type/--model omitted, uses current settings.yaml values."
    exit 1
}

# ─── Agent ID → tmux pane resolution ───
# Dynamically search panes via @agent_id metadata (handles pane number drift)
# Fallback: uses legacy fixed mapping if metadata is not found
resolve_pane() {
    local agent_id="$1"

    # Phase 1: Dynamic search via @agent_id metadata
    local pane_count
    pane_count=$(tmux list-panes -t "multiagent:agents" 2>/dev/null | wc -l)
    if [[ "$pane_count" -gt 0 ]]; then
        for i in $(seq 0 $((pane_count - 1))); do
            local aid
            aid=$(tmux display-message -t "multiagent:agents.$i" -p '#{@agent_id}' 2>/dev/null)
            if [[ "$aid" == "$agent_id" ]]; then
                echo "multiagent:agents.$i"
                return 0
            fi
        done
        log "WARN: @agent_id=$agent_id not found in any pane. Falling back to fixed mapping."
    fi

    # Phase 2: Fallback (legacy fixed mapping)
    local pane_base
    pane_base=$(tmux show-options -t multiagent -v @pane_base 2>/dev/null || echo "0")

    case "$agent_id" in
        karo)       echo "multiagent:agents.$((pane_base + 0))" ;;
        ashigaru1)  echo "multiagent:agents.$((pane_base + 1))" ;;
        ashigaru2)  echo "multiagent:agents.$((pane_base + 2))" ;;
        ashigaru3)  echo "multiagent:agents.$((pane_base + 3))" ;;
        ashigaru4)  echo "multiagent:agents.$((pane_base + 4))" ;;
        ashigaru5)  echo "multiagent:agents.$((pane_base + 5))" ;;
        ashigaru6)  echo "multiagent:agents.$((pane_base + 6))" ;;
        ashigaru7)  echo "multiagent:agents.$((pane_base + 7))" ;;
        gunshi)     echo "multiagent:agents.$((pane_base + 8))" ;;
        *)
            log "ERROR: Unknown agent_id: $agent_id"
            return 1
            ;;
    esac
}

# ─── Update settings.yaml (using Python) ───
update_settings_yaml() {
    local agent_id="$1"
    local new_type="${2:-}"
    local new_model="${3:-}"

    if [[ -z "$new_type" && -z "$new_model" ]]; then
        return 0
    fi

    log "Updating settings.yaml: ${agent_id} → type=${new_type:-<unchanged>}, model=${new_model:-<unchanged>}"

    "${PROJECT_ROOT}/.venv/bin/python3" << PYEOF
import yaml, sys, os, datetime

settings_path = "${SETTINGS_FILE}"
agent_id = "${agent_id}"
new_type = "${new_type}" or None
new_model = "${new_model}" or None

with open(settings_path, 'r', encoding='utf-8') as f:
    content = f.read()

with open(settings_path, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

cli = data.setdefault('cli', {})
agents = cli.setdefault('agents', {})
agent_cfg = agents.get(agent_id)
if not isinstance(agent_cfg, dict):
    agent_cfg = {}
    agents[agent_id] = agent_cfg

timestamp = datetime.datetime.now().strftime('%Y-%m-%d')
comment = f"# {timestamp}: switched by switch_cli.sh"

if new_type:
    agent_cfg['type'] = new_type
if new_model:
    agent_cfg['model'] = new_model

data['cli']['agents'][agent_id] = agent_cfg

# Replacing only the target agent line via sed would be safer for comment preservation,
# but using yaml.dump for completeness. Comments would be lost.
# → Instead, use a sed-like approach: rewrite only the target block

# Simple approach: read lines, find agent block, replace
lines = content.split('\n')
new_lines = []
in_agent_block = False
agent_indent = None
skip_until_next = False

i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.lstrip()

    # Detect our agent's block start
    if stripped.startswith(f'{agent_id}:'):
        in_agent_block = True
        agent_indent = len(line) - len(stripped)
        new_lines.append(line)
        # Write the updated fields
        inner_indent = ' ' * (agent_indent + 2)
        if new_type:
            new_lines.append(f'{inner_indent}type: {new_type}')
        if new_model:
            new_lines.append(f'{inner_indent}model: {new_model}  {comment}')
        # Skip old sub-fields
        i += 1
        while i < len(lines):
            next_line = lines[i]
            next_stripped = next_line.lstrip()
            if next_stripped == '' or next_stripped.startswith('#'):
                # Keep blank lines and comments between blocks
                if next_stripped.startswith('#') and len(next_line) - len(next_stripped) > agent_indent:
                    i += 1
                    continue
                break
            next_indent = len(next_line) - len(next_stripped)
            if next_indent <= agent_indent:
                break  # Next agent or section
            i += 1
        in_agent_block = False
        continue
    else:
        new_lines.append(line)
    i += 1

with open(settings_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(new_lines))
    if not content.endswith('\n'):
        pass
    else:
        f.write('\n') if not '\n'.join(new_lines).endswith('\n') else None

print("OK")
PYEOF
}

# ─── Get current CLI type (tmux metadata) ───
get_current_pane_cli() {
    local pane="$1"
    tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null | tr -d '[:space:]' || echo "claude"
}

# ─── Send /exit ───
send_exit() {
    local pane="$1"
    local current_cli="$2"

    log "Sending exit command to ${pane} (current CLI: ${current_cli})"

    case "$current_cli" in
        codex)
            # Codex: suggestion UI dismissal → Ctrl-C → /exit
            tmux send-keys -t "$pane" Escape 2>/dev/null || true
            sleep 0.3
            tmux send-keys -t "$pane" C-c 2>/dev/null || true
            sleep 0.5
            tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
            sleep 0.3
            tmux send-keys -t "$pane" Enter 2>/dev/null || true
            ;;
        claude)
            tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
            sleep 0.3
            tmux send-keys -t "$pane" Enter 2>/dev/null || true
            ;;
        copilot|kimi)
            tmux send-keys -t "$pane" C-c 2>/dev/null || true
            sleep 0.5
            tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
            sleep 0.3
            tmux send-keys -t "$pane" Enter 2>/dev/null || true
            ;;
        *)
            tmux send-keys -t "$pane" "/exit" 2>/dev/null || true
            sleep 0.3
            tmux send-keys -t "$pane" Enter 2>/dev/null || true
            ;;
    esac
}

# ─── Wait for shell prompt (max 15 seconds) ───
wait_for_shell_prompt() {
    local pane="$1"
    local max_wait=15
    local waited=0

    log "Waiting for shell prompt on ${pane}..."

    while [ "$waited" -lt "$max_wait" ]; do
        sleep 1
        waited=$((waited + 1))

        local last_lines
        last_lines=$(tmux capture-pane -t "$pane" -p 2>/dev/null | grep -v '^$' | tail -3)

        # Shell prompt detection patterns
        # PS1 may contain custom prompts (from shutsujin) or standard $/% prompts
        if echo "$last_lines" | grep -qE '[\$%#❯►] *$'; then
            log "Shell prompt detected after ${waited}s"
            return 0
        fi

        # Detect CLI exit messages such as "exit" / "Bye"
        if echo "$last_lines" | grep -qiE '(bye|goodbye|exiting|exit)'; then
            sleep 1  # Wait briefly after exit message for prompt to appear
            log "CLI exit message detected after ${waited}s"
            return 0
        fi
    done

    log "WARN: Shell prompt not detected after ${max_wait}s. Proceeding anyway."
    return 0  # Continue even on timeout (worst case is just a command being sent)
}

# ─── Model display name normalization (uses get_model_display_name from cli_adapter.sh) ───
# get_model_display_name is already sourced from cli_adapter.sh

# ─── tmux pane metadata update ───
update_pane_metadata() {
    local pane="$1"
    local new_cli_type="$2"
    local display_name="$3"

    log "Updating pane metadata: @agent_cli=${new_cli_type}, @model_name=${display_name}"

    tmux set-option -p -t "$pane" @agent_cli "$new_cli_type" 2>/dev/null || true
    tmux set-option -p -t "$pane" @model_name "$display_name" 2>/dev/null || true
    tmux select-pane -t "$pane" -T "$display_name" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════
# Main processing
# ═══════════════════════════════════════════════════════════════

# Parse arguments
if [ $# -lt 1 ]; then
    usage
fi

# If --help is the first argument
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
fi

AGENT_ID="$1"
shift

NEW_TYPE=""
NEW_MODEL=""

while [ $# -gt 0 ]; do
    case "$1" in
        --type)
            NEW_TYPE="$2"
            shift 2
            ;;
        --model)
            NEW_MODEL="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validation
if [[ -n "$NEW_TYPE" ]] && ! _cli_adapter_is_valid_cli "$NEW_TYPE"; then
    log "ERROR: Invalid CLI type: ${NEW_TYPE}. Allowed: ${CLI_ADAPTER_ALLOWED_CLIS}"
    exit 1
fi

# Step 0: Resolve pane
PANE_TARGET=$(resolve_pane "$AGENT_ID")
if [ -z "$PANE_TARGET" ]; then
    exit 1
fi
log "=== Starting CLI switch for ${AGENT_ID} (pane: ${PANE_TARGET}) ==="

# Step 0.5: If --model specified but --type omitted, auto-infer CLI type from model name
if [[ -n "$NEW_MODEL" && -z "$NEW_TYPE" ]]; then
    case "$NEW_MODEL" in
        gpt-5.3-codex*|gpt-5-codex*)
            NEW_TYPE="codex"
            log "Auto-inferred type=codex from model=${NEW_MODEL}"
            ;;
        claude-*)
            NEW_TYPE="claude"
            log "Auto-inferred type=claude from model=${NEW_MODEL}"
            ;;
    esac
fi

# Step 1: Update settings.yaml (only when --type/--model specified)
if [[ -n "$NEW_TYPE" || -n "$NEW_MODEL" ]]; then
    update_settings_yaml "$AGENT_ID" "$NEW_TYPE" "$NEW_MODEL"
fi

# Step 2: Get post-switch CLI info (after settings.yaml update)
TARGET_CLI_TYPE=$(get_cli_type "$AGENT_ID")
TARGET_MODEL=$(get_agent_model "$AGENT_ID")
TARGET_CMD=$(build_cli_command "$AGENT_ID")

log "Target: cli=${TARGET_CLI_TYPE}, model=${TARGET_MODEL}, cmd=${TARGET_CMD}"

# Step 3: Terminate current CLI with /exit
CURRENT_CLI=$(get_current_pane_cli "$PANE_TARGET")
log "Current CLI: ${CURRENT_CLI}"
send_exit "$PANE_TARGET" "$CURRENT_CLI"

# Step 4: Wait for shell prompt
wait_for_shell_prompt "$PANE_TARGET"

# Step 5: Send new CLI command
log "Launching new CLI: ${TARGET_CMD}"
if [[ "$TARGET_CMD" =~ ^[a-zA-Z0-9_./ -]+$ ]]; then
    tmux send-keys -t "$PANE_TARGET" "$TARGET_CMD" 2>/dev/null || true
else
    echo "$TARGET_CMD" > "${SHOGUNATE_STATE}/ipc/cmd_${AGENT_ID}.txt"
    tmux send-keys -t "$PANE_TARGET" "bash ${SHOGUNATE_STATE}/ipc/cmd_${AGENT_ID}.txt" 2>/dev/null || true
fi
sleep 0.3
tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null || true

# Step 6: Update tmux pane metadata
DISPLAY_NAME=$(get_model_display_name "$AGENT_ID")
update_pane_metadata "$PANE_TARGET" "$TARGET_CLI_TYPE" "$DISPLAY_NAME"

log "=== CLI switch complete: ${AGENT_ID} → ${TARGET_CLI_TYPE}/${TARGET_MODEL} (${DISPLAY_NAME}) ==="
echo "OK: ${AGENT_ID} → ${TARGET_CLI_TYPE}/${TARGET_MODEL}"
