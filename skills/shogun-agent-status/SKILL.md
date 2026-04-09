---
name: shogun-agent-status
description: "Displays the operational status of all agents (karo, ashigaru 1-7, gunshi) at a glance. Integrates tmux pane state, task YAML state, and unread inbox count."
---

# /agent-status - Agent Operational Status

## Overview

Determines the operational status of all agents by integrating two data sources into a unified display.

1. **Pane state**: Detects CLI-specific idle/busy patterns from the last 5 lines of tmux capture-pane
2. **Task YAML**: task_id and status from `queue/tasks/{agent}.yaml`
3. **Unread inbox**: Count of unprocessed messages in `queue/inbox/{agent}.yaml`

Supports both Claude Code and Codex CLI.

## When to Use

- When asked for "status check", "agent status", or "formation check"
- When checking whether ashigaru are available
- When looking for idle agents before distributing tasks
- When investigating whether an agent has stalled

## Instructions

Execute the following command:

```bash
bash scripts/agent_status.sh
```

## Reading the Output

| Column | Meaning |
|--------|---------|
| Agent | Agent name |
| CLI | CLI type (claude/codex) |
| Pane | tmux pane state: Active/Idle/Absent |
| Task ID | task_id from task YAML (---=unassigned) |
| Status | status from task YAML: assigned/done/idle etc. |
| Inbox | Unread inbox message count |

## Interpreting States

- **Pane=Idle + Status=done**: Task completed, awaiting next mission. Available for new task assignment.
- **Pane=Active + Status=assigned**: Actively executing a task. Leave them be.
- **Pane=Idle + Status=assigned**: Task assigned but CLI has stalled. Investigation required.
- **Pane=Active + Status=done**: Working on other duties after task completion (inbox processing, etc.).
- **Inbox > 0**: Unread messages present. The agent may not have processed them.
- **Pane=Absent**: tmux pane does not exist (deployment not executed or pane killed).
