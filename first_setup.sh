#!/usr/bin/env bash
# ============================================================
# first_setup.sh - multi-agent-shogun Initial Setup Script
# Environment Setup Tool for Ubuntu / WSL / Mac
# ============================================================
# Usage:
#   chmod +x first_setup.sh
#   ./first_setup.sh
# ============================================================

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Log functions with icons
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}\n"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Result tracking variables
RESULTS=()
HAS_ERROR=false

echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║  🏯 multi-agent-shogun Installer                              ║"
echo "  ║     Initial Setup Script for Ubuntu / WSL                    ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  This script is for initial setup."
echo "  It checks dependencies and creates the directory structure."
echo ""
echo "  Install location: $SCRIPT_DIR"
echo ""

# ============================================================
# STEP 1: OS Check
# ============================================================
log_step "STEP 1: System Environment Check"

# Get OS info
UNAME_S="$(uname -s)"
if [ "$UNAME_S" = "Darwin" ]; then
    OS_NAME="macOS"
    OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    log_info "OS: $OS_NAME $OS_VERSION"
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
    OS_VERSION=$VERSION_ID
    log_info "OS: $OS_NAME $OS_VERSION"
else
    OS_NAME="Unknown"
    log_warn "Could not retrieve OS information"
fi

# WSL check
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    log_info "Environment: WSL (Windows Subsystem for Linux)"
    IS_WSL=true
elif [ "$UNAME_S" = "Darwin" ]; then
    log_info "Environment: macOS"
else
    log_info "Environment: Native Linux"
fi

RESULTS+=("System environment: OK")

# ============================================================
# STEP 2: tmux Check / Install
# ============================================================
log_step "STEP 2: tmux Check"

if command -v tmux &> /dev/null; then
    TMUX_VERSION=$(tmux -V | awk '{print $2}')
    log_success "tmux is already installed (v$TMUX_VERSION)"
    RESULTS+=("tmux: OK (v$TMUX_VERSION)")
else
    log_warn "tmux is not installed"
    echo ""

    # Check if Ubuntu/Debian-based
    if command -v apt-get &> /dev/null; then
        log_info "Installing tmux..."
        if ! sudo -n apt-get update -qq 2>/dev/null; then
            if ! sudo apt-get update -qq 2>/dev/null; then
                log_error "Failed to run sudo. Please run directly from the terminal"
                RESULTS+=("tmux: Install failed (sudo failed)")
                HAS_ERROR=true
            fi
        fi

        if [ "$HAS_ERROR" != true ]; then
            if ! sudo -n apt-get install -y tmux 2>/dev/null; then
                if ! sudo apt-get install -y tmux 2>/dev/null; then
                    log_error "Failed to install tmux"
                    RESULTS+=("tmux: Install failed")
                    HAS_ERROR=true
                fi
            fi
        fi

        if command -v tmux &> /dev/null; then
            TMUX_VERSION=$(tmux -V | awk '{print $2}')
            log_success "tmux installation complete (v$TMUX_VERSION)"
            RESULTS+=("tmux: Installed (v$TMUX_VERSION)")
        else
            log_error "Failed to install tmux"
            RESULTS+=("tmux: Install failed")
            HAS_ERROR=true
        fi
    else
        log_error "apt-get not found. Please install tmux manually"
        echo ""
        echo "  Installation methods:"
        echo "    Ubuntu/Debian: sudo apt-get install tmux"
        echo "    Fedora:        sudo dnf install tmux"
        echo "    macOS:         brew install tmux"
        RESULTS+=("tmux: Not installed (manual install required)")
        HAS_ERROR=true
    fi
fi

# ============================================================
# STEP 3: tmux Mouse Scroll Configuration
# ============================================================
log_step "STEP 3: tmux Mouse Scroll Configuration"

TMUX_CONF="$HOME/.tmux.conf"
TMUX_MOUSE_SETTING="set -g mouse on"

if [ -f "$TMUX_CONF" ] && grep -qF "$TMUX_MOUSE_SETTING" "$TMUX_CONF" 2>/dev/null; then
    log_info "tmux mouse setting already exists in ~/.tmux.conf"
else
    log_info "Adding '$TMUX_MOUSE_SETTING' to ~/.tmux.conf..."
    echo "" >> "$TMUX_CONF"
    echo "# Enable mouse scroll (added by first_setup.sh)" >> "$TMUX_CONF"
    echo "$TMUX_MOUSE_SETTING" >> "$TMUX_CONF"
    log_success "Added tmux mouse setting"
fi

# If tmux is running, apply immediately
if command -v tmux &> /dev/null && tmux list-sessions &> /dev/null; then
    log_info "tmux is running, applying settings immediately..."
    if tmux source-file "$TMUX_CONF" 2>/dev/null; then
        log_success "Reloaded tmux configuration"
    else
        log_warn "Failed to reload tmux configuration (run tmux source-file ~/.tmux.conf manually)"
    fi
