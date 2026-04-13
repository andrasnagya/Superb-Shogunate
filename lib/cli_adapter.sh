#!/usr/bin/env bash
# cli_adapter.sh — CLI abstraction layer
# Conforms to Multi-CLI integration design doc (reports/design_multi_cli_support.md) §2.2
#
# Provided functions:
#   get_cli_type(agent_id)                  → "claude" | "codex" | "copilot" | "kimi"
#   build_cli_command(agent_id)             → full command string
#   get_instruction_file(agent_id [,cli_type]) → instruction file path
#   validate_cli_availability(cli_type)     → 0=OK, 1=NG
#   get_agent_model(agent_id)               → "opus" | "sonnet" | "haiku" | "k2.5"
#   get_startup_prompt(agent_id)            → startup prompt string or ""

# Resolve settings.yaml path relative to project root
CLI_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ADAPTER_PROJECT_ROOT="$(cd "${CLI_ADAPTER_DIR}/.." && pwd)"
CLI_ADAPTER_SETTINGS="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

# Allowed CLI types
CLI_ADAPTER_ALLOWED_CLIS="claude codex copilot kimi"

# --- Internal helpers ---

# _cli_adapter_read_yaml key [fallback]
# Read a value from settings.yaml using python3
_cli_adapter_read_yaml() {
    local key_path="$1"
    local fallback="${2:-}"
    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    keys = '${key_path}'.split('.')
    val = cfg
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k)
        else:
            val = None
            break
    if val is not None:
        print(val)
    else:
        print('${fallback}')
except Exception:
    print('${fallback}')
" 2>/dev/null)
    if [[ -z "$result" ]]; then
        echo "$fallback"
    else
        echo "$result"
    fi
}

# _cli_adapter_is_valid_cli cli_type
# Check if the given CLI type is allowed
_cli_adapter_is_valid_cli() {
    local cli_type="$1"
    local allowed
    for allowed in $CLI_ADAPTER_ALLOWED_CLIS; do
        [[ "$cli_type" == "$allowed" ]] && return 0
    done
    return 1
}

# --- Public API ---

# get_cli_type(agent_id)
# Returns the CLI type the specified agent should use
# Fallback: cli.agents.{id}.type → cli.agents.{id}(string) → cli.default → "claude"
get_cli_type() {
    local agent_id="$1"
    if [[ -z "$agent_id" ]]; then
        echo "claude"
        return 0
    fi

    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    cli = cfg.get('cli', {})
    if not isinstance(cli, dict):
        print('claude'); sys.exit(0)
    agents = cli.get('agents', {})
    if not isinstance(agents, dict):
        print(cli.get('default', 'claude') if cli.get('default', 'claude') in ('claude','codex','copilot','kimi') else 'claude')
        sys.exit(0)
    agent_cfg = agents.get('${agent_id}')
    if isinstance(agent_cfg, dict):
        t = agent_cfg.get('type', '')
        if t in ('claude', 'codex', 'copilot', 'kimi'):
            print(t); sys.exit(0)
    elif isinstance(agent_cfg, str):
        if agent_cfg in ('claude', 'codex', 'copilot', 'kimi'):
            print(agent_cfg); sys.exit(0)
    default = cli.get('default', 'claude')
    if default in ('claude', 'codex', 'copilot', 'kimi'):
        print(default)
    else:
        print('claude', file=sys.stderr)
        print('claude')
except Exception as e:
    print('claude', file=sys.stderr)
    print('claude')
" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo "claude"
    else
        if ! _cli_adapter_is_valid_cli "$result"; then
            echo "[WARN] Invalid CLI type '$result' for agent '$agent_id'. Falling back to 'claude'." >&2
            echo "claude"
        else
            echo "$result"
        fi
    fi
}

# build_cli_command(agent_id)
# Returns the full command string needed to launch the agent
# settings.yaml thinking: false → prepend MAX_THINKING_TOKENS=0
build_cli_command() {
    local agent_id="$1"
    local cli_type
    cli_type=$(get_cli_type "$agent_id")
    local model
    model=$(get_agent_model "$agent_id")
    local thinking
    thinking=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.thinking" "")

    # thinking prefix: only effective for Claude CLI
    # thinking: true or unset → as-is (Thinking ON by default)
    # thinking: false → prepend MAX_THINKING_TOKENS=0
    local prefix=""
    if [[ "$cli_type" == "claude" && "$thinking" == "false" || "$thinking" == "False" ]]; then
        prefix="MAX_THINKING_TOKENS=0 "
    fi

    case "$cli_type" in
        claude)
            local cmd="claude"
            if [[ -n "$model" ]]; then
                cmd="$cmd --model $model"
            fi
            cmd="$cmd --dangerously-skip-permissions"
            echo "${prefix}${cmd}"
            ;;
        codex)
            local cmd="codex"
            if [[ -n "$model" ]]; then
                cmd="$cmd --model $model"
            fi
            cmd="$cmd --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen"
            echo "$cmd"
            ;;
        copilot)
            echo "copilot --yolo"
            ;;
        kimi)
            local cmd="kimi --yolo"
            if [[ -n "$model" ]]; then
                cmd="$cmd --model $model"
            fi
            echo "$cmd"
            ;;
        *)
            echo "claude --dangerously-skip-permissions"
            ;;
    esac
}

