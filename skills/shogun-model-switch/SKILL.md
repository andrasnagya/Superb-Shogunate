---
name: shogun-model-switch
description: |
  Live-switches an agent's CLI/model. Updates settings.yaml → /exit → launches new CLI →
  updates pane metadata in one shot. Also controls Thinking on/off.
  Trigger: "model switch", "switch to Sonnet", "change to Opus", "switch all ashigaru", "turn off Thinking".
argument-hint: "[agent-name target-model e.g. ashigaru1 sonnet]"
allowed-tools: Bash(bash scripts/switch_cli.sh *), Read, Edit
---

# /model-switch - Agent CLI Live Switcher

## Overview

Live-switches the CLI type, model, and Thinking settings of a running agent.
Executes the full pipeline: `settings.yaml` → `build_cli_command()` → `/exit` → new CLI launch → pane metadata update.

## When to Use

- "Switch ashigaru3 to Opus", "Switch all ashigaru to Sonnet"
- "Model switch", "Change model", "Change CLI"
- "Turn off Thinking", "Enable Thinking"
- "Switch from Codex back to Claude", "Switch to Spark"
- When you want to change models based on the nature of the task

## Architecture

```
settings.yaml (source of truth)
    │
    ├─ cli.agents.{id}.type      → claude | codex | copilot | kimi
    ├─ cli.agents.{id}.model     → claude-sonnet-4-6 | claude-opus-4-6 | ...
    └─ cli.agents.{id}.thinking  → true | false
         │
         ├── build_cli_command()
         │   └─ thinking: false → "MAX_THINKING_TOKENS=0 claude --model ..."
         │   └─ thinking: true  → "claude --model ..."
         │
         └── get_model_display_name()
             └─ thinking: true  → "Sonnet+T" / "Opus+T"
             └─ thinking: false → "Sonnet" / "Opus"
```

## Display Name Mapping

| model (settings.yaml) | Display Name | +Thinking |
|---|---|---|
| claude-sonnet-4-6 | Sonnet | Sonnet+T |
| claude-opus-4-6 | Opus | Opus+T |
| claude-haiku-4-5-20251001 | Haiku | Haiku+T |
| gpt-5.3-codex | Codex | — |
| gpt-5.3-codex-spark | Spark | — |

## Instructions

### Single Agent Switch

```bash
# Restart with current settings.yaml values (when you just want to reset the CLI)
bash scripts/switch_cli.sh ashigaru3

# Change model (settings.yaml is also automatically updated)
bash scripts/switch_cli.sh ashigaru3 --model claude-opus-4-6

# Change CLI type entirely (Codex → Claude)
bash scripts/switch_cli.sh ashigaru3 --type claude --model claude-sonnet-4-6

# Claude → Codex Spark
bash scripts/switch_cli.sh ashigaru5 --type codex --model gpt-5.3-codex-spark
```

### Bulk Switch

```bash
# Switch all ashigaru to Sonnet
for i in $(seq 1 7); do
    bash scripts/switch_cli.sh ashigaru$i --type claude --model claude-sonnet-4-6
done

# Switch all ashigaru to Spark
for i in $(seq 1 7); do
    bash scripts/switch_cli.sh ashigaru$i --type codex --model gpt-5.3-codex-spark
done

# Restart all agents (including karo and gunshi)
for agent in karo ashigaru1 ashigaru2 ashigaru3 ashigaru4 ashigaru5 ashigaru6 ashigaru7 gunshi; do
    bash scripts/switch_cli.sh "$agent"
done
```

### Thinking Control

Edit the `thinking` field in settings.yaml, then run switch_cli.sh:

```yaml
# config/settings.yaml
cli:
  agents:
    ashigaru3:
      type: claude
      model: claude-opus-4-6
      thinking: false  # ← Launches with MAX_THINKING_TOKENS=0
```

```bash
# Restart after editing settings.yaml
bash scripts/switch_cli.sh ashigaru3
```

Steps to toggle Thinking ON/OFF:
1. Change the target agent's `thinking:` to `true` / `false` in `config/settings.yaml`
2. Restart with `bash scripts/switch_cli.sh <agent_id>`
3. The presence/absence of `+T` is reflected in the pane border

### Via inbox (switch by karo)

```bash
# When karo switches an ashigaru's CLI
bash scripts/inbox_write.sh ashigaru3 "--type claude --model claude-opus-4-6" cli_restart karo
```

inbox_watcher detects the `cli_restart` type and automatically executes switch_cli.sh.

## What switch_cli.sh Does (internal)

1. **Update settings.yaml** (only when `--type`/`--model` is specified)
2. **Detect current CLI type** (tmux pane metadata `@agent_cli`)
3. **Send CLI-specific exit command**
   - Claude: `/exit` + Enter
   - Codex: Escape → Ctrl-C → `/exit` + Enter
   - Copilot/Kimi: Ctrl-C → `/exit` + Enter
4. **Wait for shell prompt return** (max 15 seconds, captured every 1 second)
5. **Build new command with `build_cli_command()`**
   - thinking: false → `MAX_THINKING_TOKENS=0` prefix applied
6. **Launch new CLI via tmux send-keys** (text and Enter sent separately)
7. **Update pane metadata**: `@agent_cli`, `@model_name`

## Files

| File | Role |
|---|---|
| `scripts/switch_cli.sh` | Main script |
| `lib/cli_adapter.sh` | `build_cli_command()`, `get_model_display_name()` |
| `config/settings.yaml` | Agent settings (type, model, thinking) |
| `scripts/inbox_watcher.sh` | `cli_restart` type handling |
| `logs/switch_cli.log` | Execution log |

## Constraints

- **Never send to the shogun pane**: switch_cli.sh targets only panes in the multiagent session
- **Beware of running agents**: Switching during task execution may cause data loss. Confirm idle state before executing
- **Codex → Claude switch**: Codex's /exit can be unstable. Use Escape + Ctrl-C for a clean termination
- **Coordination with inbox_watcher**: After cli_restart, inbox_watcher's CLI_TYPE variable is also automatically updated