else
    log_info "tmux is not running, settings will apply on next launch"
fi

RESULTS+=("tmux mouse setting: OK")

# ============================================================
# STEP 4: Node.js Check
# ============================================================
log_step "STEP 4: Node.js Check"

if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    log_success "Node.js is already installed ($NODE_VERSION)"

    # Version check (18+ recommended)
    NODE_MAJOR=$(echo $NODE_VERSION | cut -d'.' -f1 | tr -d 'v')
    if [ "$NODE_MAJOR" -lt 18 ]; then
        log_warn "Node.js 18+ is recommended (current: $NODE_VERSION)"
        RESULTS+=("Node.js: OK (v$NODE_MAJOR - upgrade recommended)")
    else
        RESULTS+=("Node.js: OK ($NODE_VERSION)")
    fi
else
    log_warn "Node.js is not installed"
    echo ""

    # Check if nvm is already installed
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        log_info "nvm is already installed. Setting up Node.js..."
        \. "$NVM_DIR/nvm.sh"
    else
        # Auto-install nvm
        log_info "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi

    # Install Node.js if nvm is available
    if command -v nvm &> /dev/null; then
        log_info "Installing Node.js 20..."
        nvm install 20 || true
        nvm use 20 || true

        if command -v node &> /dev/null; then
            NODE_VERSION=$(node -v)
            log_success "Node.js installation complete ($NODE_VERSION)"
            RESULTS+=("Node.js: Installed ($NODE_VERSION)")
        else
            log_error "Failed to install Node.js"
            RESULTS+=("Node.js: Install failed")
            HAS_ERROR=true
        fi
    elif [ "$HAS_ERROR" != true ]; then
        log_error "Failed to install nvm"
        echo ""
        echo "  Please install manually:"
        echo "    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
        echo "    source ~/.bashrc"
        echo "    nvm install 20"
        echo ""
        RESULTS+=("Node.js: Not installed (nvm failed)")
        HAS_ERROR=true
    fi
fi

# npm check
if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm -v)
    log_success "npm is already installed (v$NPM_VERSION)"
else
    if command -v node &> /dev/null; then
        log_warn "npm not found (should have been installed with Node.js)"
    fi
fi

# ============================================================
# STEP 4.5: Python3 / venv / flock / file-watcher Check
# ============================================================
log_step "STEP 4.5: Python3 / venv / flock / file-watcher Check"

# Detect OS
SETUP_OS="$(uname -s)"

# --- python3 ---
if command -v python3 &> /dev/null; then
    PY3_VERSION=$(python3 --version 2>&1)
    log_success "python3 is already installed ($PY3_VERSION)"
    RESULTS+=("python3: OK ($PY3_VERSION)")
else
    log_warn "python3 is not installed"
    if command -v apt-get &> /dev/null; then
        log_info "Installing python3..."
        sudo apt-get update -qq 2>/dev/null
        if sudo apt-get install -y python3 2>/dev/null; then
            PY3_VERSION=$(python3 --version 2>&1)
            log_success "python3 installation complete ($PY3_VERSION)"
            RESULTS+=("python3: Installed ($PY3_VERSION)")
        else
            log_error "Failed to install python3"
            RESULTS+=("python3: Install failed")
            HAS_ERROR=true
        fi
    elif [ "$SETUP_OS" = "Darwin" ]; then
        log_error "python3 is not installed"
        echo "  macOS: brew install python3 or install from https://www.python.org/"
        RESULTS+=("python3: Not installed (manual install required)")
        HAS_ERROR=true
    else
        log_error "Please install python3 manually"
        RESULTS+=("python3: Not installed (manual install required)")
        HAS_ERROR=true
    fi
fi

# --- Python venv + PyYAML (via requirements.txt) ---
VENV_DIR="$SCRIPT_DIR/.venv"
if [ -f "$VENV_DIR/bin/python3" ] && "$VENV_DIR/bin/python3" -c "import yaml" 2>/dev/null; then
    log_success "Python venv + PyYAML is already set up"
    RESULTS+=("venv + PyYAML: OK")