# get_instruction_file(agent_id [,cli_type])
# Returns the path to the instruction file the CLI should auto-load
get_instruction_file() {
    local agent_id="$1"
    local cli_type="${2:-$(get_cli_type "$agent_id")}"
    local role

    case "$agent_id" in
        shogun)    role="shogun" ;;
        karo)      role="karo" ;;
        gunshi)    role="gunshi" ;;
        ashigaru*) role="ashigaru" ;;
        *)
            echo "" >&2
            return 1
            ;;
    esac

    case "$cli_type" in
        claude)  echo "instructions/${role}.md" ;;
        codex)   echo "instructions/codex-${role}.md" ;;
        copilot) echo ".github/copilot-instructions-${role}.md" ;;
        kimi)    echo "instructions/generated/kimi-${role}.md" ;;
        *)       echo "instructions/${role}.md" ;;
    esac
}

# validate_cli_availability(cli_type)
# Checks whether the specified CLI is installed on the system
# 0=available, 1=unavailable
validate_cli_availability() {
    local cli_type="$1"
    case "$cli_type" in
        claude)
            command -v claude &>/dev/null || {
                echo "[ERROR] Claude Code CLI not found. Install from https://claude.ai/download" >&2
                return 1
            }
            ;;
        codex)
            command -v codex &>/dev/null || {
                echo "[ERROR] OpenAI Codex CLI not found. Install with: npm install -g @openai/codex" >&2
                return 1
            }
            ;;
        copilot)
            command -v copilot &>/dev/null || {
                echo "[ERROR] GitHub Copilot CLI not found. Install with: brew install copilot-cli" >&2
                return 1
            }
            ;;
        kimi)
            if ! command -v kimi-cli &>/dev/null && ! command -v kimi &>/dev/null; then
                echo "[ERROR] Kimi CLI not found. Install from https://platform.moonshot.cn/" >&2
                return 1
            fi
            ;;
        *)
            echo "[ERROR] Unknown CLI type: '$cli_type'. Allowed: $CLI_ADAPTER_ALLOWED_CLIS" >&2
            return 1
            ;;
    esac
    return 0
}

# get_agent_model(agent_id)
# Returns the model name the agent should use
get_agent_model() {
    local agent_id="$1"

    # First check cli.agents.{id}.model in settings.yaml
    local model_from_yaml
    model_from_yaml=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.model" "")

    if [[ -n "$model_from_yaml" ]]; then
        echo "$model_from_yaml"
        return 0
    fi

    # Check existing models section
    local model_from_models
    model_from_models=$(_cli_adapter_read_yaml "models.${agent_id}" "")

    if [[ -n "$model_from_models" ]]; then
        echo "$model_from_models"
        return 0
    fi

    # Default logic (initial values based on CLI type)
    local cli_type
    cli_type=$(get_cli_type "$agent_id")

    case "$cli_type" in
        kimi)
            # Default model for Kimi CLI
            case "$agent_id" in
                shogun|karo)    echo "k2.5" ;;
                ashigaru*)      echo "k2.5" ;;
                *)              echo "k2.5" ;;
            esac
            ;;
        *)
            # Default model for Claude Code/Codex/Copilot
            case "$agent_id" in
                shogun)         echo "opus" ;;
                karo)           echo "opus" ;;
                gunshi)         echo "opus" ;;
                ashigaru*)      echo "sonnet" ;;
                *)              echo "sonnet" ;;
            esac
            ;;
    esac
}

