---
name: shogun-bloom-config
description: >
  Interactive wizard: guided questions with multiple-choice options about subscriptions,
  then outputs a ready-to-paste capability_tiers YAML + fixed agent model assignments.
  Trigger: "capability_tiers", "bloom config", "routing setup", "set up model routing",
  "routing config", "capability_tiers setup", "model config", "subscription setup", "model routing"
---

# /shogun-bloom-config — Bloom Routing Wizard

## Overview

Answer just 2 guided multiple-choice questions to generate the optimal `capability_tiers`
configuration in ready-to-paste format.

**Output:**
1. `capability_tiers` YAML → paste directly into `config/settings.yaml`
2. `available_cost_groups` declaration
3. Fixed agent recommended models (Karo / Gunshi)
4. Coverage gap warnings (e.g. when Bloom L6 cannot be covered)

## When to Use

- Initial setup of `config/settings.yaml`
- Reconfiguration after adding/changing subscriptions
- "How should I set up capability_tiers?"
- After checking model list with `/shogun-model-list`

---

## Instructions

**IMPORTANT: Do NOT output the pattern tables directly. Always ask questions first using AskUserQuestion.**

### Step 1: Q1 — Claude plan (AskUserQuestion)

Call AskUserQuestion with the following:

```
question: "What is your Claude plan?"
header: "Claude Plan"
options:
  - label: "Max 20x ($200/mo)"
    description: "All models available: Opus, Sonnet, Haiku. 20x usage. Recommended for Spark dual operation."
  - label: "Max 5x ($100/mo)"
    description: "Same model access, 5x usage. Good if cost-conscious with sufficient volume."
  - label: "Pro ($20/mo)"
    description: "Opus, Sonnet, Haiku available. Standard usage. Sufficient for personal use."
  - label: "Free / None"
    description: "Sonnet and Haiku only (no Opus). L6 tasks will have a coverage gap."
```

### Step 2: Q2 — ChatGPT plan (AskUserQuestion)

Call AskUserQuestion with the following:

```
question: "What is your ChatGPT (OpenAI) plan?"
header: "ChatGPT Plan"
options:
  - label: "None (Claude only operation)"
    description: "Claude quota only. Simple configuration. Ashigaru use Haiku 4.5 as primary model."
  - label: "Plus ($20/mo)"
    description: "gpt-5.3-codex available (no Spark). Can supplement up to L4."
  - label: "Pro ($200/mo)"
    description: "Spark (1000 tok/s, Terminal-Bench 58.4%) + gpt-5.3 (77.3%) available. Ultimate configuration for 7 ashigaru (Recommended)"
```

### Step 2.5: Q3 — Rate limit preference (only when both subscriptions are active)

**Ask only when Q1=Pro/Max AND Q2=Plus or Pro.**
When both subscriptions are available, confirm which quota to use for processing the same Bloom level.

#### Q3a: Preferred quota for L3 tasks (bulk code generation, template application)

Call AskUserQuestion with:

```
question: "Which quota should be prioritized for L1-L3 tasks (bulk work, templates, simple implementation)?"
header: "L3 Quota Priority"
options:
  - label: "ChatGPT Pro (Spark / gpt-5.3) priority (Recommended)"
    description: "Blazing fast at 1000 tok/s with Spark. Reserves Claude Max quota for L5-L6."
  - label: "Claude Max (Haiku 4.5) priority"
    description: "Even utilization of Claude quota. Saves ChatGPT Pro quota for L4 headroom."
```

#### Q3b: Preferred quota for L4 tasks (analysis, code review, debugging) — only when Q2=Pro

Call AskUserQuestion with:

```
question: "Which quota should be prioritized for L4 tasks (analysis, debugging, code review)?"
header: "L4 Quota Priority"
options:
  - label: "ChatGPT Pro (gpt-5.3-codex) priority (Recommended)"
    description: "Terminal-Bench 77.3%. Leverages Codex Pro quota to reserve Claude quota."
  - label: "Claude Max (Sonnet 4.6) priority"
    description: "SWE-bench 79.6%. Process L4 with Claude quality. Concentrate ChatGPT Pro quota on Spark."
```

Adjust the capability_tiers max_bloom values based on these answers (see the custom sections in the patterns below).

### Step 3: Map answers to pattern

| Claude | ChatGPT | Pattern |
|--------|---------|---------|
| None/Free | None | A-Free |
| Pro/Max | None | A |
| None/Free | Plus | B |
| None/Free | Pro | C |
| Pro/Max | Plus | D |
| Pro/Max | Pro | **E (Full Power)** |

### Step 4: Output the matching pattern below

