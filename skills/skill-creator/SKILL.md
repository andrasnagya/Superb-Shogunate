---
name: skill-creator
description: |
  Design, create, validate, and review Claude Code skills (SKILL.md).
  Compliant with the official Anthropic guide (2026-03). Used for new skill creation,
  improving existing skills, description quality checks, and trigger test design.
  Trigger: "create skill", "design skill", "create SKILL.md", "skill review".
  Do NOT use for: executing/invoking skills (that is done by the skills themselves).
argument-hint: "[skill-name or description]"
---

# Skill Creator — Claude Code Skills Design & Generation v2.0

Fully compliant with the official Anthropic "The Complete Guide to Building Skills for Claude" (2026-03).
Also compatible with the Agent Skills Open Standard (agentskills.io), designing skills that work with AI tools beyond Claude Code.

## North Star

**Design and create reusable, high-quality skills in the shortest time possible.**
Skill value = trigger accuracy x output quality x maintainability.

## Frontmatter Reference (All Fields)

```yaml
---
# === Required fields ===
name: skill-name              # kebab-case, max 64 chars. Defaults to directory name if omitted
                               # Names containing "claude" / "anthropic" are forbidden (reserved words)
description: |                 # [MOST IMPORTANT] The sole basis for trigger decisions. Max 1024 chars
  Specify What + When. Include trigger words.
  Prevent false triggers with negative triggers (Do NOT use for...).

# === Optional fields ===
argument-hint: "[target]"      # Hint displayed during completion. For skills with arguments
disable-model-invocation: false # true = only invoked manually via /name (for skills with side effects)
user-invocable: true           # false = hidden from / menu (for background knowledge skills)
allowed-tools: Read, Grep, Bash # Allowed tools. Specifying this also restricts. Omit = inherit all tools
model: sonnet                  # Model for skill execution (omit = inherit from parent)
context: fork                  # fork = isolated execution in sub-agent
agent: general-purpose         # Agent type for fork: Explore, Plan, general-purpose
license: MIT                   # For OSS skills. MIT, Apache-2.0, etc.
compatibility: |               # Environment requirements (1-500 chars)
  Claude Code + tmux + WSL2
metadata:                      # Custom metadata
  author: your-name
  version: 1.0.0
  mcp-server: server-name      # For MCP-integrated skills
hooks:                         # Hook definitions within skill
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/lint.sh"
---
```

### Frontmatter Security Constraints

- XML angle brackets `< >` **forbidden** (prompt injection prevention)
- "claude" / "anthropic" in `name` is forbidden (reserved words)
- Frontmatter is expanded within the system prompt → malicious content is dangerous

## Description Design (Most Important -- Determines Trigger Quality)

The description is the **sole basis** Claude Code uses to decide "whether to use this skill or not."
The body text is NOT used for trigger decisions. **Max 1024 characters**.

### Structure: `[What] + [When] + [Negative trigger]`

```yaml
# Good — specific, has triggers, has negative trigger
description: |
  Analyzes Figma design files and generates developer handoff documents.
  Triggers on .fig file upload, or when asked for "design spec", "component docs",
  or "design to code".
  Do NOT use for: general image processing or UI design (use interface-design skill).

# Bad — vague, no triggers
description: Document processing
```

### 7-Item Checklist

| # | Check | Bad Example | Good Example |
|---|-------|-------------|--------------|
| 1 | What: state what it does | "Document processing" | "Extract tables from PDF and convert to CSV" |
| 2 | When: state when to use | (none) | "Used in data analysis workflows" |
| 3 | Contains trigger words | (none) | "Triggers on 'article QC', 'validation'" |
| 4 | Specific action verbs | "manage" | "extract, convert, validate" |
| 5 | Length: max 1024 chars | 1 word or too long | 2-3 sentences covering overview + triggers + exclusions |
| 6 | Differentiated from existing skills | Overlaps with other skills | Clearly states unique scope |
| 7 | Negative trigger | None (false trigger risk) | "Do NOT use for: ..." |

### Description Debugging Technique

If the skill isn't triggering, ask Claude:
> "When would you use the [skill-name] skill?"

Claude will answer by quoting the description. Missing elements will become apparent.

## 3 Use Case Categories

Before designing a skill, identify which category it falls into:

| Category | Purpose | Example |
|----------|---------|---------|
| **1. Document & Asset Creation** | Deliverable generation (PDF, code, articles, etc.) | shogun-seo-writer |
| **2. Workflow Automation** | Step-by-step automation | shogun-git-release |
| **3. MCP Enhancement** | MCP tools + workflow knowledge | shogun-github-reviewer |

## 5 Design Patterns

### Pattern 1: Sequential Workflow
Dependencies between steps. Validation at each step + rollback on failure.

### Pattern 2: Multi-Service Coordination
Phase separation + data handoff + inter-phase validation.

### Pattern 3: Iterative Refinement
Generate → validation script → improve → re-validate. Stops at quality threshold.

### Pattern 4: Context-aware Selection
Dynamic tool/method selection based on context. Explain reasoning to user.

### Pattern 5: Domain Intelligence
Embed domain-specific rules into logic. Compliance and audit trails.

## Dynamic Features

### Argument Substitution