# get_model_display_name(agent_id)
# Returns a short display name for pane-border-format
# Format: "{ShortName}" or "{ShortName}+T" (thinking enabled)
# Examples: Sonnet, Opus+T, Haiku, Codex, Spark
get_model_display_name() {
    local agent_id="$1"
    local model
    model=$(get_agent_model "$agent_id")
    local cli_type
    cli_type=$(get_cli_type "$agent_id")
    local thinking
    thinking=$(_cli_adapter_read_yaml "cli.agents.${agent_id}.thinking" "")

    # Model name → short display name
    local short=""
    case "$model" in
        *spark*)                short="Spark" ;;
        gpt-5.3-codex)          short="Codex5.3" ;;
        *codex*|gpt-5.3)        short="Codex" ;;
        *opus*)                 short="Opus" ;;
        *sonnet*)               short="Sonnet" ;;
        *haiku*)                short="Haiku" ;;
        *k2.5*|*kimi*)          short="Kimi" ;;
        *)
            # Infer from CLI type
            case "$cli_type" in
                codex)   short="Codex" ;;
                copilot) short="Copilot" ;;
                kimi)    short="Kimi" ;;
                *)       short="$model" ;;
            esac
            ;;
    esac

    # Thinking display: Claude defaults to ON, so hide only when false
    # Claude: thinking: false → omit, otherwise (true/unset) → "+T"
    # Codex etc.: no Thinking → always omit
    if [[ "$cli_type" == "claude" ]]; then
        if [[ "$thinking" == "false" || "$thinking" == "False" ]]; then
            echo "$short"
        else
            echo "${short}+T"
        fi
    else
        echo "$short"
    fi
}

# get_startup_prompt(agent_id)
# Returns the startup prompt the CLI should execute on first launch
# Codex CLI: passed as [PROMPT] argument (root fix for suggestion UI stall)
# Claude Code: empty (Session Start procedure triggered by CLAUDE.md auto-load)
# Copilot/Kimi: empty (future support)
get_startup_prompt() {
    local agent_id="$1"
    local cli_type
    cli_type=$(get_cli_type "$agent_id")

    case "$cli_type" in
        codex)
            echo "Session Start — do ALL of this in one turn, do NOT stop early: 1) tmux display-message -t \"\$TMUX_PANE\" -p '#{@agent_id}' to identify yourself. 2) Read queue/tasks/${agent_id}.yaml. 3) Read queue/inbox/${agent_id}.yaml, mark read:true. 4) Read files listed in context_files. 5) Execute the assigned task to completion — edit files, run commands, write reports. Keep working until the task is done."
            ;;
        claude)
            echo "If text like 'inbox3' appears at your prompt, it is a wake-up signal. Read \${SHOGUNATE_STATE}/queue/inbox/${agent_id}.yaml immediately and process unread messages."
            ;;
        *)
            echo ""
            ;;
    esac
}

# =============================================================================
# Dynamic Model Routing — Issue #53 Phase 1
# capability_tier reading, recommended model selection, cost group retrieval
# =============================================================================

# get_capability_tier(model_name)
# Returns the maximum Bloom level for the specified model
# capability_tiers section undefined or model undefined → 6 (no limit)
# Note: model names may contain dots, so _cli_adapter_read_yaml is not used
get_capability_tier() {
    local model_name="$1"

    if [[ -z "$model_name" ]]; then
        echo "6"
        return 0
    fi

    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    tiers = cfg.get('capability_tiers')
    if not tiers or not isinstance(tiers, dict):
        print('6'); sys.exit(0)
    spec = tiers.get('${model_name}')
    if not spec or not isinstance(spec, dict):
        print('6'); sys.exit(0)
    mb = spec.get('max_bloom', 6)
    if isinstance(mb, int) and 1 <= mb <= 6:
        print(mb)
    else:
        print('6')
except Exception:
    print('6')
" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo "6"
    else
        echo "$result"
    fi
}

# get_cost_group(model_name)
# Returns the cost group for the specified model
# Undefined → "unknown"
# Note: model names may contain dots, so _cli_adapter_read_yaml is not used
get_cost_group() {
    local model_name="$1"

    if [[ -z "$model_name" ]]; then
        echo "unknown"
        return 0
    fi

    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    tiers = cfg.get('capability_tiers')
    if not tiers or not isinstance(tiers, dict):
        print('unknown'); sys.exit(0)
    spec = tiers.get('${model_name}')
    if not spec or not isinstance(spec, dict):
        print('unknown'); sys.exit(0)
    cg = spec.get('cost_group', 'unknown')
    print(cg if cg else 'unknown')
except Exception:
    print('unknown')
" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo "unknown"
    else
        echo "$result"
    fi
}