else
    log_info "Setting up Python venv..."
    if command -v python3 &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq 2>/dev/null
            sudo apt-get install -y python3-venv 2>/dev/null
        fi
        if python3 -m venv "$VENV_DIR" 2>/dev/null; then
            log_success "venv created: $VENV_DIR"
            if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
                if "$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" 2>/dev/null; then
                    log_success "PyYAML installation complete (venv)"
                    RESULTS+=("venv + PyYAML: Setup complete")
                else
                    log_error "pip install failed"
                    RESULTS+=("venv + PyYAML: pip failed")
                    HAS_ERROR=true
                fi
            else
                log_warn "requirements.txt not found"
                RESULTS+=("venv + PyYAML: requirements.txt missing")
                HAS_ERROR=true
            fi
        else
            log_error "python3 -m venv failed"
            echo "  The python3-venv package may be required:"
            echo "    Ubuntu/Debian: sudo apt-get install python3-venv"
            RESULTS+=("venv: Creation failed")
            HAS_ERROR=true
        fi
    else
        log_error "python3 is required (please install via the step above)"
        RESULTS+=("venv: Skipped (python3 not found)")
        HAS_ERROR=true
    fi
fi

# --- flock ---
if command -v flock &> /dev/null; then
    log_success "flock is already installed"
    RESULTS+=("flock: OK")
else
    log_warn "flock is not installed"
    if [ "$SETUP_OS" = "Darwin" ]; then
        echo "  macOS: brew install flock"
        RESULTS+=("flock: Not installed (brew install flock)")
    elif command -v apt-get &> /dev/null; then
        log_info "util-linux (includes flock) is usually pre-installed"
        echo "  sudo apt-get install util-linux"
        RESULTS+=("flock: Not installed (apt-get install util-linux)")
    else
        echo "  Please install manually"
        RESULTS+=("flock: Not installed")
    fi
    HAS_ERROR=true
fi

# --- Bash version check (macOS ships with bash 3.2) ---
if [ "$SETUP_OS" = "Darwin" ]; then
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        log_warn "bash 3.2 detected (macOS default)."
        log_warn "This tool requires bash 4.0+."
        log_warn "Install: brew install bash"
        log_warn "Then reopen terminal and retry."
        HAS_ERROR=true
    else
        log_success "bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} detected"
    fi
fi

# --- coreutils (recommended for macOS) ---
if [ "$SETUP_OS" = "Darwin" ]; then
    if ! command -v gtimeout &>/dev/null; then
        log_warn "GNU coreutils not found. inbox_watcher will use bash fallback for timeout."
        log_warn "Recommended: brew install coreutils"
        RESULTS+=("coreutils: Not installed (brew install coreutils)")
    else
        log_success "GNU coreutils detected (gtimeout available)"
    fi
fi

# --- File watcher (inotifywait / fswatch) ---
if [ "$SETUP_OS" = "Darwin" ]; then
    # macOS: fswatch
    if command -v fswatch &> /dev/null; then
        log_success "fswatch is already installed (macOS file watcher)"
        RESULTS+=("file-watcher: OK (fswatch)")
    else
        log_warn "fswatch is not installed"
        echo "  macOS: brew install fswatch"
        RESULTS+=("file-watcher: Not installed (brew install fswatch)")
        HAS_ERROR=true
    fi
else
    # Linux: inotifywait
    if command -v inotifywait &> /dev/null; then
        log_success "inotify-tools is already installed"
        RESULTS+=("file-watcher: OK (inotifywait)")
    else
        log_warn "inotify-tools is not installed"
        if command -v apt-get &> /dev/null; then
            log_info "Installing inotify-tools..."
            if sudo apt-get install -y inotify-tools 2>/dev/null; then
                log_success "inotify-tools installation complete"
                RESULTS+=("file-watcher: Installed (inotifywait)")
            else
                log_error "Failed to install inotify-tools"
                RESULTS+=("file-watcher: Install failed")
                HAS_ERROR=true
            fi
        else
            log_error "Please install inotify-tools manually"
            RESULTS+=("file-watcher: Not installed")
            HAS_ERROR=true
        fi
    fi
fi

# ============================================================
# STEP 5: Claude Code CLI Check (Native version)
# Note: npm version is officially deprecated. Use the native version.
#       Node.js is still needed for MCP servers (via npx).
# ============================================================
log_step "STEP 5: Claude Code CLI Check"

# Include ~/.local/bin in PATH to detect existing native installations
export PATH="$HOME/.local/bin:$PATH"

NEED_CLAUDE_INSTALL=false
HAS_NPM_CLAUDE=false

