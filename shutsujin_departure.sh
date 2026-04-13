#!/usr/bin/env bash
# 🏯 multi-agent-shogun Deployment Script (daily launch)
# Daily Deployment Script for Multi-Agent Orchestration System
#
# Usage:
#   ./shutsujin_departure.sh           # Launch all agents (preserve previous state)
#   ./shutsujin_departure.sh -c        # Reset queues and launch (clean start)
#   ./shutsujin_departure.sh -s        # Setup only (no Claude launch)
#   ./shutsujin_departure.sh -h        # Show help

set -e

# Get script directory (immutable code — plugin cache)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Shogunate state directory (mutable data — outside ~/.claude/)
SHOGUNATE_STATE="${HOME}/.shogunate"
if [ ! -d "$SHOGUNATE_STATE" ]; then
    echo "[WARN] State directory ${SHOGUNATE_STATE} not found. Run first_setup.sh first."
    echo "       Creating minimal structure..."
    bash "$SCRIPT_DIR/scripts/install_state_dir.sh" --from "$SCRIPT_DIR" 2>/dev/null || true
fi

# Read language setting (default: ja)
LANG_SETTING="ja"
if [ -f "./config/settings.yaml" ]; then
    LANG_SETTING=$(grep "^language:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "ja")
fi

# Read shell setting (default: bash)
SHELL_SETTING="bash"
if [ -f "./config/settings.yaml" ]; then
    SHELL_SETTING=$(grep "^shell:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "bash")
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Python venv Preflight Check
# ───────────────────────────────────────────────────────────────────────────────
# inbox_write.sh, inbox_watcher.sh, cli_adapter.sh depend on .venv/bin/python3.
# Auto-create venv if it doesn't exist (handles first launch after git pull).
# ═══════════════════════════════════════════════════════════════════════════════
VENV_DIR="$SHOGUNATE_STATE/.venv"
if [ ! -f "$VENV_DIR/bin/python3" ] || ! "$VENV_DIR/bin/python3" -c "import yaml" 2>/dev/null; then
    echo -e "\033[1;33m[INFO]\033[0m Setting up Python venv..."
    if command -v python3 &>/dev/null; then
        python3 -m venv "$VENV_DIR" 2>/dev/null || {
            echo -e "\033[1;31m[ERROR]\033[0m python3 -m venv failed. The python3-venv package may be required."
            echo "  Ubuntu/Debian: sudo apt-get install python3-venv"
            exit 1
        }
        "$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" -q 2>/dev/null || {
            echo -e "\033[1;31m[ERROR]\033[0m pip install failed."
            exit 1
        }
        echo -e "\033[1;32m[OK]\033[0m Python venv setup complete"
    else
        echo -e "\033[1;31m[ERROR]\033[0m python3 not found. Please run first_setup.sh."
        exit 1
    fi
fi

# Load CLI Adapter (Multi-CLI Support)
if [ -f "$SCRIPT_DIR/lib/cli_adapter.sh" ]; then
    source "$SCRIPT_DIR/lib/cli_adapter.sh"
    CLI_ADAPTER_LOADED=true
else
    CLI_ADAPTER_LOADED=false
fi

# Dynamically get ashigaru ID list and count (from settings.yaml)
if [ "$CLI_ADAPTER_LOADED" = true ]; then
    _ASHIGARU_IDS_STR=$(get_ashigaru_ids)
else
    _ASHIGARU_IDS_STR="ashigaru1 ashigaru2 ashigaru3 ashigaru4 ashigaru5 ashigaru6 ashigaru7"
fi
_ASHIGARU_COUNT=$(echo "$_ASHIGARU_IDS_STR" | wc -w | tr -d ' ')

# Colored log functions (sengoku style)
log_info() {
    echo -e "\033[1;33m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m[OK]\033[0m $1"
}

log_war() {
    echo -e "\033[1;31m[WAR]\033[0m $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Superpowers Dependency Detection
# ───────────────────────────────────────────────────────────────────────────────
# Checks for external Superpowers plugin. If found, prefer it (fresher).
# If not, fall back to vendored copy at vendor/superpowers/.
# Sets SUPERPOWERS_PATH and SUPERPOWERS_VERSION for agents via tmux variable.
# ═══════════════════════════════════════════════════════════════════════════════
detect_superpowers() {
    local external_base="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers"
    local vendor_path="$SCRIPT_DIR/vendor/superpowers"
    local external_path=""
    local external_version=""

    # Check for external Superpowers plugin (any version)
    if [ -d "$external_base" ]; then
        # Find the latest version directory
        external_path=$(ls -d "$external_base"/*/ 2>/dev/null | sort -V | tail -1)
        if [ -n "$external_path" ] && [ -f "$external_path/package.json" ]; then
            external_version=$(grep '"version"' "$external_path/package.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
            SUPERPOWERS_PATH="$external_path"
            SUPERPOWERS_VERSION="$external_version"
            SUPERPOWERS_SOURCE="external"
            log_info "📦 Superpowers: v${SUPERPOWERS_VERSION} (external plugin)"
            return 0
        fi
    fi

    # Fall back to vendored copy
    if [ -d "$vendor_path" ] && [ -f "$vendor_path/package.json" ]; then
        local vendor_version
        vendor_version=$(grep '"version"' "$vendor_path/package.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
        SUPERPOWERS_PATH="$vendor_path"
        SUPERPOWERS_VERSION="$vendor_version"
        SUPERPOWERS_SOURCE="bundled"
        log_info "📦 Superpowers: v${SUPERPOWERS_VERSION} (bundled) — install Superpowers plugin for latest"
        return 0
    fi

    # Neither found
    SUPERPOWERS_PATH=""
    SUPERPOWERS_VERSION=""
    SUPERPOWERS_SOURCE="none"
    log_war "📦 Superpowers: not found (vendor/superpowers/ missing)"
    return 1
}

# Run detection
detect_superpowers

# ═══════════════════════════════════════════════════════════════════════════════
# Prompt generation function (bash/zsh compatible)
# ───────────────────────────────────────────────────────────────────────────────
# Usage: generate_prompt "label" "color" "shell"
# Colors: red, green, blue, magenta, cyan, yellow
# ═══════════════════════════════════════════════════════════════════════════════
generate_prompt() {
    local label="$1"
    local color="$2"
    local shell_type="$3"

    if [ "$shell_type" == "zsh" ]; then
        # zsh: %F{color}%B...%b%f format
        echo "(%F{${color}}%B${label}%b%f) %F{green}%B%~%b%f%# "
    else
        # bash: \[\033[...m\] format
        local color_code
        case "$color" in
            red)     color_code="1;31" ;;
            green)   color_code="1;32" ;;
            yellow)  color_code="1;33" ;;
            blue)    color_code="1;34" ;;
            magenta) color_code="1;35" ;;
            cyan)    color_code="1;36" ;;
            *)       color_code="1;37" ;;  # white (default)
        esac
        echo "(\[\033[${color_code}m\]${label}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ "
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Option Parsing
# ═══════════════════════════════════════════════════════════════════════════════
SETUP_ONLY=false
OPEN_TERMINAL=false
CLEAN_MODE=false
KESSEN_MODE=false
SHOGUN_NO_THINKING=false
SILENT_MODE=false
SHELL_OVERRIDE=""
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            if [[ -n "$2" && "$2" != -* ]]; then
                PROJECT_PATH="$2"
                shift 2
            else
                echo "Error: -p option requires a project path"
                exit 1
            fi
            ;;
        -s|--setup-only)
            SETUP_ONLY=true
            shift
            ;;
        -c|--clean)
            CLEAN_MODE=true
            shift
            ;;
        -k|--kessen)
            KESSEN_MODE=true
            shift
            ;;
        -t|--terminal)
            OPEN_TERMINAL=true
            shift
            ;;
        --shogun-no-thinking)
            SHOGUN_NO_THINKING=true
            shift
            ;;
        -S|--silent)
            SILENT_MODE=true
            shift
            ;;
        -shell|--shell)
            if [[ -n "$2" && "$2" != -* ]]; then
                SHELL_OVERRIDE="$2"
                shift 2
            else
                echo "Error: -shell option requires bash or zsh"
                exit 1
            fi
            ;;
        -h|--help)
            echo ""
            echo "🏯 multi-agent-shogun Deployment Script"
            echo ""
            echo "Usage: ./shutsujin_departure.sh [options]"
            echo ""
            echo "Options:"
            echo "  -c, --clean         Reset queues and dashboard, then launch (clean start)"
            echo "                      Without this flag, previous state is preserved"
            echo "  -k, --kessen        Battle formation (launch all ashigaru with Opus)"
            echo "                      Without this flag, peacetime formation (ashigaru 1-7=Sonnet, gunshi=Opus)"
            echo "  -s, --setup-only    tmux session setup only (no Claude launch)"
            echo "  -t, --terminal      Open new tabs in Windows Terminal"
            echo "  -shell, --shell SH  Specify shell (bash or zsh)"
            echo "                      Without this flag, uses config/settings.yaml setting"
            echo "  -p, --project PATH  Set ashigaru working directory to PROJECT PATH"
            echo "                      Shogun and Karo stay in Shogunate home (queue management)"
            echo "                      Ashigaru cd to this path before Claude launches"
            echo "  -S, --silent        Silent mode (disable ashigaru sengoku echo display / save API calls)"
            echo "                      Without this flag, shout mode (sengoku echo on task completion)"
            echo "  -h, --help          Show this help"
            echo ""
            echo "Examples:"
            echo "  ./shutsujin_departure.sh              # Deploy, preserving previous state"
            echo "  ./shutsujin_departure.sh -c           # Clean start (queue reset)"
            echo "  ./shutsujin_departure.sh -s           # Setup only (launch Claude manually)"
            echo "  ./shutsujin_departure.sh -t           # Launch all agents + open terminal tabs"
            echo "  ./shutsujin_departure.sh -shell bash  # Launch with bash prompt"
            echo "  ./shutsujin_departure.sh -k           # Battle formation (all ashigaru Opus)"
            echo "  ./shutsujin_departure.sh -c -k         # Clean start + battle formation"
            echo "  ./shutsujin_departure.sh -shell zsh   # Launch with zsh prompt"
            echo "  ./shutsujin_departure.sh --shogun-no-thinking  # Disable shogun thinking (relay mode)"
            echo "  ./shutsujin_departure.sh -S           # Silent mode (no echo display)"
            echo ""
            echo "Model Configuration:"
            echo "  Shogun:      Opus (default; --shogun-no-thinking to disable)"
            echo "  Karo:        Opus (task management with full reasoning)"
            echo "  Gunshi:      Opus (strategy planning and design decisions)"
            echo "  Ashigaru 1-7: Sonnet (field operatives)"
            echo ""
            echo "Formations:"
            echo "  Peacetime (default):     ashigaru 1-7=Sonnet, gunshi=Opus"
            echo "  Battle (--kessen):       all ashigaru=Opus, gunshi=Opus"
            echo ""
            echo "Display Modes:"
            echo "  shout (default):  Sengoku style echo on task completion"
            echo "  silent (--silent): No echo display (saves API calls)"
            echo ""
            echo "Aliases:"
            echo "  csst  → cd <your-project-path> && ./shutsujin_departure.sh"
            echo "  css   → tmux attach-session -t shogun"
            echo "  csm   → tmux attach-session -t multiagent"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run ./shutsujin_departure.sh -h for help"
            exit 1
            ;;
    esac
done

# Shell setting override (command-line option takes priority)
if [ -n "$SHELL_OVERRIDE" ]; then
    if [[ "$SHELL_OVERRIDE" == "bash" || "$SHELL_OVERRIDE" == "zsh" ]]; then
        SHELL_SETTING="$SHELL_OVERRIDE"
    else
        echo "Error: -shell option requires bash or zsh (given: $SHELL_OVERRIDE)"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Deployment Banner Display (CC0 License ASCII Art)
# ───────────────────────────────────────────────────────────────────────────────
# [Copyright / License Notice]
# Ninja ASCII Art: syntax-samurai/ryu - CC0 1.0 Universal (Public Domain)
# Source: https://github.com/syntax-samurai/ryu
# "all files and scripts in this repo are released CC0 / kopimi!"
# ═══════════════════════════════════════════════════════════════════════════════
show_battle_cry() {
    clear

    # Title banner (colored)
    echo ""
    echo -e "\033[1;31m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████╗██╗  ██╗██╗   ██╗████████╗███████╗██╗   ██╗     ██╗██╗███╗   ██╗\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m██╔════╝██║  ██║██║   ██║╚══██╔══╝██╔════╝██║   ██║     ██║██║████╗  ██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████╗███████║██║   ██║   ██║   ███████╗██║   ██║     ██║██║██╔██╗ ██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m╚════██║██╔══██║██║   ██║   ██║   ╚════██║██║   ██║██   ██║██║██║╚██╗██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████║██║  ██║╚██████╔╝   ██║   ███████║╚██████╔╝╚█████╔╝██║██║ ╚████║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m╚══════╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝  ╚════╝ ╚═╝╚═╝  ╚═══╝\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m╠══════════════════════════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;31m║\033[0m       \033[1;37mMarch to battle!!!\033[0m       \033[1;36m⚔\033[0m    \033[1;35mConquer all under heaven!\033[0m           \033[1;31m║\033[0m"
    echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # Ashigaru Formation (original)
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;34m  ╔═════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;34m  ║\033[0m              \033[1;37m[ ASHIGARU FORMATION: 7 Soldiers + Gunshi ]\033[0m                \033[1;34m║\033[0m"
    echo -e "\033[1;34m  ╚═════════════════════════════════════════════════════════════════════════════╝\033[0m"

    cat << 'ASHIGARU_EOF'

       /\      /\      /\      /\      /\      /\      /\      /\
      /||\    /||\    /||\    /||\    /||\    /||\    /||\    /||\
     /_||\   /_||\   /_||\   /_||\   /_||\   /_||\   /_||\   /_||\
       ||      ||      ||      ||      ||      ||      ||      ||
      /||\    /||\    /||\    /||\    /||\    /||\    /||\    /||\
      /  \    /  \    /  \    /  \    /  \    /  \    /  \    /  \
     [AS1]   [AS2]   [AS3]   [AS4]   [AS5]   [AS6]   [AS7]   [GUN ]

ASHIGARU_EOF

    echo -e "                    \033[1;36m\"\"\" Ha!! We march to battle!! \"\"\"\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # System Information
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;33m  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
    echo -e "\033[1;33m  ┃\033[0m  \033[1;37m🏯 multi-agent-shogun\033[0m  ~ \033[1;36mSengoku Multi-Agent Command System\033[0m ~            \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m                                                                           \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m  \033[1;35mShogun\033[0m: Command  \033[1;31mKaro\033[0m: Manage  \033[1;33mGunshi\033[0m: Strategy(Opus)  \033[1;34mAshigaru\033[0m: x7  \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m"
    echo ""
}

# Execute banner display
show_battle_cry

echo -e "  \033[1;33mConquer all under heaven! Commencing formation setup.\033[0m"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Existing Session Cleanup
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🧹 Dismantling existing formations..."
tmux kill-session -t multiagent 2>/dev/null && log_info "  └─ multiagent formation dismantled" || log_info "  └─ No multiagent formation found"
tmux kill-session -t shogun 2>/dev/null && log_info "  └─ shogun headquarters dismantled" || log_info "  └─ No shogun headquarters found"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1.5: Previous Record Backup (--clean only, if content exists)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    BACKUP_DIR="./logs/backup_$(date '+%Y%m%d_%H%M%S')"
    NEED_BACKUP=false

    if [ -f "./dashboard.md" ]; then
        if grep -q "cmd_" "./dashboard.md" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    # Additional check after dashboard.md evaluation
    if [ -f "./queue/shogun_to_karo.yaml" ]; then
        if grep -q "id: cmd_" "./queue/shogun_to_karo.yaml" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    if [ "$NEED_BACKUP" = true ]; then
        mkdir -p "$BACKUP_DIR" || true
        cp "./dashboard.md" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/reports" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/tasks" "$BACKUP_DIR/" 2>/dev/null || true
        cp "./queue/shogun_to_karo.yaml" "$BACKUP_DIR/" 2>/dev/null || true
        log_info "📦 Previous records backed up: $BACKUP_DIR"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Queue Directory Setup + Reset (reset only with --clean)
# ═══════════════════════════════════════════════════════════════════════════════

# Create queue directories if they don't exist (needed on first launch)
[ -d ./queue/reports ] || mkdir -p ./queue/reports
[ -d ./queue/tasks ] || mkdir -p ./queue/tasks
# Symlink inbox to Linux FS (inotifywait doesn't work on WSL2's /mnt/c/)
# On macOS, fswatch is used so symlink is not needed
if [ "$(uname -s)" != "Darwin" ]; then
    INBOX_LINUX_DIR="$HOME/.local/share/multi-agent-shogun/inbox"
    if [ ! -L ./queue/inbox ]; then
        mkdir -p "$INBOX_LINUX_DIR"
        [ -d ./queue/inbox ] && cp ./queue/inbox/*.yaml "$INBOX_LINUX_DIR/" 2>/dev/null && rm -rf ./queue/inbox
        ln -sf "$INBOX_LINUX_DIR" ./queue/inbox
        log_info "  └─ inbox -> Linux FS ($INBOX_LINUX_DIR) symlink created"
    fi
else
    [ -d ./queue/inbox ] || mkdir -p ./queue/inbox
fi

if [ "$CLEAN_MODE" = true ]; then
    log_info "📜 Discarding previous war council records..."

    # Ashigaru task file reset
    for i in $(seq 1 "$_ASHIGARU_COUNT"); do
        cat > ./queue/tasks/ashigaru${i}.yaml << EOF
# Ashigaru ${i} task file
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
    done

    # Gunshi task file reset
    cat > ./queue/tasks/gunshi.yaml << EOF
# Gunshi task file
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF

    # Ashigaru report file reset
    for i in $(seq 1 "$_ASHIGARU_COUNT"); do
        cat > ./queue/reports/ashigaru${i}_report.yaml << EOF
worker_id: ashigaru${i}
task_id: null
timestamp: ""
status: idle
result: null
EOF
    done

    # Gunshi report file reset
    cat > ./queue/reports/gunshi_report.yaml << EOF
worker_id: gunshi
task_id: null
timestamp: ""
status: idle
result: null
EOF

    # ntfy inbox reset
    echo "inbox:" > ./queue/ntfy_inbox.yaml

    # agent inbox reset
    for agent in shogun karo $_ASHIGARU_IDS_STR gunshi; do
        echo "messages:" > "./queue/inbox/${agent}.yaml"
    done

    log_success "✅ Formation cleared"
else
    log_info "📜 Deploying with previous formation intact..."
    log_success "✅ Queue and report files preserved"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Dashboard Initialization (--clean only)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$CLEAN_MODE" = true ]; then
    log_info "📊 Initializing battle status dashboard..."
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

    if [ "$LANG_SETTING" = "ja" ]; then
        # Sengoku English only
        cat > ./dashboard.md << EOF
# 📊 Battle Status Report
Last Updated: ${TIMESTAMP}

## 🚨 Action Required - Awaiting Lord's Decision
None

## 🔄 In Progress - Currently in Battle
None

## ✅ Today's Battle Results
| Time | Battlefield | Mission | Result |
|------|-------------|---------|--------|

## 🎯 Skill Candidates - Pending Approval
None

## 🛠️ Generated Skills
None

## ⏸️ On Standby
None

## ❓ Questions for Lord
None
EOF
    else
        # Sengoku English + plain translation in parentheses
        cat > ./dashboard.md << EOF
# 📊 Battle Status Report
Last Updated: ${TIMESTAMP}

## 🚨 Action Required - Awaiting Lord's Decision
None

## 🔄 In Progress - Currently in Battle
None

## ✅ Today's Battle Results
| Time | Battlefield | Mission | Result |
|------|-------------|---------|--------|

## 🎯 Skill Candidates - Pending Approval
None

## 🛠️ Generated Skills
None

## ⏸️ On Standby
None

## ❓ Questions for Lord
None
EOF
    fi

    log_success "  └─ Dashboard initialized (language: $LANG_SETTING, shell: $SHELL_SETTING)"
else
    log_info "📊 Preserving previous dashboard"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: Verify tmux availability
# ═══════════════════════════════════════════════════════════════════════════════
if ! command -v tmux &> /dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] tmux not found!                              ║"
    echo "  ║                                                        ║"
    echo "  ╠════════════════════════════════════════════════════════╣"
    echo "  ║  Run first_setup.sh first:                            ║"
    echo "  ║                                                        ║"
    echo "  ║     ./first_setup.sh                                  ║"
    echo "  ╚════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4.5: Pre-trust working directories for Claude Code agents
# ───────────────────────────────────────────────────────────────────────────────
# Claude Code prompts "Do you trust this folder?" on first launch in a directory.
# --dangerously-skip-permissions does NOT bypass this. Running claude -p (print
# mode) in each directory pre-trusts it — the docs say: "The workspace trust
# dialog is skipped when Claude is run with the -p mode."
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🔐 Pre-trusting working directories for agents..."

_pretrust_dir() {
    local dir="$1"
    local label="$2"
    if [ -d "$dir" ]; then
        # Layer 1: Write directly to Claude Code's trust store
        local trust_name
        trust_name=$(echo "$dir" | sed 's|/|-|g')
        mkdir -p "$HOME/.claude/projects/${trust_name}" 2>/dev/null

        # Layer 2: Run claude -p to confirm trust (belt and suspenders)
        (cd "$dir" && claude -p "echo trusted" --dangerously-skip-permissions --setting-sources user 2>/dev/null) && \
            log_success "  └─ ${label}: ${dir}" || \
            log_info "  └─ ${label}: ${dir} (trust store written, claude -p skipped)"
    fi
}

# Pre-trust the plugin cache (Shogun/Karo/Gunshi CWD)
_pretrust_dir "$SCRIPT_DIR" "Plugin cache"

# Pre-trust the state directory
_pretrust_dir "$SHOGUNATE_STATE" "State dir"

# Pre-trust the project directory (ashigaru CWD)
if [ -n "$PROJECT_PATH" ]; then
    _pretrust_dir "$PROJECT_PATH" "Project"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: Create Shogun Session (1 pane, always secure window 0)
# ═══════════════════════════════════════════════════════════════════════════════
log_war "👑 Constructing shogun headquarters..."

# Create shogun session if it doesn't exist (ensure shogun exists even with -s)
# Create only window 0, named "main" (using a second window causes empty pane on attach, so limit to 1 window)
if ! tmux has-session -t shogun 2>/dev/null; then
    tmux new-session -d -s shogun -n main
fi

# Handle small-screen clients (phones, etc.): aggressive-resize + latest
# css function creates dedicated windows for small screens, so PC windows aren't affected
tmux set-option -g window-size latest
tmux set-option -g aggressive-resize on

# Shogun pane is specified by window name "main" (works even with base-index 1)
SHOGUN_PROMPT=$(generate_prompt "shogun" "magenta" "$SHELL_SETTING")
# Shogun stays in SCRIPT_DIR (plugin cache — already trusted by Claude Code)
# Mutable state accessed via absolute paths: ${SHOGUNATE_STATE}/queue/, etc.
# File-based env setup (safe from shell metacharacter issues)
_shogun_safe_prompt=$(printf '%s' "${SHOGUN_PROMPT}" | sed "s/'/'\\\\''/g")
cat > "${SHOGUNATE_STATE}/ipc/env/shogun.env" << ENVEOF
export SHOGUNATE_STATE="${SHOGUNATE_STATE}"
export PS1='${_shogun_safe_prompt}'
cd "$(pwd)"
ENVEOF
tmux send-keys -t shogun:main "source ${SHOGUNATE_STATE}/ipc/env/shogun.env && clear" Enter
tmux select-pane -t shogun:main -P 'bg=#002b36'  # Shogun's Solarized Dark
tmux set-option -p -t shogun:main @agent_id "shogun"

# Set Superpowers path as tmux global variable (agents query via: tmux display-message -p '#{@superpowers_path}')
if [ -n "$SUPERPOWERS_PATH" ]; then
    tmux set-option -g @superpowers_path "$SUPERPOWERS_PATH"
    tmux set-option -g @superpowers_version "$SUPERPOWERS_VERSION"
    tmux set-option -g @superpowers_source "$SUPERPOWERS_SOURCE"
fi

# Set state directory and code directory as tmux global variables
tmux set-option -g @shogunate_state "$SHOGUNATE_STATE"
tmux set-option -g @shogunate_code "$SCRIPT_DIR"

log_success "  └─ Shogun headquarters constructed"
log_info "  └─ State: ${SHOGUNATE_STATE}"
echo ""

# Get pane-base-index (in base-index 1 environments, panes start at 1,2,...)
PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5.1: Create multiagent Session (9 panes: karo + ashigaru1-7 + gunshi)
# ═══════════════════════════════════════════════════════════════════════════════
log_war "⚔️ Constructing karo, ashigaru, and gunshi formations (9 agents)..."

# Create first pane
if ! tmux new-session -d -s multiagent -n "agents" 2>/dev/null; then
    echo ""
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║  [ERROR] Failed to create tmux session 'multiagent'      ║"
    echo "  ║                                                          ║"
    echo "  ╠════════════════════════════════════════════════════════════╣"
    echo "  ║  An existing session may be running.                     ║"
    echo "  ║                                                          ║"
    echo "  ║                                                          ║"
    echo "  ║  Check: tmux ls                                          ║"
    echo "  ║  Kill:  tmux kill-session -t multiagent                  ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
fi

# DISPLAY_MODE: shout (default) or silent (--silent flag)
if [ "$SILENT_MODE" = true ]; then
    tmux set-environment -t multiagent DISPLAY_MODE "silent"
    echo "  📢 Display mode: Silent (no echo display)"
else
    tmux set-environment -t multiagent DISPLAY_MODE "shout"
fi

# Create 3x3 grid (9 panes total)
# Pane numbers depend on pane-base-index (0 or 1)
# First split into 3 columns
tmux split-window -h -t "multiagent:agents"
tmux split-window -h -t "multiagent:agents"

# Split each column into 3 rows
tmux select-pane -t "multiagent:agents.${PANE_BASE}"
tmux split-window -v
tmux split-window -v

tmux select-pane -t "multiagent:agents.$((PANE_BASE+3))"
tmux split-window -v
tmux split-window -v

tmux select-pane -t "multiagent:agents.$((PANE_BASE+6))"
tmux split-window -v
tmux split-window -v

# Pane labels, agent IDs, colors -- dynamically built from settings.yaml
PANE_LABELS=("karo")
AGENT_IDS=("karo")
PANE_COLORS=("red")
for _ai in $_ASHIGARU_IDS_STR; do
    PANE_LABELS+=("$_ai")
    AGENT_IDS+=("$_ai")
    PANE_COLORS+=("blue")
done
PANE_LABELS+=("gunshi")
AGENT_IDS+=("gunshi")
PANE_COLORS+=("yellow")

# Model name settings (for constant display in pane-border-format) - dynamically built
MODEL_NAMES=()
for _ai in "${AGENT_IDS[@]}"; do
    if [[ "$_ai" == "gunshi" || "$_ai" == "karo" ]]; then
        MODEL_NAMES+=("Opus")
    elif [ "$KESSEN_MODE" = true ]; then
        MODEL_NAMES+=("Opus")
    else
        MODEL_NAMES+=("Sonnet")
    fi
done

# Set model display names via CLI Adapter in unified format
# get_model_display_name(): returns short names like Sonnet, Opus+T, Haiku, Codex, Spark
if [ "$CLI_ADAPTER_LOADED" = true ]; then
    for i in "${!AGENT_IDS[@]}"; do
        _agent="${AGENT_IDS[$i]}"
        MODEL_NAMES[$i]=$(get_model_display_name "$_agent")
    done
fi

for i in "${!AGENT_IDS[@]}"; do
    p=$((PANE_BASE + i))
    tmux select-pane -t "multiagent:agents.${p}" -T "${MODEL_NAMES[$i]}"
    tmux set-option -p -t "multiagent:agents.${p}" @agent_id "${AGENT_IDS[$i]}"
    tmux set-option -p -t "multiagent:agents.${p}" @model_name "${MODEL_NAMES[$i]}"
    tmux set-option -p -t "multiagent:agents.${p}" @current_task ""
    PROMPT_STR=$(generate_prompt "${PANE_LABELS[$i]}" "${PANE_COLORS[$i]}" "$SHELL_SETTING")

    # Ashigaru → PROJECT_PATH (if provided), Karo/Gunshi → SCRIPT_DIR (plugin cache, already trusted)
    # All agents get SHOGUNATE_STATE env var for absolute paths to mutable state
    _agent_id="${AGENT_IDS[$i]}"
    # File-based env setup (safe from shell metacharacter issues)
    _agent_safe_prompt=$(printf '%s' "${PROMPT_STR}" | sed "s/'/'\\\\''/g")
    if [[ -n "$PROJECT_PATH" && "$_agent_id" == ashigaru* ]]; then
        cat > "${SHOGUNATE_STATE}/ipc/env/${_agent_id}.env" << ENVEOF
export SHOGUNATE_STATE="${SHOGUNATE_STATE}"
export PS1='${_agent_safe_prompt}'
cd "${PROJECT_PATH}"
ENVEOF
        tmux send-keys -t "multiagent:agents.${p}" "source ${SHOGUNATE_STATE}/ipc/env/${_agent_id}.env && clear" Enter
    else
        cat > "${SHOGUNATE_STATE}/ipc/env/${_agent_id}.env" << ENVEOF
export SHOGUNATE_STATE="${SHOGUNATE_STATE}"
export PS1='${_agent_safe_prompt}'
cd "$(pwd)"
ENVEOF
        tmux send-keys -t "multiagent:agents.${p}" "source ${SHOGUNATE_STATE}/ipc/env/${_agent_id}.env && clear" Enter
    fi
done

# Store project path as tmux variable for agents to query
if [ -n "$PROJECT_PATH" ]; then
    tmux set-option -g @project_path "$PROJECT_PATH"
    log_info "📂 Ashigaru working directory: ${PROJECT_PATH}"
fi

# Karo/gunshi pane background colors (visual distinction from ashigaru)
# Note: Commented out due to background color not inheriting in group sessions (2026-02-14)
# tmux select-pane -t "multiagent:agents.${PANE_BASE}" -P 'bg=#501515'          # karo: red
# tmux select-pane -t "multiagent:agents.$((PANE_BASE+8))" -P 'bg=#454510'      # gunshi: gold

# Display model name constantly via pane-border-format
tmux set-option -t multiagent -w pane-border-status top
tmux set-option -t multiagent -w pane-border-format '#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[default] (#{@model_name}) #{@current_task}'

log_success "  └─ Karo, ashigaru, and gunshi formations constructed"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Launch Claude Code (skip when -s / --setup-only)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$SETUP_ONLY" = false ]; then
    # CLI availability check (Multi-CLI support)
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _default_cli=$(get_cli_type "")
        if ! validate_cli_availability "$_default_cli"; then
            exit 1
        fi
    else
        if ! command -v claude &> /dev/null; then
            log_info "⚠️  claude command not found"
            echo "  Please re-run first_setup.sh:"
            echo "    ./first_setup.sh"
            exit 1
        fi
    fi

    # Clear stale flags from previous session
    rm -f /tmp/shogun_idle_*
    echo "idle flags cleared"

    log_war "👑 Summoning Claude Code for all forces..."

    # Shogun: Build command via CLI Adapter
    _shogun_cli_type="claude"
    _shogun_cmd="claude --model opus --dangerously-skip-permissions --setting-sources user"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _shogun_cli_type=$(get_cli_type "shogun")
        _shogun_cmd=$(build_cli_command "shogun")
    fi
    # --shogun-no-thinking -> temporarily set thinking to false in settings.yaml and let build_cli_command handle it
    if [ "$SHOGUN_NO_THINKING" = true ] && [ "$CLI_ADAPTER_LOADED" = true ]; then
        "$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml
f = '${CLI_ADAPTER_SETTINGS}'
with open(f) as fh: d = yaml.safe_load(fh) or {}
d.setdefault('cli',{}).setdefault('agents',{}).setdefault('shogun',{})['thinking'] = False
with open(f,'w') as fh: yaml.safe_dump(d, fh, default_flow_style=False, allow_unicode=True, sort_keys=False)
" 2>/dev/null
        _shogun_cmd=$(build_cli_command "shogun")
        log_info "  └─ Shogun settings.yaml thinking=false set"
    fi
    tmux set-option -p -t "shogun:main" @agent_cli "$_shogun_cli_type"
    tmux send-keys -t shogun:main "$_shogun_cmd"
    tmux send-keys -t shogun:main Enter
    _shogun_display=$(get_model_display_name "shogun" 2>/dev/null || echo "Opus")
    tmux set-option -p -t "shogun:main" @model_name "$_shogun_display" 2>/dev/null || true
    log_info "  └─ Shogun (${_shogun_cli_type} / ${_shogun_display}) summoned"

    # Brief wait (for stability)
    sleep 1

    # Karo (pane 0): Build command via CLI Adapter (default: Opus)
    p=$((PANE_BASE + 0))
    _karo_cli_type="claude"
    _karo_cmd="claude --model opus --dangerously-skip-permissions --setting-sources user"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _karo_cli_type=$(get_cli_type "karo")
        _karo_cmd=$(build_cli_command "karo")
    fi
    # Add initial prompt for Codex etc. (workaround for suggest UI freeze)
    _startup_prompt=$(get_startup_prompt "karo" 2>/dev/null)
    if [[ -n "$_startup_prompt" ]]; then
        _karo_cmd="$_karo_cmd \"$_startup_prompt\""
    fi
    tmux set-option -p -t "multiagent:agents.${p}" @agent_cli "$_karo_cli_type"
    tmux send-keys -t "multiagent:agents.${p}" "$_karo_cmd"
    tmux send-keys -t "multiagent:agents.${p}" Enter
    _karo_display=$(get_model_display_name "karo" 2>/dev/null || echo "Opus")
    tmux set-option -p -t "multiagent:agents.${p}" @model_name "$_karo_display" 2>/dev/null || true
    log_info "  └─ Karo (${_karo_display}) summoned"

    if [ "$KESSEN_MODE" = true ]; then
        # Battle formation: via CLI Adapter (claude forced to Opus)
        for i in $(seq 1 "$_ASHIGARU_COUNT"); do
            p=$((PANE_BASE + i))
            _ashi_cli_type="claude"
            _ashi_cmd="claude --model opus --dangerously-skip-permissions --setting-sources user"
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _ashi_cli_type=$(get_cli_type "ashigaru${i}")
                if [ "$_ashi_cli_type" = "claude" ]; then
                    _ashi_cmd="claude --model opus --dangerously-skip-permissions --setting-sources user"
                else
                    _ashi_cmd=$(build_cli_command "ashigaru${i}")
                fi
            fi
            # Add initial prompt for Codex etc. (workaround for suggest UI freeze)
            _startup_prompt=$(get_startup_prompt "ashigaru${i}" 2>/dev/null)
            if [[ -n "$_startup_prompt" ]]; then
                _ashi_cmd="$_ashi_cmd \"$_startup_prompt\""
            fi
            tmux set-option -p -t "multiagent:agents.${p}" @agent_cli "$_ashi_cli_type"
            tmux send-keys -t "multiagent:agents.${p}" "$_ashi_cmd"
            tmux send-keys -t "multiagent:agents.${p}" Enter
        done
        log_info "  └─ Ashigaru 1-${_ASHIGARU_COUNT} (battle formation) summoned"
    else
        # Peacetime formation: via CLI Adapter (default: all ashigaru=Sonnet)
        for i in $(seq 1 "$_ASHIGARU_COUNT"); do
            p=$((PANE_BASE + i))
            _ashi_cli_type="claude"
            _ashi_cmd="claude --model sonnet --dangerously-skip-permissions --setting-sources user"
            if [ "$CLI_ADAPTER_LOADED" = true ]; then
                _ashi_cli_type=$(get_cli_type "ashigaru${i}")
                _ashi_cmd=$(build_cli_command "ashigaru${i}")
            fi
            # Add initial prompt for Codex etc. (workaround for suggest UI freeze)
            _startup_prompt=$(get_startup_prompt "ashigaru${i}" 2>/dev/null)
            if [[ -n "$_startup_prompt" ]]; then
                _ashi_cmd="$_ashi_cmd \"$_startup_prompt\""
            fi
            tmux set-option -p -t "multiagent:agents.${p}" @agent_cli "$_ashi_cli_type"
            tmux send-keys -t "multiagent:agents.${p}" "$_ashi_cmd"
            tmux send-keys -t "multiagent:agents.${p}" Enter
        done
        log_info "  └─ Ashigaru 1-${_ASHIGARU_COUNT} (peacetime formation) summoned"
    fi

    # Gunshi (pane _ASHIGARU_COUNT+1): Opus Thinking -- dedicated strategy planning and design decisions
    p=$((PANE_BASE + _ASHIGARU_COUNT + 1))
    _gunshi_cli_type="claude"
    _gunshi_cmd="claude --model opus --dangerously-skip-permissions --setting-sources user"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _gunshi_cli_type=$(get_cli_type "gunshi")
        _gunshi_cmd=$(build_cli_command "gunshi")
    fi
    # Add initial prompt for Codex etc. (workaround for suggest UI freeze)
    _startup_prompt=$(get_startup_prompt "gunshi" 2>/dev/null)
    if [[ -n "$_startup_prompt" ]]; then
        _gunshi_cmd="$_gunshi_cmd \"$_startup_prompt\""
    fi
    tmux set-option -p -t "multiagent:agents.${p}" @agent_cli "$_gunshi_cli_type"
    tmux send-keys -t "multiagent:agents.${p}" "$_gunshi_cmd"
    tmux send-keys -t "multiagent:agents.${p}" Enter
    _gunshi_display=$(get_model_display_name "gunshi" 2>/dev/null || echo "Opus+T")
    tmux set-option -p -t "multiagent:agents.${p}" @model_name "$_gunshi_display" 2>/dev/null || true
    log_info "  └─ Gunshi (${_gunshi_display}) summoned"

    if [ "$KESSEN_MODE" = true ]; then
        log_success "✅ Deployed in battle formation! All forces on Opus!"
    else
        log_success "✅ Deployed in peacetime formation (karo=Opus, ashigaru=Sonnet, gunshi=Opus)"
    fi
    if [ -n "$SUPERPOWERS_PATH" ]; then
        log_success "📦 Superpowers: v${SUPERPOWERS_VERSION} (${SUPERPOWERS_SOURCE})"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6.5: Load instructions into each agent
    # ═══════════════════════════════════════════════════════════════════════════
    log_war "📜 Loading instructions into each agent..."
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # Ninja Warrior (syntax-samurai/ryu - CC0 1.0 Public Domain)
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;35m  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m  │\033[0m                              \033[1;37m[ NINJA WARRIOR ]\033[0m  Ryu Hayabusa (CC0 Public Domain)                        \033[1;35m│\033[0m"
    echo -e "\033[1;35m  └────────────────────────────────────────────────────────────────────────────────────────────────────────────┘\033[0m"

    cat << 'NINJA_EOF'
...................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░▒▒▒▒          ▒▒▒▒▒▒▒▒░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒                             ...................................
..................................░░░░░░░░░░░░░░▒▒▒▒               ▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                ...................................
..................................░░░░░░░░░░░░░▒▒▒                    ▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                    ...................................
..................................░░░░░░░░░░░░▒                            ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                        ...................................
..................................░░░░░░░░░░░      ░░░░░░░░░░░░░                                      ░░░░░░░░░░░░       ▒          ...................................
..................................░░░░░░░░░░ ▒    ░░░▓▓▓▓▓▓▓▓▓▓▓▓░░                                 ░░░░░░░░░░░░░░░ ░               ...................................
..................................░░░░░░░░░░     ░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░                          ░░░░░░░░░░░░░░░░░░░                ...................................
..................................░░░░░░░░░ ▒  ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░             ░░▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░  ░   ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░ ░  ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░  ░    ▒        ...................................
..................................░░░░░░░░░▒  ░ ░               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░                 ░            ...................................
.................................░░░░░░░░░░   ░░░  ░                 ▓▓▓▓▓▓▓▓░▓▓▓▓░░░▓░░░░░░▓▓▓▓▓                    ░ ░   ▒         ..................................
.................................░░░░░░░░▒▒   ░░░░░ ░                  ▓▓▓▓▓▓░▓▓▓▓░░▓▓▓░░░░░░▓▓                    ░  ░ ░  ▒         ..................................
.................................░░░░░░░░▒    ░░░░░░░░░ ░                 ░▓░░▓▓▓▓▓░▓▓▓░░░░░                   ░ ░░ ░░ ░   ▒         ..................................
.................................░░░░░░░▒▒    ░░░░░░░   ░░                    ▓▓▓▓▓▓▓▓▓░░                   ░░    ░ ░░ ░    ▒        ..................................
.................................░░░░░░░▒▒    ░░░░░░░░░░                      ░▓▓▓▓▓▓▓░░░                     ░░░  ░  ░ ░   ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░                         ░░░▓▓▓░▓░░░░      ░                  ░ ░░ ░    ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░░     ▓▓        ▓  ░░ ░░░░░░░░░░░░░  ░   ░░  ▓        █▓       ░  ░ ░   ▒▒       ..................................
..................................░░░░░▒ ▒    ░░░░░░░░  ▓▓██  ▓  ██ ██▓  ▓ ░░░▓░  ░ ░ ░░░░  ▓   ██ ▓█  ▓  ██▓▓  ░░░░  ░ ░    ▒      ...................................
..................................░░░░░▒ ▒▒   ░░░░░░░░░  ▓██  ▓▓  ▓ ██▓  ▓░░░░▓▓░  ░░░░░░░░ ▓  ▓██ ▓   ▓  ██▓▓ ░░░░░░░ ░     ▒      ...................................
..................................░░░░░  ▒░   ░░░░░░░▓░░ ▓███  ▓▓▓▓ ███░  ░░░░▓▓░░░░░░░░░░    ░▓██  ▓▓▓  ███▓ ░░▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░  ▒░    ░░░░▓▓▓▓▓▓░  ███    ██      ░░░░░▓▓▓▓▓░░░░░░░     ███   ████ ░░▓▓▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░ ▒ ░▒    ░░▓▓▓▓▓▓▓▓▓▓ ██████  ▓▓▓░░ ░░░░▓▓▓▓▓▓░░░░░░░░░▓▓▓   █████  ▓▓▓▓▓▓▓░░░░    ▒▒ ▒      ...................................
...................................░░░░ ░ ░░     ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█░░░░░░░▓▓▓▓▓▓▓░░░░ ░░   ░░▓░▓▓░░░░░░░▓▓▓▓▓▓░░      ▒▒ ▒      ...................................
...................................░░░░ ░ ░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██  ░░░░░░░▓▓▓▓▓▓▓░░░░  ░░░░░   ░░░░░░░░░▓▓▓▓▓░░ ░    ▒▒  ▒      ...................................
...................................░░░░▒░░▒░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░▓▓▓▓▓▓▓▓░░░  ░░░░░░░░░░░░░░░░░░▓▓░░░░      ▒▒  ▒     ....................................
...................................░░░░▒░░ ░░       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░▓▓▓▓▓▓▓▓▓░░░░  ░░░░░░░░░░░░░░░░░░░░░        ▒▒  ▒     ....................................
...................................░░░░░░░ ▒░▒       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░▓▓▓░░   ░░░░░  ░░░░░░░░░░░░░░░░░░░░         ▒   ▒     ....................................
...................................░░░░░░░░░░░           ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓              ░    ░░░░░░░░░░░░░░░            ▒   ▒     ....................................
....................................░░░░░░░░░░░▒  ▒▒        ▓▓▓▓▓▓▓▓▓▓▓▓▓  ░░░░░░░░░░▒▒                         ▒▒▒▒▒   ▒    ▒    .....................................
....................................░░░░░░░░░░ ░▒ ▒▒▒░░░        ▓▓▓▓▓▓   ░░░░░░░░░░░░░▒▒▒      ▒▒▒▒▒░░░░▒▒    ▒▒▒▒▒▒▒  ▒▒    ▒    .....................................
....................................░░░░░░░░░░ ░░░ ▒▒▒░░░░░░          ░░░░░ ░░░░░░░░░░▒░▒     ▒▒▒▒▒▒░░░░░░▒▒▒▒▒░▒▒▒▒   ▒▒         .....................................
.....................................░░░░░░░░░░ ░░░░░  ▒▒░░░░░░░░░░░░░    ░░░░░░░░░  ▒░▒▒    ▒▒▒▒▒░░░░▒▒▒▒▒▒░░▒▒▒   ▒▒▒         ......................................
.....................................░░░░░░░░░░░░░░░░░░  ▒░░░░░░░░░░░   ░░░░░░░░░░░░░░   ▒   ▒▒▒▒▒▒▒░▒▒▒▒▒▒░░░░▒▒▒   ▒▒          ......................................
.....................................░░░░░░░░░░░ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░      ▒▒▒▒▒▒▒    ▒  ░░░▒▒▒▒  ▒▒▒          ......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ▒░▒▒▒ ▒▒▒    ▒░░░░░░░░░░▒   ▒▒▒▒      ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒  ░░▒▒▒▒▒▒░░░░░░░░░░░░░▒  ░▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒ ▒▒░▒▒▒▒▒▒▒░░░░░░░░░░  ░░▒▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒ ░▒▒▒▒▒▒▒▒▒░░▒░░░░░░ ░░▒▒▒▒▒▒      ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░▒░▒▒▒ ▒▒▒▒▒░░░░░░░░░▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒░▒▒▒▒▒     ░░░░░░░░▒▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒░░▒░▒▒▒▒▒▒  ▒░░░░░░░▒▒▒▒▒▒        ▒     .......................................
NINJA_EOF

    echo ""
    echo -e "                                    \033[1;35m\"Conquer all under heaven! Seize victory!\"\033[0m"
    echo ""
    echo -e "                               \033[0;36m[ASCII Art: syntax-samurai/ryu - CC0 1.0 Public Domain]\033[0m"
    echo ""

    echo "  Waiting for Claude Code to start (up to 30 seconds)..."

    # Confirm shogun startup (wait up to 30 seconds)
    for i in {1..30}; do
        if tmux capture-pane -t shogun:main -p | grep -q "bypass permissions"; then
            echo "  └─ Shogun Claude Code startup confirmed (${i}s)"
            break
        fi
        sleep 1
    done

    # ═══════════════════════════════════════════════════════════════════
    # STEP 6.6: Start inbox_watcher (all agents)
    # ═══════════════════════════════════════════════════════════════════
    log_info "📬 Starting mailbox watchers..."

    # Initialize inbox directory (create on Linux FS at symlink target)
    mkdir -p "$SCRIPT_DIR/logs"
    for agent in shogun karo $_ASHIGARU_IDS_STR gunshi; do
        [ -f "$SCRIPT_DIR/queue/inbox/${agent}.yaml" ] || echo "messages:" > "$SCRIPT_DIR/queue/inbox/${agent}.yaml"
    done

    # Kill existing watchers and orphan inotifywait/fswatch processes
    pkill -f "inbox_watcher.sh" 2>/dev/null || true
    pkill -f "inotifywait.*queue/inbox" 2>/dev/null || true
    pkill -f "fswatch.*queue/inbox" 2>/dev/null || true
    sleep 1

    # Shogun's watcher (needed for auto-wakeup on ntfy messages)
    # Safe mode: phase2/phase3 escalation disabled, timeout periodic processing disabled (event-driven only)
    _shogun_watcher_cli=$(tmux show-options -p -t "shogun:main" -v @agent_cli 2>/dev/null || echo "claude")
    nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 ASW_DISABLE_NORMAL_NUDGE=0 \
        bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" shogun "shogun:main" "$_shogun_watcher_cli" \
        >> "$SCRIPT_DIR/logs/inbox_watcher_shogun.log" 2>&1 &
    disown

    # Karo's watcher
    _karo_watcher_cli=$(tmux show-options -p -t "multiagent:agents.${PANE_BASE}" -v @agent_cli 2>/dev/null || echo "claude")
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" karo "multiagent:agents.${PANE_BASE}" "$_karo_watcher_cli" \
        >> "$SCRIPT_DIR/logs/inbox_watcher_karo.log" 2>&1 &
    disown

    # Ashigaru watchers
    for i in $(seq 1 "$_ASHIGARU_COUNT"); do
        p=$((PANE_BASE + i))
        _ashi_watcher_cli=$(tmux show-options -p -t "multiagent:agents.${p}" -v @agent_cli 2>/dev/null || echo "claude")
        nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "ashigaru${i}" "multiagent:agents.${p}" "$_ashi_watcher_cli" \
            >> "$SCRIPT_DIR/logs/inbox_watcher_ashigaru${i}.log" 2>&1 &
        disown
    done

    # Gunshi's watcher
    p=$((PANE_BASE + _ASHIGARU_COUNT + 1))
    _gunshi_watcher_cli=$(tmux show-options -p -t "multiagent:agents.${p}" -v @agent_cli 2>/dev/null || echo "claude")
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "gunshi" "multiagent:agents.${p}" "$_gunshi_watcher_cli" \
        >> "$SCRIPT_DIR/logs/inbox_watcher_gunshi.log" 2>&1 &
    disown

    log_success "  └─ inbox_watcher started for $((_ASHIGARU_COUNT + 3)) agents (shogun+karo+ashigaru${_ASHIGARU_COUNT}+gunshi)"

    # STEP 6.7 deprecated -- each agent autonomously loads its own instructions/*.md
    # via CLAUDE.md Session Start (step 1: tmux agent_id). Verified (2026-02-08).
    log_info "📜 Instruction loading handled autonomously by each agent (CLAUDE.md Session Start)"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.7.5: Archive old ntfy_inbox messages (processed entries older than 7 days)
# ═══════════════════════════════════════════════════════════════════════════════
if [ -f ./queue/ntfy_inbox.yaml ]; then
    _archive_result=$(python3 -c "
import yaml, sys
from datetime import datetime, timedelta, timezone

INBOX = './queue/ntfy_inbox.yaml'
ARCHIVE = './queue/ntfy_inbox_archive.yaml'
DAYS = 7

with open(INBOX) as f:
    data = yaml.safe_load(f) or {}

entries = data.get('inbox', []) or []
if not entries:
    sys.exit(0)

cutoff = datetime.now(timezone(timedelta(hours=9))) - timedelta(days=DAYS)
recent, old = [], []

for e in entries:
    ts = e.get('timestamp', '')
    try:
        dt = datetime.fromisoformat(str(ts))
        if dt < cutoff and e.get('status') == 'processed':
            old.append(e)
        else:
            recent.append(e)
    except Exception:
        recent.append(e)

if not old:
    sys.exit(0)

# Append to archive
try:
    with open(ARCHIVE) as f:
        archive = yaml.safe_load(f) or {}
except FileNotFoundError:
    archive = {}
archive_entries = archive.get('inbox', []) or []
archive_entries.extend(old)
with open(ARCHIVE, 'w') as f:
    yaml.dump({'inbox': archive_entries}, f, allow_unicode=True, default_flow_style=False)

# Write back recent only
with open(INBOX, 'w') as f:
    yaml.dump({'inbox': recent}, f, allow_unicode=True, default_flow_style=False)

print(f'{len(old)} archived, {len(recent)} retained')
" 2>/dev/null) || true
    if [ -n "$_archive_result" ]; then
        log_info "📱 ntfy_inbox cleanup: $_archive_result -> ntfy_inbox_archive.yaml"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.8: Start ntfy input listener
# ═══════════════════════════════════════════════════════════════════════════════
NTFY_TOPIC=$(grep 'ntfy_topic:' ./config/settings.yaml 2>/dev/null | awk '{print $2}' | tr -d '"')
if [ -n "$NTFY_TOPIC" ]; then
    pkill -f "ntfy_listener.sh" 2>/dev/null || true
    [ ! -f ./queue/ntfy_inbox.yaml ] && echo "inbox:" > ./queue/ntfy_inbox.yaml
    nohup bash "$SCRIPT_DIR/scripts/ntfy_listener.sh" &>/dev/null &
    disown
    log_info "📱 ntfy input listener started (topic: $NTFY_TOPIC)"
else
    log_info "📱 ntfy not configured, skipping listener"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: Environment Check & Completion Message
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🔍 Verifying formation..."
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📺 Tmux Formation (Sessions)                              │"
echo "  └──────────────────────────────────────────────────────────┘"
tmux list-sessions | sed 's/^/     /'
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📋 Battle Formation Map                                  │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "     [shogun session] Shogun Headquarters"
echo "     ┌─────────────────────────────┐"
echo "     │  Pane 0: Shogun             │  <- Supreme commander / project lead"
echo "     └─────────────────────────────┘"
echo ""
echo "     [multiagent session] Karo, Ashigaru & Gunshi Formation (3x3 = 9 panes)"
echo "     ┌─────────┬─────────┬─────────┐"
echo "     │  karo   │ashigaru3│ashigaru6│"
echo "     │ (chief) │  (a3)   │  (a6)   │"
echo "     ├─────────┼─────────┼─────────┤"
echo "     │ashigaru1│ashigaru4│ashigaru7│"
echo "     │  (a1)   │  (a4)   │  (a7)   │"
echo "     ├─────────┼─────────┼─────────┤"
echo "     │ashigaru2│ashigaru5│ gunshi  │"
echo "     │  (a2)   │  (a5)   │ (strat) │"
echo "     └─────────┴─────────┴─────────┘"
echo ""

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║  🏯 Deployment ready! Conquer all under heaven!             ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

if [ "$SETUP_ONLY" = true ]; then
    echo "  ⚠️  Setup-only mode: Claude Code has not been launched"
    echo ""
    echo "  To launch Claude Code manually:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  # Summon the shogun                                     │"
    echo "  │  tmux send-keys -t shogun:main \\                         │"
    echo "  │    'claude --dangerously-skip-permissions' Enter         │"
    echo "  │                                                          │"
    echo "  │  # Summon karo and ashigaru at once                       │"
    echo "  │  for p in \$(seq $PANE_BASE $((PANE_BASE+8))); do                                 │"
    echo "  │      tmux send-keys -t multiagent:agents.\$p \\            │"
    echo "  │      'claude --dangerously-skip-permissions' Enter       │"
    echo "  │  done                                                    │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
fi

echo "  Next steps:"
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  Attach to shogun headquarters and begin commands:       │"
echo "  │     tmux attach-session -t shogun   (or: css)            │"
echo "  │                                                          │"
echo "  │  View the karo/ashigaru formation:                       │"
echo "  │     tmux attach-session -t multiagent   (or: csm)       │"
echo "  │                                                          │"
echo "  │  Note: All agents have loaded their instructions.        │"
echo "  │  You can begin issuing commands immediately.             │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "  ════════════════════════════════════════════════════════════"
echo "   Conquer all under heaven! Seize victory! (Tenka Fubu!)"
echo "  ════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Open tabs in Windows Terminal (-t option only)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$OPEN_TERMINAL" = true ]; then
    log_info "📺 Opening tabs in Windows Terminal..."

    # Check if Windows Terminal is available
    if command -v wt.exe &> /dev/null; then
        wt.exe -w 0 new-tab wsl.exe -e bash -c "tmux attach-session -t shogun" \; new-tab wsl.exe -e bash -c "tmux attach-session -t multiagent"
        log_success "  └─ Terminal tabs opened"
    else
        log_info "  └─ wt.exe not found. Please attach manually."
    fi
    echo ""
fi