# get_available_cost_groups()
# Returns the user's subscription pattern
# 1) available_cost_groups defined in settings.yaml → return as-is
# 2) Undefined → auto-infer from capability_tiers (aggregate cost_groups of defined models)
# 3) capability_tiers absent → empty string
# Output: space-separated cost_group list (e.g., "claude_max chatgpt_pro")
get_available_cost_groups() {
    local settings="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys
try:
    with open('${settings}') as f:
        cfg = yaml.safe_load(f) or {}

    # 1) Use explicit definition if available
    explicit = cfg.get('available_cost_groups')
    if explicit and isinstance(explicit, list):
        print(' '.join(str(g) for g in explicit))
        sys.exit(0)

    # 2) Auto-infer from capability_tiers
    tiers = cfg.get('capability_tiers')
    if not tiers or not isinstance(tiers, dict):
        print('')
        sys.exit(0)

    groups = set()
    for model, spec in tiers.items():
        if isinstance(spec, dict):
            cg = spec.get('cost_group')
            if cg:
                groups.add(cg)
    print(' '.join(sorted(groups)))
except Exception:
    print('')
" 2>/dev/null)

    echo "$result"
}

# get_recommended_model(bloom_level)
# Returns the most cost-efficient model for the specified Bloom level
# Filtered by available_cost_groups. Warns on stderr for insufficient/overqualified models.
# capability_tiers section absent → empty string
# bloom_level out of range (not 1-6) → empty string + exit code 1
get_recommended_model() {
    local bloom_level="$1"

    # Range check
    if [[ ! "$bloom_level" =~ ^[1-6]$ ]]; then
        echo ""
        return 1
    fi

    local settings="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

    # Python: stdout=model name, stderr=warnings (pass through to caller's stderr)
    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys

def parse_bloom_range(key):
    '''parse 'L1-L3' -> [1,2,3], 'L4-L5' -> [4,5], 'L6' -> [6]'''
    key = key.strip()
    if '-' in key[1:]:  # e.g. L1-L3
        parts = key.split('-')
        start = int(parts[0].lstrip('Ll'))
        end = int(parts[1].lstrip('Ll'))
        return list(range(start, end + 1))
    else:  # e.g. L6
        return [int(key.lstrip('Ll'))]

try:
    with open('${settings}') as f:
        cfg = yaml.safe_load(f) or {}
    tiers = cfg.get('capability_tiers')
    if not tiers or not isinstance(tiers, dict):
        sys.exit(0)

    bloom = int('${bloom_level}')
    cost_priority = {'chatgpt_pro': 0, 'claude_max': 1}

    # available_cost_groups: explicit definition or None (allow all)
    explicit_groups = cfg.get('available_cost_groups')
    if explicit_groups and isinstance(explicit_groups, list):
        allowed_groups = set(str(g) for g in explicit_groups)
    else:
        allowed_groups = None

    # bloom_model_preference: if defined → priority-based routing
    preference = cfg.get('bloom_model_preference')
    if preference and isinstance(preference, dict):
        # Find the range key matching the input bloom_level
        matched_list = None
        for range_key, model_list in preference.items():
            try:
                levels = parse_bloom_range(range_key)
                if bloom in levels:
                    matched_list = model_list
                    break
            except (ValueError, IndexError):
                continue

        if matched_list and isinstance(matched_list, list):
            # Iterate models in list order
            for pref_model in matched_list:
                spec = tiers.get(pref_model)
                if not isinstance(spec, dict):
                    continue
                mb = spec.get('max_bloom', 6)
                cg = spec.get('cost_group', 'unknown')
                # (a) available_cost_groups exclusion check
                if allowed_groups is not None and cg not in allowed_groups:
                    continue
                # (b) capability_tiers max_bloom >= bloom_level
                if isinstance(mb, int) and mb >= bloom:
                    print(pref_model)
                    sys.exit(0)
            # All exhausted → fallback + warning
            print('WARNING: All preferred models unavailable for bloom level ' + str(bloom) + ', falling back to cost_priority', file=sys.stderr)
            # fallthrough to legacy cost_priority logic

    # Legacy cost_priority auto-selection (backward compatible)
    candidates = []
    all_models = []
    for model, spec in tiers.items():
        if not isinstance(spec, dict):
            continue
        mb = spec.get('max_bloom', 6)
        cg = spec.get('cost_group', 'unknown')
        if allowed_groups is not None and cg not in allowed_groups:
            continue
        all_models.append((mb, cg, model))
        if isinstance(mb, int) and mb >= bloom:
            candidates.append((cost_priority.get(cg, 99), mb, model))

    if not all_models:
        sys.exit(0)

    if not candidates:
        best = max(all_models, key=lambda x: x[0])
        print(best[2])
        print(f'[WARN] insufficient: {best[2]} (max_bloom={best[0]}) cannot handle bloom level {bloom}', file=sys.stderr)
    else:
        candidates.sort(key=lambda x: (x[1], x[0]))
        chosen_mb = candidates[0][1]
        chosen_model = candidates[0][2]
        print(chosen_model)
        if chosen_mb - bloom >= 2:
            print(f'[WARN] overqualified: {chosen_model} (max_bloom={chosen_mb}) for bloom level {bloom}. Consider adding a lower-tier model.', file=sys.stderr)
except Exception:
    pass
")

    echo "$result"
}

