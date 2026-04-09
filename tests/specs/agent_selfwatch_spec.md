# Agent Self-Watch Test Specification

| Field | Details |
|---|---|
| Document ID | ASW-SPEC-001 |
| parent_cmd | cmd_107 |
| task_id | subtask_107b |
| Created | 2026-02-09 |
| Reference Requirements | reports/requirements_agent_selfwatch.md |
| Scope | Agent self-watch Phase 1-3 (TDD Step 2) |

---

## 1. Purpose

This specification decomposes the FR/NFR defined in `reports/requirements_agent_selfwatch.md`
into verifiable test cases prior to implementation.

Goals:
- Define test case IDs and expected values for each FR/NFR
- Clarify unit test scope (inbox processing, monitoring, concurrency control, escalation)
- Separate E2E scope as "Lord-owned"

---

## 2. Test Levels and Ownership

| Level | Name | Owner | Execution Environment | Purpose |
|---|---|---|---|---|
| L1 | Unit | Ashigaru (this task) | bats + bash + python3 | Individual function/logic verification |
| L2 | Integration | Karo | L1 + tmux + inotify-tools | Integration verification of watcher/CLI boundary |
| L3 | E2E | **Lord** | Full production tmux | End-to-end confirmation including chain of command |

Notes:
- `SKIP=0` is mandatory. If SKIP is 1 or more, treated as "incomplete."
- This specification covers Step 2. Implementation and execution are in subsequent Step 3 onward.

---

## 3. FR Test Case List

### 3.1 Phase 1

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-FR-001 | FR-001 unread recovery at startup | L1 | Immediately after startup | With unread messages, `process_unread_once` runs once with 0 missed messages |
| TC-FR-002 | FR-002 self-watch monitoring | L1/L2 | inotify + timeout | Unread detected via timeout even when inotify is missing |
| TC-FR-003 | FR-003 type-based routing | L1 | Message type branching | `task_assigned`/`clear_command`/`model_switch` branch to correct processing lanes |
| TC-FR-004 | FR-004 mutual exclusion integrity | L1/L2 | flock + atomic | YAML not corrupted under contention, read updates do not roll back |
| TC-FR-005 | FR-005 post-task inbox check | L1/L3 | Behavior right after completion | Checks unread immediately after completion; does not transition to idle if unread exist |
| TC-FR-006 | FR-006 observability metrics | L1 | Metrics recording | `unread_latency_sec`/`read_count`/`estimated_tokens` can be computed |
| TC-FR-007 | FR-007 feature flag migration | L1/L2 | Flag switching | Phase switching works; when OFF, reverts to current-compatible mode |

### 3.2 Phase 2

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-FR-008 | FR-008 normal nudge elimination | L2 | send-keys reduction | `send-keys inboxN` is not executed for normal messages |
| TC-FR-009 | FR-009 special command compatibility | L1/L2 | Compatibility | Existing behavior of `clear_command`/`model_switch` is maintained |
| TC-FR-010 | FR-010 summary-first | L1 | Fast-path | Full read avoided when unread_count=0; full read only when needed |

### 3.3 Phase 3

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-FR-011 | FR-011 send-keys as last resort | L2/L3 | Recovery only | Zero send-keys usage during normal operation; fires only during anomalies |
| TC-FR-012 | FR-012 threshold redefinition | L1/L2 | Escalation | No excessive recovery loops per threshold/cooldown rules |
| TC-FR-013 | FR-013 alternative IPC evaluation hook | L1 | Extensibility | PoC can be introduced/withdrawn without corrupting the canonical YAML |

### 3.4 Common

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-FR-014 | FR-014 backward compatible IF | L1/L2 | Interface | Inbox YAML schema / inbox_write IF / message type compatibility maintained |
| TC-FR-015 | FR-015 implementation/CI integration | L1/L2 | Integration | spec → bats → CI traceable by the same ID |

---

## 4. NFR Test Case List

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-NFR-001 | NFR-001 reliability | L2/L3 | Unread loss prevention | Zero unread message loss; reprocessing is idempotent |
| TC-NFR-002 | NFR-002 backward compatibility | L1/L2 | Regression | No regression with existing inbox_write / existing YAML |
| TC-NFR-003 | NFR-003 token efficiency | L1/L2 | No Idle Read | Zero full reads while idle; estimated tokens/day within threshold |
| TC-NFR-004 | NFR-004 operability | L2 | Failure recovery | Recoverable using runbook only; 100% reproducibility |
| TC-NFR-005 | NFR-005 portability | L2/L3 | Environment differences | No contradictions in WSL2/Linux/Docker/SSH policies |
| TC-NFR-006 | NFR-006 observability | L1 | Logs/metrics | Key metrics can be continuously collected |
| TC-NFR-007 | NFR-007 maintainability | L1 | Separation of concerns | Watcher responsibilities do not bloat; standard path and recovery path are separated |
| TC-NFR-008 | NFR-008 testability | L1 | Traceability | FR/NFR → TC → bats mapping has no gaps |

---

## 5. Unit Test Scope (Step 3 target)

## 5.1 Inbox processing

- UT-INBOX-001: unread_count calculation (empty / read-only / mixed)
- UT-INBOX-002: Type-based branching (task_assigned / clear / model / unknown)
- UT-INBOX-003: Idempotency of read update (no corruption on reprocessing same message)
- UT-INBOX-004: Mandatory execution of `process_unread_once` at startup

Expected:
- Zero error in unread calculation
- No abnormal termination even for unknown type
- YAML structure remains valid after read update

## 5.2 Monitoring (self-watch)

- UT-WATCH-001: Processing triggered by inotify event
- UT-WATCH-002: Caught by timeout fallback
- UT-WATCH-003: No Idle Read rule (full read forbidden while idle)