```
/my-skill wedding kekkon
```
- `$ARGUMENTS` → `wedding kekkon` (all arguments)
- `$0` → `wedding` (1st argument)
- `$1` → `kekkon` (2nd argument)

If `$ARGUMENTS` is not used in the body, it is automatically appended at the end.

### Dynamic Context `!`command``

Executes shell commands before loading the skill and embeds the results:

```markdown
## Current Branch
!`git branch --show-current`

## Recent Commits
!`git log --oneline -5`
```

## Execution Patterns

### Pattern A: Inline Execution (default)
Runs directly in the main conversation. For guideline-type and short tasks.

### Pattern B: Fork Execution (isolated)
Runs in a sub-agent with `context: fork`. For heavy processing and large outputs.
**Note**: Do not use fork for guideline-only skills. Sub-agents need a concrete task.

### Pattern C: Manual Only (has side effects)
Disables Claude's auto-triggering with `disable-model-invocation: true`. Only invoked via /name.

## File Structure

```
~/.claude/skills/skill-name/
├── SKILL.md              # Required. Max 5,000 words (~500 lines). Case-sensitive
├── scripts/              # Optional. Validation and execution scripts
├── references/           # Optional. Detailed API specs and rule sets
├── assets/               # Optional. Templates, fonts, icons
└── examples/             # Optional. Input/output samples
```

### Naming Rules
- Folder name: **kebab-case** (`notion-project-setup` ✅ / `Notion_Setup` ❌)
- `SKILL.md` is case-sensitive (`skill.md` ❌ / `SKILL.MD` ❌)
- **README.md forbidden** (inside skill folder). Documentation goes in SKILL.md or references/

### Progressive Disclosure (3-Layer Structure)

| Layer | Content | Load Timing |
|-------|---------|-------------|
| L1 | YAML frontmatter | **Always** (within system prompt) |
| L2 | SKILL.md body | When determined to be skill-related |
| L3 | references/, scripts/ | Referenced by Claude as needed |

The SKILL.md body should be **max 5,000 words**. Move details to references/.

## Test Strategy (3 Areas)

### 1. Triggering Test
```
Should trigger:
- "I want to create a new skill"
- "Review this SKILL.md"
- "Design a skill"

Should NOT trigger:
- "Execute the skill"
- "What's the weather?"
- "Write some code"
```

### 2. Functional Test
- Does it produce correct output?
- Does error handling work?
- Are edge cases handled?

### 3. Performance Test
Compare with and without the skill:
- Number of tool calls
- Token consumption
- Number of user rework cycles

**Pro Tip**: First iterate on one difficult task. Turn the successful approach into a skill.
Then expand test cases.

## Creation Workflow

When creating a skill, execute the following in order:

1. **Identify use cases**: Define 2-3 concrete scenarios
2. **Determine category**: Document / Workflow / MCP Enhancement
3. **Design description**: 7-item check + negative trigger + max 1024 chars
4. **Check for duplicates with existing skills**: Verify with `ls ~/.claude/skills/`
5. **Select execution pattern**: Inline / fork / manual only
6. **Design allowed-tools**: Restrict to the minimum necessary
7. **Design arguments**: `$0`, `$1` → specify in `argument-hint`
8. **Dynamic context**: Consider data to pre-fetch with `!`command``
9. **Write SKILL.md**: Max 5,000 words. Place critical instructions at the top
10. **Script validation**: Put critical checks in scripts/ (code is deterministic, language is non-deterministic)
11. **Test**: 3 areas — Triggering / Functional / Performance
12. **Deploy**: Place in `~/.claude/skills/skill-name/`

## Validation Script Recommendation

**Most important tip from the official guide**: Perform critical validation with scripts.
Code is deterministic; language interpretation is non-deterministic.

```bash
# Example scripts/validate.sh
#!/bin/bash
# Output file quality check
if [ $(wc -w < "$1") -lt 100 ]; then
  echo "ERROR: Output too short (min 100 words)"
  exit 1
fi
```

## Shogun System-Specific Rules

- Save location: `~/.claude/skills/shogun-{skill-name}/`
- Ashigaru discover skill candidates → reported to shogun via karo → shogun designs → Lord approves → karo creates
- Skills that need shogun system integration (inbox_write, task YAML, etc.) must include Bash in allowed-tools
- north_star should be placed in the **body, not frontmatter** (custom frontmatter fields are ignored by Claude Code)


## Anti-Patterns

| Don't | Reason | Instead |
|-------|--------|---------|
| SKILL.md over 5,000 words | Loading cost explodes, response quality drops | Split to references/ |
| Vague description | Won't trigger or false triggers | What + When + negative trigger |
| description over 1024 chars | Exceeds frontmatter limit | Keep concise, max 3 sentences |
| `< >` in description | Security violation | Do not use angle brackets |
| No negative trigger | False triggers between similar skills | Add "Do NOT use for: ..." |
| `context: fork` + guidelines only | Sub-agent gets lost | Use inline execution |
| `disable-model-invocation` + `user-invocable: false` | Nobody can invoke it | Use one or the other |
| Heavy processing without allowed-tools | Unintended tool usage | List only required tools |
| Custom fields in frontmatter | Ignored by Claude Code | Write in body Markdown |
| README.md in skill folder | Spec violation | Use SKILL.md or references/ |
| 50+ simultaneously active skills | Context pressure | Selective activation |