if command -v claude &> /dev/null; then
    # claude command exists -> check if it actually works
    CLAUDE_VERSION=$(claude --version 2>&1)
    CLAUDE_PATH=$(which claude 2>/dev/null)

    if [ $? -eq 0 ] && [ "$CLAUDE_VERSION" != "unknown" ] && [[ "$CLAUDE_VERSION" != *"not found"* ]]; then
        # Working claude found -> determine if npm or native version
        if echo "$CLAUDE_PATH" | grep -qi "npm\|node_modules\|AppData"; then
            # npm version is running
            HAS_NPM_CLAUDE=true
            log_warn "npm version of Claude Code CLI detected (officially deprecated)"
            log_info "Detected path: $CLAUDE_PATH"
            log_info "Version: $CLAUDE_VERSION"
            echo ""
            echo "  The npm version is officially deprecated."
            echo "  It is recommended to install the native version and uninstall the npm version."
            echo ""
            if [ ! -t 0 ]; then
                REPLY="Y"
            else
                read -p "  Install the native version? [Y/n]: " REPLY
            fi
            REPLY=${REPLY:-Y}
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                NEED_CLAUDE_INSTALL=true
                # npm version uninstall guidance
                echo ""
                log_info "Please uninstall the npm version first:"
                if echo "$CLAUDE_PATH" | grep -qi "mnt/c\|AppData"; then
                    echo "  In Windows PowerShell:"
                    echo "    npm uninstall -g @anthropic-ai/claude-code"
                else
                    echo "    npm uninstall -g @anthropic-ai/claude-code"
                fi
                echo ""
            else
                log_warn "Skipped migration to native version (continuing with npm version)"
                RESULTS+=("Claude Code CLI: OK (npm version - migration recommended)")
            fi
        else
            # Native version is working correctly
            log_success "Claude Code CLI is already installed (native version)"
            log_info "Version: $CLAUDE_VERSION"
            RESULTS+=("Claude Code CLI: OK")
        fi
    else
        # Found via command -v but doesn't work (e.g. npm version without Node.js)
        log_warn "Claude Code CLI found but not functioning correctly"
        log_info "Detected path: $CLAUDE_PATH"
        if echo "$CLAUDE_PATH" | grep -qi "npm\|node_modules\|AppData"; then
            HAS_NPM_CLAUDE=true
            log_info "-> npm version (Node.js dependent) detected"
        else
            log_info "-> Failed to retrieve version"
        fi
        NEED_CLAUDE_INSTALL=true
    fi
else
    # claude command not found
    NEED_CLAUDE_INSTALL=true
fi

if [ "$NEED_CLAUDE_INSTALL" = true ]; then
    log_info "Installing native Claude Code CLI"
    log_info "Installing Claude Code CLI (native version)..."
    curl -fsSL https://claude.ai/install.sh | bash

    # Update PATH (may not be reflected immediately after install)
    export PATH="$HOME/.local/bin:$PATH"

    # Persist in .bashrc (prevent duplicate entries)
    if ! grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$HOME/.bashrc" 2>/dev/null; then
        echo '' >> "$HOME/.bashrc"
        echo '# Claude Code CLI PATH (added by first_setup.sh)' >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        log_info "Added ~/.local/bin to PATH in ~/.bashrc"
    fi

    if command -v claude &> /dev/null; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
        log_success "Claude Code CLI installation complete (native version)"
        log_info "Version: $CLAUDE_VERSION"
        RESULTS+=("Claude Code CLI: Installed")

        # Guidance if npm version remains
        if [ "$HAS_NPM_CLAUDE" = true ]; then
            echo ""
            log_info "The native version takes priority in PATH, so the npm version is disabled"
            log_info "To completely remove the npm version, run:"
            if echo "$CLAUDE_PATH" | grep -qi "mnt/c\|AppData"; then
                echo "  In Windows PowerShell:"
                echo "    npm uninstall -g @anthropic-ai/claude-code"
            else
                echo "    npm uninstall -g @anthropic-ai/claude-code"
            fi
        fi
    else
        log_error "Installation failed. Please check the path"
        log_info "Verify that ~/.local/bin is included in your PATH"
        RESULTS+=("Claude Code CLI: Install failed")
        HAS_ERROR=true
    fi
fi

# ============================================================
# STEP 6: Directory Structure Creation
# ============================================================
log_step "STEP 6: Directory Structure Creation"

# Required directories
DIRECTORIES=(
    "queue/tasks"
    "queue/reports"
    "config"
    "status"
    "instructions"
    "logs"
    "demo_output"
    "skills"
    "memory"
)

CREATED_COUNT=0
EXISTED_COUNT=0

for dir in "${DIRECTORIES[@]}"; do
    if [ ! -d "$SCRIPT_DIR/$dir" ]; then
        mkdir -p "$SCRIPT_DIR/$dir"
        log_info "Created: $dir/"
        CREATED_COUNT=$((CREATED_COUNT + 1))
    else
        EXISTED_COUNT=$((EXISTED_COUNT + 1))
    fi
done

if [ $CREATED_COUNT -gt 0 ]; then
    log_success "Created $CREATED_COUNT directories"
fi
if [ $EXISTED_COUNT -gt 0 ]; then
    log_info "$EXISTED_COUNT directories already exist"
fi

RESULTS+=("Directory structure: OK (created:$CREATED_COUNT, existing:$EXISTED_COUNT)")