# =============================================================================
# Dynamic Model Routing — Issue #53 Phase 2
# model_switch decision, recommended action, CLI compatibility check
# =============================================================================

# needs_model_switch(current_model, bloom_level)
# Determines whether the current model can handle the specified Bloom level
# Output: "yes" (switch needed) | "no" (not needed) | "skip" (cannot determine)
needs_model_switch() {
    local current_model="$1"
    local bloom_level="$2"

    # bloom_level not specified → skip determination
    if [[ -z "$bloom_level" || ! "$bloom_level" =~ ^[1-6]$ ]]; then
        echo "skip"
        return 0
    fi

    # Check existence of capability_tiers
    local max_bloom
    max_bloom=$(get_capability_tier "$current_model")

    # Check if capability_tiers section is absent (when all models return 6)
    local has_tiers
    has_tiers=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys
try:
    with open('${CLI_ADAPTER_SETTINGS}') as f:
        cfg = yaml.safe_load(f) or {}
    tiers = cfg.get('capability_tiers')
    print('yes' if tiers and isinstance(tiers, dict) else 'no')
except:
    print('no')
" 2>/dev/null)

    if [[ "$has_tiers" != "yes" ]]; then
        echo "skip"
        return 0
    fi

    if [[ "$bloom_level" -gt "$max_bloom" ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# get_switch_recommendation(current_model, bloom_level)
# Returns switch decision + recommended model + cost group transition
# Output: "no_switch" | "{recommended_model}:{transition_type}"
#   transition_type: "same_cost_group" | "cross_cost_group"
get_switch_recommendation() {
    local current_model="$1"
    local bloom_level="$2"

    local switch_needed
    switch_needed=$(needs_model_switch "$current_model" "$bloom_level")

    if [[ "$switch_needed" != "yes" ]]; then
        echo "no_switch"
        return 0
    fi

    local recommended
    recommended=$(get_recommended_model "$bloom_level")

    if [[ -z "$recommended" ]]; then
        echo "no_switch"
        return 0
    fi

    local current_cg recommended_cg transition
    current_cg=$(get_cost_group "$current_model")
    recommended_cg=$(get_cost_group "$recommended")

    if [[ "$current_cg" = "$recommended_cg" ]]; then
        transition="same_cost_group"
    else
        transition="cross_cost_group"
    fi

    echo "${recommended}:${transition}"
}

# can_model_switch(cli_type)
# Determines whether model_switch is possible for the specified CLI type
# Output: "full" (Claude: /model command supported) | "limited" (Codex: same CLI only) | "none"
can_model_switch() {
    local cli_type="$1"

    case "$cli_type" in
        claude)  echo "full" ;;
        codex)   echo "limited" ;;
        copilot) echo "none" ;;
        kimi)    echo "none" ;;
        *)       echo "none" ;;
    esac
}

# =============================================================================
# Dynamic Model Routing — Issue #53 Phase 3
# gunshi_analysis.yaml validation, Bloom analysis trigger determination
# =============================================================================

# get_bloom_routing()
# Reads and validates bloom_routing setting from settings.yaml
# Output: "auto" | "manual" | "off"
# Invalid value → "off" + stderr warning
get_bloom_routing() {
    local settings="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

    local raw
    raw=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys
try:
    with open('${settings}') as f:
        cfg = yaml.safe_load(f) or {}
    val = cfg.get('bloom_routing')
    if val is None:
        print('off')
    elif val is False:
        print('off')
    else:
        print(str(val))
except Exception:
    print('off')
" 2>/dev/null)

    case "$raw" in
        auto|manual|off)
            echo "$raw"
            ;;
        *)
            echo "off"
            echo "[WARN] bloom_routing: invalid value '${raw}', falling back to 'off'" >&2
            ;;
    esac
}