Expected:
- Unread recovered via timeout even when events are missed
- No unnecessary full reads while idle

## 5.3 Concurrency control

- UT-LOCK-001: Safe retry under flock contention
- UT-LOCK-002: No YAML corruption after atomic replace
- UT-LOCK-003: Consistency under concurrent updates (no rollback)

Expected:
- Integrity maintained even under lock contention
- No corrupted YAML generated

## 5.4 Escalation

- UT-ESC-001: Phase 1/2/3 transition based on unread age
- UT-ESC-002: Cooldown suppresses `/clear` spam
- UT-ESC-003: Nudge deferred when busy
- UT-ESC-004: Nudge send skipped when self-watch is active

Expected:
- Only expected actions fire per time conditions
- No erroneous sends under busy/self-watch conditions

---

## 6. Integration Test Scope (karo-owned)

- IT-001: Coordination of watcher + agent + inbox_write
- IT-002: CLI-based branching (claude/codex/copilot)
- IT-003: send-keys elimination on normal path (Phase 2)
- IT-004: Last-resort recovery under fault injection (Phase 3)

Expected:
- Boundary inconsistencies invisible to unit tests are resolved
- Reproducible in inter-agent operation

---

## 7. E2E Scope (Lord-owned)

E2E in this specification is **Lord-owned**; karo/ashigaru do not execute these.

Targets:
- E2E-001: Full chain completion: Shogun → Karo → Ashigaru
- E2E-002: Long-running operation including redo/clear
- E2E-003: Stability and unread backlog under 9-agent parallel operation

Expected:
- Production viability under hierarchical organization operation
- /clear dependency does not grow excessively
- Key metrics remain within acceptable range

---

## 8. Prerequisites (Preflight)

- `bash`, `python3`, `bats` are available
- For L2 and above, `tmux` and `inotifywait` are available
- Read/write access to queue/tests paths under test

When prerequisites are not met:
- Do not execute the affected tests; record the reason they cannot be met
- SKIP reporting is forbidden (treated as incomplete)

---

## 9. FR/NFR Traceability Operating Rules

- Embed TC ID in bats test names (e.g., `TC-FR-001`)
- Record test results as PASS/FAIL per TC ID
- Maintain at least one TC per requirement (no gaps allowed)

---

## 10. E2E Execution Runbook (for Lord, chronological)

This section provides the execution steps to satisfy the `cmd_117` requirement: "Prepare for Lord to execute E2E tests."
The execution order is fixed. If a step fails, follow the diagnosis for that step to recover before continuing.

| Precondition | Procedure | Expected Result | Failure Diagnosis | Evidence |
|---|---|---|---|---|
| Step 1: tmux infrastructure is running | Run `tmux ls` and confirm `shogun` and `multiagent` sessions. | Both sessions exist and are not terminated. | If sessions are missing, run `bash scripts/shohou/start_or_resume.sh` and re-check. | `tests/results/e2e_cmd117_step01_tmux_sessions.txt` |
| Step 2: Karo/ashigaru monitoring processes are running | Run `pgrep -af \"inbox_watcher.sh|inotifywait\"`. | Monitoring processes are confirmed. | If monitoring is not visible, restart watchers, then check recent errors in `logs/`. | `tests/results/e2e_cmd117_step02_watchers.txt` |
| Step 3: No unread backlog explosion before E2E start | Run `for f in queue/inbox/*.yaml; do c=$(awk '/read: false/{n++} END{print n+0}' \"$f\"); echo \"$(basename \"$f\"):$c\"; done`. | Unread count for target agents is within acceptable range (0 in principle). | If unread > 0 remains, complete normal processing first, then re-run Step 3. | `tests/results/e2e_cmd117_step03_unread_baseline.txt` |
| Step 4: Launch E2E-001 (Shogun → Karo → Ashigaru full chain) | Send `bash scripts/inbox_write.sh karo \"cmd117_e2e_probe: chain test\" cmd_new shogun` and confirm karo processing and ashigaru task deployment. | Karo inbox is processed and tasks flow to at least 1 ashigaru. | If no change after 2+ minutes, check `queue/inbox/karo.yaml` and `logs/inbox_watcher/`, inspect Phase 2/3 escalation conditions. | `tests/results/e2e_cmd117_step04_chain.md` |
| Step 5: Verify E2E-002 (redo/clear flow) | Send `clear_command` to target ashigaru (e.g., `bash scripts/inbox_write.sh ashigaru6 \"cmd117_e2e_probe redo\" clear_command karo`) and confirm recovery flow. | After `/clear`, target ashigaru re-reads task YAML and resumes without halting. | If recovery fails, check `read` update and task status in `queue/inbox/ashigaru6.yaml`, inspect for race conditions. | `tests/results/e2e_cmd117_step05_redo_clear.md` |
| Step 6: Verify E2E-003 (9-agent parallel stability) | Re-run `tmux list-panes -t multiagent -F '#{pane_index}:#{pane_current_command}'` and Step 3 to check backlog during parallel operation. | Unread backlog does not continuously increase even under multi-agent operation. | If backlog grows, check busy-skip/cooldown misconfiguration and collect logs for the affected agent. | `tests/results/e2e_cmd117_step06_parallel_health.txt` |
| Step 7: Record E2E completion verdict | Record PASS/FAIL for E2E-001/002/003, blocking factors, and retry plan in `tests/results/e2e_cmd117_readiness.md`. | A verdict record is complete that allows the Lord to immediately decide the next action. | If evidence is insufficient, re-collect missing evidence before finalizing the record. | `tests/results/e2e_cmd117_readiness.md` |

---

The above satisfies `cmd_107` AC-2 (test specification complete) and the `cmd_117` requirement for "E2E-ready procedure preparation."