Output ONLY the matching pattern. Show:
1. Brief explanation (why this configuration)
2. `capability_tiers` YAML (copyable code block)
3. `available_cost_groups`
4. Fixed agent recommendations
5. Gap warnings (if any)
6. Next steps

---

## Pattern A-Free — Claude Free Only

> Sonnet 4.6 and Haiku 4.5 available but Opus 4.6 is not. L6 tasks are processed at L5 quality.

### Fixed Agents

| Agent | Recommended Model | Notes |
|-------|-------------------|-------|
| Karo | `claude-sonnet-4-6` | Opus unavailable, so Sonnet |
| Gunshi | `claude-sonnet-4-6` | Same as above |

### `config/settings.yaml` snippet

```yaml
available_cost_groups:
  - claude_max

capability_tiers:
  claude-haiku-4-5-20251001:
    max_bloom: 3       # L1-L3: $1/$5/M, SWE-bench 73.3%
    cost_group: claude_max
  claude-sonnet-4-6:
    max_bloom: 5       # L4-L5: $3/$15/M, SWE-bench 79.6%, 1M context
    cost_group: claude_max
```

### Coverage

| Bloom | Model | Notes |
|-------|-------|-------|
| L1–L3 | Haiku 4.5 | Fast and cheap |
| L4–L5 | Sonnet 4.6 | Analysis and design evaluation |
| **L6** | ⚠️ **GAP** | Opus 4.6 unavailable. Processed at L5 quality as fallback. |

---

## Pattern A — Claude Pro/Max Only ($20–$200/mo)

> All models up to Claude Opus available. Ashigaru auto-route: Haiku (L1-L3) → Sonnet (L4-L5) → Opus (L6).

### Fixed Agents

| Agent | Recommended Model | Notes |
|-------|-------------------|-------|
| Karo | `claude-opus-4-6` | L4-L6 orchestration with full strategic reasoning. |
| Gunshi | `claude-opus-4-6` | Deep QC and architecture evaluation for L5-L6 |

### `config/settings.yaml` snippet

```yaml
available_cost_groups:
  - claude_max

capability_tiers:
  claude-haiku-4-5-20251001:
    max_bloom: 3       # L1-L3: $1/$5/M, SWE-bench 73.3% — bulk task workhorse
    cost_group: claude_max
  claude-sonnet-4-6:
    max_bloom: 5       # L4-L5: $3/$15/M, SWE-bench 79.6%, 1M context
    cost_group: claude_max
  claude-opus-4-6:
    max_bloom: 6       # L6: $5/$25/M, SWE-bench 80.8% — true creative tasks only
    cost_group: claude_max
```

### Coverage

| Bloom | Model | Notes |
|-------|-------|-------|
| L1–L3 | Haiku 4.5 | SWE-bench 73.3%, 4pp below Sonnet 4.5, 1/3 cost |
| L4–L5 | Sonnet 4.6 | SWE-bench 79.6%, math +27pt (vs Sonnet 4.5) |
| L6 | Opus 4.6 | SWE-bench 80.8%. Only 1.2pp above Sonnet. Recommended for true L6 only |

---

## Pattern B — ChatGPT Plus Only ($20/mo)

> Spark unavailable. gpt-5.3-codex is the primary model. L6 gap exists. No-Claude config has lower cost-efficiency.

### Fixed Agents

> No Claude subscription → Karo/Gunshi also use Codex models. Beware of L6 gap.

| Agent | Recommended Model |
|-------|-------------------|
| Karo | `gpt-5.3-codex` |
| Gunshi | `gpt-5.1-codex-max` |

### `config/settings.yaml` snippet

```yaml
available_cost_groups:
  - chatgpt_plus

capability_tiers:
  gpt-5-codex-mini:
    max_bloom: 2       # L1-L2: lightweight tasks only
    cost_group: chatgpt_plus
  gpt-5.3-codex:
    max_bloom: 4       # L3-L4: Terminal-Bench 77.3%
    cost_group: chatgpt_plus
  gpt-5.1-codex-max:
    max_bloom: 5       # L5: highest Codex model
    cost_group: chatgpt_plus
```

### Coverage

| Bloom | Model | Notes |
|-------|-------|-------|
| L1–L2 | codex-mini | Minimal quota consumption |
| L3–L4 | gpt-5.3-codex | |
| L5 | codex-max | |
| **L6** | ⚠️ **GAP** | Codex unsuitable for novel creative design tasks. Claude Opus recommended. |

---

## Pattern C — ChatGPT Pro Only ($200/mo)

> Spark (1000 tok/s) available. L6 gap remains. Add Claude for complete coverage.

### Fixed Agents

| Agent | Recommended Model |
|-------|-------------------|
| Karo | `gpt-5.3-codex` |
| Gunshi | `gpt-5.1-codex-max` |