# validate_gunshi_analysis(yaml_path)
# Schema validation for gunshi_analysis.yaml
# Output: "valid" (normal) | error message (abnormal)
# Exit code: 0 (normal) | 1 (abnormal)
validate_gunshi_analysis() {
    local yaml_path="$1"

    if [[ ! -f "$yaml_path" ]]; then
        echo "error: file not found: ${yaml_path}"
        return 1
    fi

    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys

try:
    with open('${yaml_path}') as f:
        doc = yaml.safe_load(f)
except Exception as e:
    print(f'error: YAML parse failed: {e}')
    sys.exit(1)

if not isinstance(doc, dict):
    print('error: root must be a mapping')
    sys.exit(1)

# Required fields
if 'task_id' not in doc:
    print('error: missing required field: task_id')
    sys.exit(1)
if 'timestamp' not in doc:
    print('error: missing required field: timestamp')
    sys.exit(1)

analysis = doc.get('analysis')
if not isinstance(analysis, dict):
    print('error: missing or invalid analysis section')
    sys.exit(1)

# bloom_level: integer 1-6
bl = analysis.get('bloom_level')
if bl is None:
    print('error: missing analysis.bloom_level')
    sys.exit(1)
if not isinstance(bl, int) or bl < 1 or bl > 6:
    print(f'error: bloom_level must be integer 1-6, got {bl}')
    sys.exit(1)

# confidence: float 0.0-1.0
conf = analysis.get('confidence')
if conf is not None:
    if not isinstance(conf, (int, float)) or conf < 0.0 or conf > 1.0:
        print(f'error: confidence must be 0.0-1.0, got {conf}')
        sys.exit(1)

# #48 fields are optional — no validation needed
print('valid')
" 2>&1)

    if [[ "$result" == "valid" ]]; then
        echo "valid"
        return 0
    else
        echo "$result"
        return 1
    fi
}

# should_trigger_bloom_analysis(bloom_routing, bloom_analysis_required, gunshi_available)
# Determines whether Bloom analysis should be triggered
# $1: bloom_routing — "auto" | "manual" | "off"
# $2: bloom_analysis_required — "true" | "false" (flag in task YAML)
# $3: gunshi_available — "yes" | "no" (defaults to "yes")
# Output: "yes" | "no" | "fallback"
should_trigger_bloom_analysis() {
    local bloom_routing="${1:-off}"
    local bloom_analysis_required="${2:-false}"
    local gunshi_available="${3:-yes}"

    # Gunshi not running → Phase 2 fallback
    if [[ "$gunshi_available" = "no" ]]; then
        echo "fallback"
        return 0
    fi

    case "$bloom_routing" in
        auto)
            echo "yes"
            ;;
        manual)
            if [[ "$bloom_analysis_required" = "true" ]]; then
                echo "yes"
            else
                echo "no"
            fi
            ;;
        off|*)
            echo "no"
            ;;
    esac
}

# =============================================================================
# Dynamic Model Routing — Issue #53 Phase 4
# Quality feedback accumulation and aggregation
# =============================================================================

