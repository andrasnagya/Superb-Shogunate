---
name: shogun-readme-sync
description: "Checks and synchronizes README.md (English) and README_ja.md (Japanese). Ensures both language versions are always updated together when README changes."
---

# /shogun-readme-sync - README EN/JA Sync

## Overview

Detects differences between README.md (English) and README_ja.md (Japanese), then adds missing sections and fixes numbering discrepancies.

Workflow when README changes:
1. Diff detection (automatically determines which version is newer)
2. List missing sections
3. Execute translation and additions
4. Section number consistency check

## When to Use

- After editing a README (feature additions, section additions, structural changes)
- When asked for "README update", "README sync", or "readme sync"
- When told "Japanese version too" after writing a new feature in the README
- README consistency check before PR creation

## Instructions

### Step 1: Diff Detection

Read both files and detect differences from the following perspectives:

```bash
# Read both files
Read README.md
Read README_ja.md
```

**Check items:**

| Item | How to verify |
|------|---------------|
| Section count | Do the number of `###` headers match? |
| Section numbers | Are numbered sections (`### ... 1.`, `### ... 2.` etc.) sequential? |
| File structure | Does the file list in the File Structure section match? |
| Version section | Do both have `What's New` / `新機能` sections? |
| Collapsible content | Do `<details>` blocks match in presence/absence? |

### Step 2: Diff Report

Report the detected differences:

```
README Sync Check Results:

Missing EN → JA:
- Section "Agent Status Check" is missing from the Japanese version
- lib/agent_status.sh is not listed in the file structure
- v3.3.2 section is missing

Missing JA → EN:
- (none)

Section Number Misalignment:
- JA: Screenshot is #5 but EN has it as #6
```

### Step 3: Execute Sync

Fix the differences. Translation rules:

| EN | JA |
|----|-----|
| Agent Status Check | エージェント稼働確認 |
| Screenshot Integration | スクリーンショット連携 |
| Context Management | コンテキスト管理 |
| Phone Notifications | スマホ通知 |
| Pane Border Task Display | ペインボーダータスク表示 |
| Shout Mode | Shout Mode (sengoku echo) |
| Event-Driven Communication | イベント駆動通信 |
| Parallel Execution | 並列実行 |
| Non-Blocking Workflow | ノンブロッキングワークフロー |
| Cross-Session Memory | セッション間記憶 |
| Bottom-Up Skill Discovery | ボトムアップスキル発見 |

**Translation policy:**
- Keep technical terms as-is (tmux, YAML, CLI, MCP, inotifywait, etc.)
- Do not translate commands inside code blocks
- Match output examples to the Japanese version ("稼働中", "待機中", etc.)
- Use the same emoji as the EN version

### Step 4: Final Consistency Check

After corrections, verify:
1. Section count matches in both files
2. Numbered sections have correct sequential numbering
3. File structure section entries match
4. Version sections exist in both files

## Guidelines

- **EN is authoritative**: New features are typically written in EN first. JA follows.
- **Preserve JA-specific expressions**: Unique Japanese expressions like "sengoku echo" are kept as-is
- **Not one-directional**: Detect changes that exist only in EN as well as those only in JA
- **Auto-increment section numbers**: When inserting a section mid-way, increment all subsequent numbers
- **Do not touch code blocks**: Text inside bash/yaml/markdown code blocks is not a translation target