### `config/settings.yaml` snippet

```yaml
available_cost_groups:
  - chatgpt_pro

capability_tiers:
  gpt-5.3-codex-spark:
    max_bloom: 3       # L1-L3: 1000+ tok/s — ample throughput even for 7 ashigaru
    cost_group: chatgpt_pro
  gpt-5.3-codex:
    max_bloom: 4       # L4: Terminal-Bench 77.3%, 400K+ context
    cost_group: chatgpt_pro
  gpt-5.1-codex-max:
    max_bloom: 5       # L5: highest Codex capability
    cost_group: chatgpt_pro
```

### Coverage

| Bloom | Model | Notes |
|-------|-------|-------|
| L1–L3 | **Spark** | By Cerebras. Separate quota from Codex. |
| L4 | gpt-5.3-codex | |
| L5 | codex-max | |
| **L6** | ⚠️ **GAP** | L6 requires Claude Opus 4.6. |

---

## Pattern D — Claude Pro/Max + ChatGPT Plus ($40–$220/mo)


> Claude handles high-quality work (L4+). Codex Plus covers L1-L4 bulk tasks. No Spark.

### Fixed Agents

| Agent | Recommended Model |
|-------|-------------------|
| Karo | `claude-opus-4-6` |
| Gunshi | `claude-opus-4-6` |

### `config/settings.yaml` snippet

```yaml
available_cost_groups:
  - claude_max
  - chatgpt_plus

capability_tiers:
  gpt-5-codex-mini:
    max_bloom: 2       # L1-L2: Saves Claude quota. Consumes Codex Plus quota.
    cost_group: chatgpt_plus
  gpt-5.3-codex:
    max_bloom: 4       # L3-L4: Terminal-Bench 77.3%
    cost_group: chatgpt_plus
  claude-sonnet-4-6:
    max_bloom: 5       # L5: Claude-quality architecture evaluation
    cost_group: claude_max
  claude-opus-4-6:
    max_bloom: 6       # L6: Creative and strategic tasks
    cost_group: claude_max
```

### Coverage

| Bloom | Model | Notes |
|-------|-------|-------|
| L1–L2 | codex-mini | Consumes Codex Plus quota to save Claude Max |
| L3–L4 | gpt-5.3-codex | |
| L5 | Sonnet 4.6 | Switches to Claude quality |
| L6 | Opus 4.6 | |

---

## Pattern E — Claude Pro/Max + ChatGPT Pro ($220–$400/mo) ⭐ Full Power

> **Ultimate configuration**. Spark handles L1-L3 at blazing speed, Claude handles L4-L6 at high quality.
> $400/mo (Claude Max 20x + ChatGPT Pro) for full Bloom coverage.

### Fixed Agents

| Agent | Recommended Model | Reason |
|-------|-------------------|--------|
| Karo | `claude-opus-4-6` | L4-L6 orchestration. SWE-bench 80.8% |
| Gunshi | `claude-opus-4-6` | Deep QC for L5-L6. SWE-bench 80.8% |

### Config by Q3a x Q3b Answers

#### E-1: Spark priority (L3) x Codex priority (L4) ← **Default Recommended**

> Concentrate Claude Max quota on L5-L6. Process L1-L4 at high speed with ChatGPT Pro quota.

```yaml
available_cost_groups:
  - claude_max
  - chatgpt_pro

capability_tiers:
  gpt-5.3-codex-spark:
    max_bloom: 3       # L1-L3: 1000+ tok/s — high-speed L1-L3 processing with ChatGPT Pro quota
    cost_group: chatgpt_pro
  claude-haiku-4-5-20251001:
    max_bloom: 3       # L1-L3: Claude quota fallback (auto-switches when Spark quota runs out)
    cost_group: claude_max
  gpt-5.3-codex:
    max_bloom: 4       # L4: Terminal-Bench 77.3% — leverages Codex Pro quota for L4
    cost_group: chatgpt_pro
  claude-sonnet-4-6:
    max_bloom: 5       # L5: SWE-bench 79.6%, 1M context
    cost_group: claude_max
  claude-opus-4-6:
    max_bloom: 6       # L6: SWE-bench 80.8%
    cost_group: claude_max
```

#### E-2: Spark priority (L3) x Sonnet priority (L4)

> Process L4 with Claude quality. Concentrate ChatGPT Pro quota on Spark.