# ============================================================
# STEP 7: Configuration File Initialization
# ============================================================
log_step "STEP 7: Configuration File Check"

# config/settings.yaml
if [ ! -f "$SCRIPT_DIR/config/settings.yaml" ]; then
    log_info "Creating config/settings.yaml..."
    cat > "$SCRIPT_DIR/config/settings.yaml" << EOF
# multi-agent-shogun configuration file

# Language setting
# ja: Sengoku English only (feudal tone, no parenthetical explanations)
# en: Sengoku English + plain translation in parentheses
# Other language codes (es, zh, ko, fr, de, etc.) also supported
language: ja

# Shell setting
# bash: bash prompt (default)
# zsh: zsh prompt
shell: bash

# Skill settings
skill:
  # Skill save path (saved with shogun- prefix)
  save_path: "~/.claude/skills/"

  # Local skill save path (project-specific)
  local_path: "$SCRIPT_DIR/skills/"

# Logging settings
logging:
  level: info  # debug | info | warn | error
  path: "$SCRIPT_DIR/logs/"
EOF
    log_success "settings.yaml created"
else
    log_info "config/settings.yaml already exists"
fi

# config/projects.yaml
if [ ! -f "$SCRIPT_DIR/config/projects.yaml" ]; then
    log_info "Creating config/projects.yaml..."
    cat > "$SCRIPT_DIR/config/projects.yaml" << 'EOF'
projects:
  - id: sample_project
    name: "Sample Project"
    path: "/path/to/your/project"
    priority: high
    status: active

current_project: sample_project
EOF
    log_success "projects.yaml created"
else
    log_info "config/projects.yaml already exists"
fi

# memory/MEMORY.md (Shogun persistent memory -- do not overwrite existing files)
if [ ! -f "$SCRIPT_DIR/memory/MEMORY.md" ]; then
    log_info "Creating memory/MEMORY.md..."
    cp "$SCRIPT_DIR/memory/MEMORY.md.sample" "$SCRIPT_DIR/memory/MEMORY.md"
    log_success "memory/MEMORY.md created (copied from MEMORY.md.sample)"
    log_info "Edit memory/MEMORY.md and fill in your information"
else
    log_info "memory/MEMORY.md already exists (skipping)"
fi

# memory/global_context.md (system-wide context)
if [ ! -f "$SCRIPT_DIR/memory/global_context.md" ]; then
    log_info "Creating memory/global_context.md..."
    cat > "$SCRIPT_DIR/memory/global_context.md" << 'EOF'
# Global Context
Last updated: (not set)