# append_model_performance(yaml_path, task_id, task_type, bloom_level, model_used, qc_result, qc_score)
# Appends a QC result entry to model_performance.yaml
# Output: none. Exit code 0=success, 1=failure
append_model_performance() {
    local yaml_path="$1"
    local task_id="$2"
    local task_type="$3"
    local bloom_level="$4"
    local model_used="$5"
    local qc_result="$6"
    local qc_score="$7"

    "$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys, os
from datetime import datetime, timezone

yaml_path = '${yaml_path}'
entry = {
    'task_id': '${task_id}',
    'task_type': '${task_type}',
    'bloom_level': int('${bloom_level}'),
    'model_used': '${model_used}',
    'qc_result': '${qc_result}',
    'qc_score': float('${qc_score}'),
    'timestamp': datetime.now(timezone.utc).isoformat()
}

try:
    if os.path.exists(yaml_path):
        with open(yaml_path) as f:
            doc = yaml.safe_load(f) or {}
    else:
        doc = {}

    if 'history' not in doc or not isinstance(doc.get('history'), list):
        doc['history'] = []

    doc['history'].append(entry)

    with open(yaml_path, 'w') as f:
        yaml.dump(doc, f, default_flow_style=False, allow_unicode=True)
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# get_model_performance_summary(yaml_path, task_type, bloom_level)
# Returns aggregated stats per task_type x bloom_level
# Output: "total:N pass:M fail:F pass_rate:R"
get_model_performance_summary() {
    local yaml_path="$1"
    local task_type="$2"
    local bloom_level="$3"

    "$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys, os

yaml_path = '${yaml_path}'
task_type = '${task_type}'
bloom_level = int('${bloom_level}')

try:
    if not os.path.exists(yaml_path):
        print('total:0 pass:0 fail:0 pass_rate:0.00')
        sys.exit(0)

    with open(yaml_path) as f:
        doc = yaml.safe_load(f) or {}

    history = doc.get('history', [])
    filtered = [h for h in history
                if h.get('task_type') == task_type
                and h.get('bloom_level') == bloom_level]

    total = len(filtered)
    if total == 0:
        print('total:0 pass:0 fail:0 pass_rate:0.00')
        sys.exit(0)

    pass_count = sum(1 for h in filtered if h.get('qc_result') == 'pass')
    fail_count = total - pass_count
    pass_rate = round(pass_count / total, 2)

    print(f'total:{total} pass:{pass_count} fail:{fail_count} pass_rate:{pass_rate}')
except Exception as e:
    print('total:0 pass:0 fail:0 pass_rate:0.00')
" 2>/dev/null
}

# =============================================================================
# Subscription Pattern Validation
# User subscription pattern validation
# =============================================================================

# validate_subscription_coverage()
# Verifies that all Bloom levels (1-6) are covered by available models
# Output:
#   "ok" — all levels covered
#   "unconfigured" — capability_tiers not defined
#   "gap:N,M max_available:X" — levels N,M are not covered. Maximum available level is X
validate_subscription_coverage() {
    local settings="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys

try:
    with open('${settings}') as f:
        cfg = yaml.safe_load(f) or {}
    tiers = cfg.get('capability_tiers')
    if not tiers or not isinstance(tiers, dict):
        print('unconfigured')
        sys.exit(0)

    # available_cost_groups filter
    explicit_groups = cfg.get('available_cost_groups')
    if explicit_groups and isinstance(explicit_groups, list):
        allowed_groups = set(str(g) for g in explicit_groups)
    else:
        allowed_groups = None

    # Collect max_bloom values of available models
    max_blooms = []
    for model, spec in tiers.items():
        if not isinstance(spec, dict):
            continue
        cg = spec.get('cost_group', 'unknown')
        if allowed_groups is not None and cg not in allowed_groups:
            continue
        mb = spec.get('max_bloom', 6)
        if isinstance(mb, int):
            max_blooms.append(mb)

    if not max_blooms:
        print('unconfigured')
        sys.exit(0)

    max_available = max(max_blooms)

    # Check if there is a model with max_bloom >= level for each Bloom level (1-6)
    gaps = []
    for level in range(1, 7):
        if not any(mb >= level for mb in max_blooms):
            gaps.append(str(level))

    if gaps:
        print(f'gap:{','.join(gaps)} max_available:{max_available}')
    else:
        print('ok')
except Exception:
    print('unconfigured')
" 2>/dev/null)

    echo "$result"
}

# find_agent_for_model() — Issue #53 Phase 2
# Finds an idle ashigaru running the specified model.
#
# Core design principle (Lord's policy):
#   - Busy panes: NEVER touch (risk of work interruption and data loss)
#   - Idle panes: CLI switch OK (stop → start)
#   e.g.) Need Codex 5.3 but only Claude Code is idle → downgrade to Claude Code OK
#   e.g.) Need Claude Code but only Codex is idle → kill Codex and launch Claude Code OK
#   Actual CLI restart processing is handled by karo.md (this function only returns agent_id)
#
# Arguments:
#   $1: recommended_model — return value of get_recommended_model()
#
# Return value:
#   Idle ashigaru ID (e.g., "ashigaru4") — exact match or fallback
#   All busy → "QUEUE"
#   Error → "" (empty string)
#
# Usage example:
#   agent=$(find_agent_for_model "claude-sonnet-4-6")
#   case "$agent" in
#     QUEUE) echo "Add to waiting queue" ;;
#     "")    echo "Error" ;;
#     *)     echo "Assign to ashigaru: $agent (karo.md decides CLI switch)" ;;
#   esac
find_agent_for_model() {
    local recommended_model="$1"

    if [[ -z "$recommended_model" ]]; then
        return 1
    fi

    local settings="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"

    # Extract ashigaru using recommended_model from cli.agents in settings.yaml
    local candidates
    candidates=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml, sys

try:
    with open('${settings}') as f:
        cfg = yaml.safe_load(f) or {}
    cli_cfg = cfg.get('cli', {})
    agents = cli_cfg.get('agents', {})

    results = []
    for agent_id, spec in agents.items():
        # Only ashigaru (exclude karo, gunshi, shogun)
        if not agent_id.startswith('ashigaru'):
            continue
        if not isinstance(spec, dict):
            continue
        agent_model = spec.get('model', '')
        if agent_model == '${recommended_model}':
            results.append(agent_id)

    # Sort by number (ashigaru1, ashigaru2, ...)
    results.sort(key=lambda x: int(x.replace('ashigaru', '')) if x.replace('ashigaru', '').isdigit() else 99)
    print(' '.join(results))
except Exception:
    pass
" 2>/dev/null)

    # Check candidate ashigaru in order (find idle ones)
    # Reuse agent_is_busy_check from agent_status.sh
    local agent_status_lib="${CLI_ADAPTER_PROJECT_ROOT}/lib/agent_status.sh"

    if [[ -f "$agent_status_lib" ]]; then
        if ! declare -f agent_is_busy_check >/dev/null 2>&1; then
            # shellcheck disable=SC1090
            source "$agent_status_lib" 2>/dev/null
        fi
    fi

    local candidate
    for candidate in $candidates; do
        # Reverse-lookup tmux pane target by @agent_id
        local pane_target
        pane_target=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{@agent_id}' 2>/dev/null \
            | awk -v agent="$candidate" '$2 == agent {print $1}' | head -1)

        if [[ -z "$pane_target" ]]; then
            # No tmux session (unit test environment etc.) → return candidate as-is
            echo "$candidate"
            return 0
        fi

        # Busy check
        if declare -f agent_is_busy_check >/dev/null 2>&1; then
            local busy_rc
            agent_is_busy_check "$pane_target" 2>/dev/null
            busy_rc=$?
            # 0=busy, 1=idle, 2=not_found
            if [[ $busy_rc -eq 1 ]]; then
                echo "$candidate"
                return 0
            fi
        else
            # If agent_is_busy_check is unavailable, return first candidate (fallback)
            echo "$candidate"
            return 0
        fi
    done

    # Phase 2: All exact matches busy → fallback to any idle ashigaru
    # Lord's policy: "If Codex 5.3 is needed but only Claude Code is idle, use Claude Code"
    # Never kill/restart. Reuse idle panes.
    local all_agents
    all_agents=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml

try:
    with open('${settings}') as f:
        cfg = yaml.safe_load(f) or {}
    agents = cfg.get('cli', {}).get('agents', {})
    results = [k for k in agents if k.startswith('ashigaru')]
    results.sort(key=lambda x: int(x.replace('ashigaru', '')) if x.replace('ashigaru', '').isdigit() else 99)
    print(' '.join(results))
except Exception:
    pass
" 2>/dev/null)

    local fallback
    for fallback in $all_agents; do
        # Skip candidates already checked
        if [[ " $candidates " == *" $fallback "* ]]; then
            continue
        fi

        local fb_pane
        fb_pane=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{@agent_id}' 2>/dev/null \
            | awk -v agent="$fallback" '$2 == agent {print $1}' | head -1)

        if [[ -z "$fb_pane" ]]; then
            # No tmux session (test environment) → return fallback candidate
            echo "$fallback"
            return 0
        fi

        if declare -f agent_is_busy_check >/dev/null 2>&1; then
            agent_is_busy_check "$fb_pane" 2>/dev/null
            local fb_rc=$?
            if [[ $fb_rc -eq 1 ]]; then
                echo "$fallback"
                return 0
            fi
        fi
    done

    # All ashigaru busy → queue wait
    echo "QUEUE"
    return 0
}

# get_ashigaru_ids()
# Returns ashigaru ID list from cli.agents in settings.yaml (space-separated, sorted by number)
# Fallback: "ashigaru1 ashigaru2 ashigaru3 ashigaru4 ashigaru5 ashigaru6 ashigaru7"
get_ashigaru_ids() {
    local settings="${CLI_ADAPTER_SETTINGS:-${CLI_ADAPTER_PROJECT_ROOT}/config/settings.yaml}"
    local result
    result=$("$CLI_ADAPTER_PROJECT_ROOT/.venv/bin/python3" -c "
import yaml
try:
    with open('${settings}') as f:
        cfg = yaml.safe_load(f) or {}
    agents = cfg.get('cli', {}).get('agents', {})
    results = [k for k in agents if k.startswith('ashigaru')]
    results.sort(key=lambda x: int(x.replace('ashigaru', '')) if x.replace('ashigaru', '').isdigit() else 99)
    print(' '.join(results))
except Exception:
    pass
" 2>/dev/null)
    if [[ -n "$result" ]]; then
        echo "$result"
    else
        echo "ashigaru1 ashigaru2 ashigaru3 ashigaru4 ashigaru5 ashigaru6 ashigaru7"
    fi
}