```yaml
available_cost_groups:
  - claude_max
  - chatgpt_pro

capability_tiers:
  gpt-5.3-codex-spark:
    max_bloom: 3       # L1-L3: 1000+ tok/s — concentrate ChatGPT Pro quota on Spark
    cost_group: chatgpt_pro
  claude-haiku-4-5-20251001:
    max_bloom: 3       # L1-L3: Claude quota fallback
    cost_group: claude_max
  claude-sonnet-4-6:
    max_bloom: 5       # L4-L5: SWE-bench 79.6% — L4 also at Claude quality
    cost_group: claude_max
  claude-opus-4-6:
    max_bloom: 6       # L6: SWE-bench 80.8%
    cost_group: claude_max
```

#### E-3: Haiku priority (L3) x Codex priority (L4)

> Process L3 with Claude quota and reserve ChatGPT Pro quota for L4's gpt-5.3.

```yaml
available_cost_groups:
  - claude_max
  - chatgpt_pro

capability_tiers:
  claude-haiku-4-5-20251001:
    max_bloom: 3       # L1-L3: SWE-bench 73.3% — process L3 with Claude quota
    cost_group: claude_max
  gpt-5.3-codex-spark:
    max_bloom: 2       # L1-L2 only: Spark used as supplement (L3 goes to Haiku)
    cost_group: chatgpt_pro
  gpt-5.3-codex:
    max_bloom: 4       # L4: Terminal-Bench 77.3% — concentrate ChatGPT Pro quota on L4
    cost_group: chatgpt_pro
  claude-sonnet-4-6:
    max_bloom: 5       # L5
    cost_group: claude_max
  claude-opus-4-6:
    max_bloom: 6       # L6
    cost_group: claude_max
```

#### E-4: Haiku priority (L3) x Sonnet priority (L4)

> Process all L1-L5 with Claude quota. ChatGPT Pro quota is conserved (Spark used only as supplement).

```yaml
available_cost_groups:
  - claude_max
  - chatgpt_pro

capability_tiers:
  gpt-5.3-codex-spark:
    max_bloom: 2       # L1-L2 supplement: Spark for ultra-lightweight tasks only
    cost_group: chatgpt_pro
  claude-haiku-4-5-20251001:
    max_bloom: 3       # L1-L3: unified processing with Claude quota
    cost_group: claude_max
  claude-sonnet-4-6:
    max_bloom: 5       # L4-L5: L4 also processed at Claude quality
    cost_group: claude_max
  claude-opus-4-6:
    max_bloom: 6       # L6
    cost_group: claude_max
```

### Coverage (E-1 baseline)

| Bloom | Model | Speed/Quality |
|-------|-------|---------------|
| L1–L3 | **Spark** → Haiku (fallback) | 1000 tok/s. Auto-switches when quota runs out |
| L4 | gpt-5.3-codex | Full utilization of Codex Pro quota |
| L5 | Sonnet 4.6 | Claude quality. Only 1.2pt gap with Opus at 1/5 the price |
| L6 | Opus 4.6 | Deploy for true creative tasks only |

> **Cost optimization insight**: Spark and gpt-5.3 have independent quotas. Both can be maximally utilized simultaneously.
> L5 is well served by Sonnet 4.6 instead of Opus (1.2% SWE-bench gap, ~1.7x price difference: $3/$15 vs $5/$25/M).

---

## Step 5: How to Apply the Configuration

After outputting the YAML, always guide the user through these application steps:

**1. Open `config/settings.yaml`**

```yaml
# Paste available_cost_groups and capability_tiers
available_cost_groups:
  - ...   ← paste here

capability_tiers:
  ...:    ← paste here
```

**2. Update fixed agent models**

```yaml
cli:
  agents:
    karo:
      type: claude
      model: claude-opus-4-6      # ← Change to Karo's recommended model
    gunshi:
      type: claude
      model: opus                  # ← Change to Gunshi's recommended model
    ashigaru1:                     # ← Ashigaru auto-route via capability_tiers
      type: codex                  #    Set CLI type to match subscription
      model: gpt-5.3-codex-spark
```

**3. Enable bloom_routing (optional)**

```yaml
bloom_routing: "manual"   # "off"(disabled) → "manual"(manual) → "auto"(fully automatic)
```

**4. Verify configuration (in terminal)**

```bash
# Subscription coverage check (detects Bloom levels that cannot be covered)
source lib/cli_adapter.sh && validate_subscription_coverage
```

---

## Quick Decision Tree

```
Do you have Claude Pro or higher?
  Yes → Claude available for fixed agents (Shogun/Karo/Gunshi) ✓
  No  → Codex only. Beware of L6 gap ⚠️

Do you have ChatGPT Pro ($200)?
  Yes → Spark (L1-L3, 1000 tok/s) + gpt-5.3 (L4) available ✓
  Plus ($20) → gpt-5.3 (L3-L4) only. No Spark.
  None → Claude Haiku handles ashigaru L1-L3 tasks
```