## System Policies
- (Record Lord's preferences and policies here)

## Cross-Project Decisions
- (Record decisions affecting multiple projects here)

## Notes
- (Record important notes for all agents here)
EOF
    log_success "global_context.md created"
else
    log_info "memory/global_context.md already exists"
fi

RESULTS+=("Configuration files: OK")

# ============================================================
# STEP 8: Ashigaru Task & Report File Initialization
# ============================================================
log_step "STEP 8: Queue File Initialization"

# Dynamically get ashigaru count from settings.yaml (default: 7 if not configured)
_SETUP_VENV_PYTHON="$SCRIPT_DIR/.venv/bin/python3"
_SETUP_ASHIGARU_COUNT=$(
    if [[ -x "$_SETUP_VENV_PYTHON" ]]; then
        "$_SETUP_VENV_PYTHON" -c "
import yaml
try:
    with open('$SCRIPT_DIR/config/settings.yaml') as f:
        cfg = yaml.safe_load(f) or {}
    agents = cfg.get('cli', {}).get('agents', {})
    count = len([k for k in agents if k.startswith('ashigaru')])
    print(count if count > 0 else 7)
except Exception:
    print(7)
" 2>/dev/null
    else
        echo 7
    fi
)
_SETUP_ASHIGARU_COUNT=${_SETUP_ASHIGARU_COUNT:-7}

# Create ashigaru task files
for i in $(seq 1 "$_SETUP_ASHIGARU_COUNT"); do
    TASK_FILE="$SCRIPT_DIR/queue/tasks/ashigaru${i}.yaml"
    if [ ! -f "$TASK_FILE" ]; then
        cat > "$TASK_FILE" << EOF
# Ashigaru ${i} task file
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
    fi
done
log_info "Ashigaru task files (1-${_SETUP_ASHIGARU_COUNT}) checked/created"

# Create ashigaru report files
for i in $(seq 1 "$_SETUP_ASHIGARU_COUNT"); do
    REPORT_FILE="$SCRIPT_DIR/queue/reports/ashigaru${i}_report.yaml"
    if [ ! -f "$REPORT_FILE" ]; then
        cat > "$REPORT_FILE" << EOF
worker_id: ashigaru${i}
task_id: null
timestamp: ""
status: idle
result: null
EOF
    fi
done
log_info "Ashigaru report files (1-${_SETUP_ASHIGARU_COUNT}) checked/created"

RESULTS+=("Queue files: OK")

# ============================================================
# STEP 9: Script Execute Permission Setup
# ============================================================
log_step "STEP 9: Execute Permission Setup"

SCRIPTS=(
    "setup.sh"
    "shutsujin_departure.sh"
    "first_setup.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        chmod +x "$SCRIPT_DIR/$script"
        log_info "Set execute permission on $script"
    fi
done

RESULTS+=("Execute permissions: OK")

# ============================================================
# STEP 10: bashrc Alias Setup
# ============================================================
log_step "STEP 10: Alias Setup"

# Target file for alias additions
BASHRC_FILE="$HOME/.bashrc"

# Define css/csm as functions (auto-cleanup via destroy-unattached)
# - Screen sizes don't interfere when connecting from multiple terminals
# - Temporary sessions auto-destroy on SSH disconnect / app exit
# - Main sessions (shogun/multiagent) are never destroyed
CSS_FUNC='css() { local s="shogun-$$"; local cols=$(tput cols 2>/dev/null || echo 80); tmux new-session -d -t shogun -s "$s" 2>/dev/null && tmux set-option -t "$s" destroy-unattached on 2>/dev/null; if [ "$cols" -lt 80 ]; then tmux new-window -t "$s" -n mobile 2>/dev/null; tmux attach-session -t "$s:mobile" 2>/dev/null || tmux attach-session -t shogun; else tmux attach-session -t "$s" 2>/dev/null || tmux attach-session -t shogun; fi; }'
CSM_FUNC='csm() { local s="multi-$$"; local cols=$(tput cols 2>/dev/null || echo 80); tmux new-session -d -t multiagent -s "$s" 2>/dev/null && tmux set-option -t "$s" destroy-unattached on 2>/dev/null; if [ "$cols" -lt 80 ]; then tmux new-window -t "$s" -n mobile 2>/dev/null; tmux attach-session -t "$s:mobile" 2>/dev/null || tmux attach-session -t multiagent; else tmux attach-session -t "$s" 2>/dev/null || tmux attach-session -t multiagent; fi; }'

ALIAS_ADDED=false

if [ -f "$BASHRC_FILE" ]; then
    # Remove old alias format (if present)
    if grep -q "alias css=" "$BASHRC_FILE" 2>/dev/null; then
        sed -i '/alias css=/d' "$BASHRC_FILE"
        log_info "Removed old alias css"
    fi
    if grep -q "alias csm=" "$BASHRC_FILE" 2>/dev/null; then
        sed -i '/alias csm=/d' "$BASHRC_FILE"
        log_info "Removed old alias csm"
    fi

    # css function
    if ! grep -q "^css()" "$BASHRC_FILE" 2>/dev/null; then
        if ! grep -q "multi-agent-shogun aliases" "$BASHRC_FILE" 2>/dev/null; then
            echo "" >> "$BASHRC_FILE"
            echo "# multi-agent-shogun aliases (added by first_setup.sh)" >> "$BASHRC_FILE"
        fi
        echo "$CSS_FUNC" >> "$BASHRC_FILE"
        log_info "Added css function (shogun window -- auto-cleanup)"
        ALIAS_ADDED=true
    else
        # Function exists -> update to latest version
        sed -i '/^css()/d' "$BASHRC_FILE"
        echo "$CSS_FUNC" >> "$BASHRC_FILE"
        log_info "Updated css function"
        ALIAS_ADDED=true
    fi

    # csm function
    if ! grep -q "^csm()" "$BASHRC_FILE" 2>/dev/null; then
        echo "$CSM_FUNC" >> "$BASHRC_FILE"
        log_info "Added csm function (karo/ashigaru window -- auto-cleanup)"
        ALIAS_ADDED=true
    else
        sed -i '/^csm()/d' "$BASHRC_FILE"
        echo "$CSM_FUNC" >> "$BASHRC_FILE"
        log_info "Updated csm function"
        ALIAS_ADDED=true
    fi
else
    log_warn "$BASHRC_FILE not found"
fi

if [ "$ALIAS_ADDED" = true ]; then
    log_success "Alias setup complete (destroy-unattached mode)"
    log_warn "To apply aliases, do one of the following:"
    log_info "  1. source ~/.bashrc"
    log_info "  2. Run 'wsl --shutdown' in PowerShell, then reopen the terminal"
    log_info "  Note: Simply closing the window does not terminate WSL, so changes won't apply"
fi

RESULTS+=("Alias setup: OK")

# ============================================================
# STEP 10.5: WSL Memory Optimization Settings
# ============================================================
if [ "$IS_WSL" = true ]; then
    log_step "STEP 10.5: WSL Memory Optimization Settings"

    # Check/configure .wslconfig (placed in Windows user directory)
    WIN_USER_DIR=$(cmd.exe /C "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')
    if [ -n "$WIN_USER_DIR" ]; then
        # Convert Windows path to WSL path
        WSLCONFIG_PATH=$(wslpath "$WIN_USER_DIR")/.wslconfig

        if [ -f "$WSLCONFIG_PATH" ]; then
            if grep -q "autoMemoryReclaim" "$WSLCONFIG_PATH" 2>/dev/null; then
                log_info "autoMemoryReclaim already configured in .wslconfig"
            else
                log_info "Adding autoMemoryReclaim=gradual to .wslconfig..."
                # Check if [experimental] section exists
                if grep -q "\[experimental\]" "$WSLCONFIG_PATH" 2>/dev/null; then
                    # Add right after [experimental] section
                    sed -i '/\[experimental\]/a autoMemoryReclaim=gradual' "$WSLCONFIG_PATH"
                else
                    echo "" >> "$WSLCONFIG_PATH"
                    echo "[experimental]" >> "$WSLCONFIG_PATH"
                    echo "autoMemoryReclaim=gradual" >> "$WSLCONFIG_PATH"
                fi
                log_success "Added autoMemoryReclaim=gradual to .wslconfig"
                log_warn "Requires 'wsl --shutdown' and restart to take effect"
            fi
        else
            log_info "Creating new .wslconfig..."
            cat > "$WSLCONFIG_PATH" << 'EOF'
[experimental]
autoMemoryReclaim=gradual
EOF
            log_success ".wslconfig created (autoMemoryReclaim=gradual)"
            log_warn "Requires 'wsl --shutdown' and restart to take effect"
        fi

        RESULTS+=("WSL memory optimization: OK (.wslconfig configured)")
    else
        log_warn "Failed to retrieve Windows user directory"
        log_info "Manually add the following to %USERPROFILE%\\.wslconfig:"
        echo "  [experimental]"
        echo "  autoMemoryReclaim=gradual"
        RESULTS+=("WSL memory optimization: Manual setup required")
    fi

    # Guidance for immediate cache clearing
    log_info "To clear memory cache immediately, run:"
    echo "  sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'"
else
    log_info "Not a WSL environment, skipping memory optimization settings"
fi

# ============================================================
# STEP 11: Memory MCP Setup
# ============================================================
log_step "STEP 11: Memory MCP Setup"

if command -v claude &> /dev/null; then
    # Check if Memory MCP is already configured
    if claude mcp list 2>/dev/null | grep -q "memory"; then
        log_info "Memory MCP is already configured"
        RESULTS+=("Memory MCP: OK (configured)")
    else
        log_info "Configuring Memory MCP..."
        if claude mcp add memory \
            -e MEMORY_FILE_PATH="$SCRIPT_DIR/memory/shogun_memory.jsonl" \
            -- npx -y @modelcontextprotocol/server-memory 2>/dev/null; then
            log_success "Memory MCP configuration complete"
            RESULTS+=("Memory MCP: Configured")
        else
            log_warn "Failed to configure Memory MCP (can be set up manually)"
            RESULTS+=("Memory MCP: Configuration failed (manual setup available)")
        fi
    fi
else
    log_warn "claude command not found, skipping Memory MCP setup"
    RESULTS+=("Memory MCP: Skipped (claude not installed)")
fi

# ============================================================
# STEP 12: Create Shogunate State Directory (~/.shogunate/)
# ============================================================
log_step "STEP 12: Shogunate State Directory"

if [ -f "$SCRIPT_DIR/scripts/install_state_dir.sh" ]; then
    if bash "$SCRIPT_DIR/scripts/install_state_dir.sh" --from "$SCRIPT_DIR"; then
        RESULTS+=("Shogunate state: Created at ~/.shogunate/")
    else
        log_warn "Failed to create state directory (can be run manually: bash scripts/install_state_dir.sh)"
        RESULTS+=("Shogunate state: Failed (run manually)")
    fi
else
    log_warn "install_state_dir.sh not found"
    RESULTS+=("Shogunate state: Skipped (script missing)")
fi

# ============================================================
# STEP 13: Install Shogunate Hooks into User Settings
# ============================================================
log_step "STEP 13: Shogunate User Settings"

if [ -f "$SCRIPT_DIR/scripts/install_user_settings.sh" ]; then
    if bash "$SCRIPT_DIR/scripts/install_user_settings.sh"; then
        RESULTS+=("Shogunate hooks: Installed in ~/.claude/settings.json")
    else
        log_warn "Failed to install Shogunate hooks (can be run manually: bash scripts/install_user_settings.sh)"
        RESULTS+=("Shogunate hooks: Failed (run manually)")
    fi
else
    log_warn "install_user_settings.sh not found"
    RESULTS+=("Shogunate hooks: Skipped (script missing)")
fi

# ============================================================
# STEP 14: Pre-trust Shogunate directories for Claude Code
# ============================================================
log_step "STEP 14: Pre-trust Directories"

# Layer 1: Write directly to Claude Code's trust store (mkdir)
_pretrust_store() {
    local dir="$1"
    local label="$2"
    local trust_name
    trust_name=$(echo "$dir" | sed 's|/|-|g')
    mkdir -p "$HOME/.claude/projects/${trust_name}" 2>/dev/null && \
        log_success "  Trust store: ${label} (${dir})" || \
        log_warn "  Trust store: ${label} failed"
}

_pretrust_store "$SCRIPT_DIR" "Plugin cache"
if [ -d "$HOME/.shogunate" ]; then
    _pretrust_store "$HOME/.shogunate" "State dir"
fi
RESULTS+=("Pre-trust: Trust store entries created")

# Layer 2: claude -p + doctor (belt and suspenders)
if command -v claude &>/dev/null; then
    log_info "Pre-trusting via claude -p..."
    (cd "$SCRIPT_DIR" && claude -p "echo trusted" --dangerously-skip-permissions --setting-sources user 2>/dev/null) && \
        RESULTS+=("Pre-trust: claude -p OK") || \
        RESULTS+=("Pre-trust: claude -p skipped (trust store used instead)")

    log_info "Running claude doctor for health check..."
    (cd "$SCRIPT_DIR" && claude doctor 2>/dev/null) && \
        RESULTS+=("Claude doctor: OK") || \
        RESULTS+=("Claude doctor: Warning (non-critical)")
else
    RESULTS+=("Pre-trust: claude not installed (trust store entries created, should be sufficient)")
fi

# ============================================================
# Result Summary
# ============================================================
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║  📋 Setup Result Summary                                     ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""

for result in "${RESULTS[@]}"; do
    if [[ $result == *"Not installed"* ]] || [[ $result == *"failed"* ]] || [[ $result == *"Failed"* ]]; then
        echo -e "  ${RED}✗${NC} $result"
    elif [[ $result == *"upgrade"* ]] || [[ $result == *"Skipped"* ]] || [[ $result == *"recommended"* ]]; then
        echo -e "  ${YELLOW}!${NC} $result"
    else
        echo -e "  ${GREEN}✓${NC} $result"
    fi
done

echo ""

if [ "$HAS_ERROR" = true ]; then
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║  ⚠️  Some dependencies are missing                           ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Review the warnings above and install the missing dependencies."
    echo "  Once all dependencies are in place, re-run this script to verify."
else
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║  ✅ Setup complete! All preparations are in order!           ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
fi

echo ""
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │  📜 Next Steps                                               │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo ""
echo "  ⚠️  First time only: Please run the following manually"
echo ""
echo "  STEP 0: Apply PATH (reflect installation results in this shell)"
echo "     source ~/.bashrc"
echo ""
echo "  STEP A: OAuth authentication + Bypass Permissions approval (single command)"
echo "     claude --dangerously-skip-permissions"
echo ""
echo "     1. Browser opens -> Log in with Anthropic account -> Return to CLI"
echo "        Note: If the browser doesn't open in WSL, manually paste the"
echo "              displayed URL into a browser on the Windows side"
echo "     2. Bypass Permissions approval screen appears"
echo "        -> Select 'Yes, I accept' (press down arrow to option 2, then Enter)"
echo "     3. Type /exit to quit"
echo ""
echo "     Note: Once approved, it is saved in ~/.claude/ and not needed again"
echo ""
echo "  ────────────────────────────────────────────────────────────────"
echo ""
echo "  Deploy (launch all agents):"
echo "     ./shutsujin_departure.sh"
echo ""
echo "  Options:"
echo "     ./shutsujin_departure.sh -s            # Setup only (launch Claude manually)"
echo "     ./shutsujin_departure.sh -t            # Open Windows Terminal tabs"
echo "     ./shutsujin_departure.sh -shell bash   # Launch with bash prompt"
echo "     ./shutsujin_departure.sh -shell zsh    # Launch with zsh prompt"
echo ""
echo "  Note: Shell setting can also be changed via shell: in config/settings.yaml"
echo ""
echo "  See README.md for details."
echo ""
echo "  ════════════════════════════════════════════════════════════════"
echo "   Conquer all under heaven! (Tenka Fubu!)"
echo "  ════════════════════════════════════════════════════════════════"
echo ""

# Return exit 1 if dependencies are missing (so install.bat can detect it)
if [ "$HAS_ERROR" = true ]; then
    exit 1
fi