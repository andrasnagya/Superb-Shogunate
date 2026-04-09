# Dynamic Model Routing Test Specification

| Field | Details |
|---|---|
| Document ID | DMR-SPEC-001 |
| Issue | #53 |
| Created | 2026-02-17 |
| Reference Requirements | reports/requirements_dynamic_model_routing.md |
| Scope | Phase 1-4 (TDD: test-first) |

---

## 1. Purpose

This specification decomposes the FR/NFR defined in `reports/requirements_dynamic_model_routing.md`
into verifiable test cases prior to implementation.

Goals:
- Iterate test → implementation incrementally from Phase 1 onward
- Advance to the next Phase only after all tests in the current Phase PASS
- Guarantee no regression against existing tests (test_cli_adapter.bats)

---

## 2. Test Levels and Ownership

| Level | Name | Owner | Execution Environment | Purpose |
|---|---|---|---|---|
| L1 | Unit | Ashigaru | bats + bash + python3 | Individual function/logic verification |
| L2 | Integration | Karo | L1 + tmux + inbox_write | Integration verification of model_switch coordination |
| L3 | E2E | Lord | Full production tmux | End-to-end confirmation: Bloom analysis → switch → execution |

Notes:
- `SKIP=0` is mandatory. If SKIP is 1 or more, treated as "incomplete."
- Phase 1 includes L1 tests only. L2 added from Phase 2 onward.

---

## 3. Phase 1 Test Cases — capability_tier definition

### 3.1 FR-01: settings.yaml capability_tiers section

| TC ID | Requirement | Level | Input | Expected |
|---|---|---|---|---|
| TC-DMR-001 | FR-01 basic read | L1 | YAML with capability_tiers defined | No parse error, max_bloom readable for each model |
| TC-DMR-002 | FR-01 section absent | L1 | YAML without capability_tiers | No error, backward compatible behavior |
| TC-DMR-003 | FR-01 cost_group read | L1 | YAML with capability_tiers defined | cost_group readable for each model |

### 3.2 FR-02: get_capability_tier()

| TC ID | Requirement | Level | Input | Expected |
|---|---|---|---|---|
| TC-DMR-010 | FR-02 Spark → 3 | L1 | model="gpt-5.3-codex-spark" | "3" |
| TC-DMR-011 | FR-02 Codex 5.3 → 4 | L1 | model="gpt-5.3" | "4" |
| TC-DMR-012 | FR-02 Sonnet → 5 | L1 | model="claude-sonnet-4-5-20250929" | "5" |
| TC-DMR-013 | FR-02 Opus → 6 | L1 | model="claude-opus-4-6" | "6" |
| TC-DMR-014 | FR-02 undefined model → 6 | L1 | model="unknown-model" | "6" |
| TC-DMR-015 | FR-02 section absent → 6 | L1 | capability_tiers undefined | "6" |
| TC-DMR-016 | FR-02 corrupted YAML → 6 | L1 | Corrupted YAML | "6" |
| TC-DMR-017 | FR-02 empty string → 6 | L1 | model="" | "6" |

### 3.3 FR-03: get_recommended_model()

| TC ID | Requirement | Level | Input | Expected |
|---|---|---|---|---|
| TC-DMR-020 | FR-03 L1 → Spark | L1 | bloom_level=1 | "gpt-5.3-codex-spark" |
| TC-DMR-021 | FR-03 L2 → Spark | L1 | bloom_level=2 | "gpt-5.3-codex-spark" |
| TC-DMR-022 | FR-03 L3 → Spark | L1 | bloom_level=3 | "gpt-5.3-codex-spark" |
| TC-DMR-023 | FR-03 L4 → Codex 5.3 | L1 | bloom_level=4 | "gpt-5.3" |
| TC-DMR-024 | FR-03 L5 → Sonnet | L1 | bloom_level=5 | "claude-sonnet-4-5-20250929" |
| TC-DMR-025 | FR-03 L6 → Opus | L1 | bloom_level=6 | "claude-opus-4-6" |
| TC-DMR-026 | FR-03 section absent → empty | L1 | capability_tiers undefined | "" (empty string) |
| TC-DMR-027 | FR-03 out of range(0) → exit 1 | L1 | bloom_level=0 | exit code 1 |
| TC-DMR-028 | FR-03 out of range(7) → exit 1 | L1 | bloom_level=7 | exit code 1 |
| TC-DMR-029 | FR-03 cost priority | L1 | chatgpt_pro and claude_max at same bloom | chatgpt_pro group model is preferred |

### 3.4 FR-04: get_cost_group()

| TC ID | Requirement | Level | Input | Expected |
|---|---|---|---|---|
| TC-DMR-030 | FR-04 Spark → chatgpt_pro | L1 | model="gpt-5.3-codex-spark" | "chatgpt_pro" |
| TC-DMR-031 | FR-04 Opus → claude_max | L1 | model="claude-opus-4-6" | "claude_max" |
| TC-DMR-032 | FR-04 undefined → unknown | L1 | model="unknown" | "unknown" |
| TC-DMR-033 | FR-04 section absent → unknown | L1 | capability_tiers undefined | "unknown" |

### 3.5 NFR-01: Backward Compatibility

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-040 | NFR-01 no existing test regression | L1 | test_cli_adapter.bats | All tests PASS after Phase 1 code addition |
| TC-DMR-041 | NFR-01 legacy settings.yaml compat | L1 | Neither cli nor capability_tiers present | get_cli_type, get_agent_model, etc. return same results as before |

### 3.6 NFR-05: Testability

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-050 | NFR-05 config injection | L1 | CLI_ADAPTER_SETTINGS | Test YAML can be injected |

### 3.7 NFR-06: Idempotency

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-055 | NFR-06 consecutive call consistency | L1 | Same input called twice | get_recommended_model() returns same result |

---

## 4. Phase 2 Test Cases — Karo manual model_switch

### 4.1 FR-05: Karo manual model_switch

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-100 | FR-05 switch not required | L1 | bloom=3, model=spark | Determined as switch not required |
| TC-DMR-101 | FR-05 switch required | L1 | bloom=4, model=spark | Determined as switch required |
| TC-DMR-102 | FR-05 capability_tiers absent | L1 | Section missing | Assessment skipped |
| TC-DMR-103 | FR-05 bloom field absent | L1 | Task YAML without bloom_level | Assessment skipped |

### 4.2 FR-06: Karo model_switch decision logic

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-110 | FR-06 same-CLI switch | L2 | codex spark → codex 5.3 | model_switch inbox sent |
| TC-DMR-111 | FR-06 cross-CLI | L2 | bloom=5, codex ashigaru | Reassigned to Claude ashigaru |
| TC-DMR-112 | FR-06 Codex ashigaru switch skip | L2 | model_switch to Codex ashigaru | Silent skip |
| TC-DMR-113 | FR-06 no send when switch not needed | L2 | bloom=3, spark ashigaru | No inbox sent |

### 4.3 NFR-02: Model Switch Latency

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-120 | NFR-02 function response speed | L1 | get_capability_tier() | Within 500ms |
| TC-DMR-121 | NFR-02 recommended model response speed | L1 | get_recommended_model() | Within 500ms |

### 4.4 NFR-03: CLI Compatibility

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-130 | NFR-03 Codex skip | L1 | CLI=codex, model_switch | No error, processing skipped |
| TC-DMR-131 | NFR-03 Copilot skip | L1 | CLI=copilot, model_switch | No error, processing skipped |

### 4.5 NFR-04: Cost Optimization

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-140 | NFR-04 no Opus for L3 | L1 | bloom=3 | Opus is not selected |
| TC-DMR-141 | NFR-04 chatgpt_pro priority | L1 | Multiple models for same bloom | chatgpt_pro group is preferred |
| TC-DMR-142 | NFR-04 suppress unnecessary switch | L1 | current model = recommended model | No switch occurs |

---

## 5. Phase 3 Test Cases — Gunshi Bloom analysis layer

### 5.1 FR-07: gunshi_analysis.yaml schema

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-200 | FR-07 valid YAML | L1 | All fields defined | yaml.safe_load() succeeds, all fields readable |
| TC-DMR-201 | FR-07 #48 fields omitted | L1 | quality_criteria etc. absent | No parse error |
| TC-DMR-202 | FR-07 bloom_level range | L1 | bloom_level=0, 7, etc. | Validation error |
| TC-DMR-203 | FR-07 confidence range | L1 | confidence=-1, 2.0, etc. | Validation error |

### 5.2 FR-08: Gunshi Bloom analysis trigger

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-210 | FR-08 auto → all tasks analyzed | L2 | bloom_routing=auto | Inbox sent to gunshi |
| TC-DMR-211 | FR-08 manual → explicit request only | L2 | bloom_routing=manual | Only tasks with bloom_analysis_required=true |
| TC-DMR-212 | FR-08 off → no analysis | L2 | bloom_routing=off | No inbox sent to gunshi |
| TC-DMR-213 | FR-08 undefined → off | L2 | bloom_routing not set | No inbox sent to gunshi |
| TC-DMR-214 | FR-08 gunshi not running fallback | L2 | Gunshi pane absent | Falls back to Phase 2 behavior |

### 5.3 FR-09: bloom_routing setting

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-220 | FR-09 auto read | L1 | bloom_routing: auto | "auto" |
| TC-DMR-221 | FR-09 manual read | L1 | bloom_routing: manual | "manual" |
| TC-DMR-222 | FR-09 off read | L1 | bloom_routing: off | "off" |
| TC-DMR-223 | FR-09 undefined → off | L1 | bloom_routing not set | "off" |
| TC-DMR-224 | FR-09 invalid value → off | L1 | bloom_routing: invalid | "off" + stderr warning |

---

## 6. Phase 4 Test Cases — Full auto-selection

### 6.1 FR-10: Quality Feedback

| TC ID | Requirement | Level | Aspect | Expected |
|---|---|---|---|---|
| TC-DMR-300 | FR-10 history append | L1 | On task completion | One entry appended to model_performance.yaml |
| TC-DMR-301 | FR-10 history read | L1 | Read last 10 entries | Aggregation by task_type x bloom_level is possible |
| TC-DMR-302 | FR-10 empty file | L1 | model_performance.yaml absent | No error |
| TC-DMR-303 | FR-10 suitability calculation | L1 | pass/fail statistics for same conditions | Pass rate can be calculated |

---

## 7. Unit Test Scope (Phase 1 implementation target)

### 7.1 capability_tier read

- UT-DMR-001: Get max_bloom for defined model
- UT-DMR-002: Get default value (6) for undefined model
- UT-DMR-003: Get default value (6) when section absent
- UT-DMR-004: Get default value (6) when YAML corrupted

### 7.2 Recommended model selection

- UT-DMR-010: L1-L3 → Spark selected
- UT-DMR-011: L4 → Codex 5.3 selected
- UT-DMR-012: L5 → Sonnet Thinking selected
- UT-DMR-013: L6 → Opus Thinking selected
- UT-DMR-014: chatgpt_pro group preferred
- UT-DMR-015: Error handling for out-of-range input
- UT-DMR-016: Idempotency (same result on 2 consecutive calls)

### 7.3 Cost group

- UT-DMR-020: Get cost_group for each model
- UT-DMR-021: Get "unknown" for undefined model

---

## 8. Integration Test Scope (Phase 2 onward, karo-owned)

- IT-DMR-001: model_switch inbox → confirm ashigaru model change
- IT-DMR-002: Ashigaru reassignment on cross-CLI switch
- IT-DMR-003: model_switch skip for Codex/Copilot ashigaru
- IT-DMR-004: Gunshi Bloom analysis → karo model_switch → ashigaru execution coordination
- IT-DMR-005: Gunshi analysis control via bloom_routing flag

---

## 9. E2E Scope (Lord-owned)

- E2E-DMR-001: Full chain completion: Lord → Shogun → Gunshi (Bloom analysis) → Karo (switch) → Ashigaru (execution)
- E2E-DMR-002: When L3 and L5 tasks coexist, they are executed on different models
- E2E-DMR-003: Confirm shutsujin starts normally both before and after adding capability_tiers

---

## 10. Prerequisites (Preflight)

- `bash`, `python3`, `bats` are available
- `.venv/bin/python3` can import PyYAML
- For L2 and above, `tmux` and `inotifywait` are available
- Test settings.yaml can be injected (CLI_ADAPTER_SETTINGS environment variable)

When prerequisites are not met:
- Do not execute the affected tests; record the reason they cannot be met
- SKIP reporting is forbidden (treated as incomplete)

---

## 11. Test Case ID Summary

| Phase | TC ID Range | Count | Level |
|-------|----------|------|--------|
| Phase 1 | TC-DMR-001 to 055 | 23 | L1 |
| Phase 2 | TC-DMR-100 to 142 | 15 | L1/L2 |
| Phase 3 | TC-DMR-200 to 224 | 14 | L1/L2 |
| Phase 4 | TC-DMR-300 to 303 | 4 | L1 |
| **Total** | | **56** | |

---

## 12. FR/NFR Traceability

| Requirement ID | TC ID(s) | Phase |
|--------|----------|-------|
| FR-01 | TC-DMR-001 to 003 | 1 |
| FR-02 | TC-DMR-010 to 017 | 1 |
| FR-03 | TC-DMR-020 to 029 | 1 |
| FR-04 | TC-DMR-030 to 033 | 1 |
| FR-05 | TC-DMR-100 to 103 | 2 |
| FR-06 | TC-DMR-110 to 113 | 2 |
| FR-07 | TC-DMR-200 to 203 | 3 |
| FR-08 | TC-DMR-210 to 214 | 3 |
| FR-09 | TC-DMR-220 to 224 | 3 |
| FR-10 | TC-DMR-300 to 303 | 4 |
| NFR-01 | TC-DMR-040 to 041 | 1 |
| NFR-02 | TC-DMR-120 to 121 | 2 |
| NFR-03 | TC-DMR-130 to 131 | 2 |
| NFR-04 | TC-DMR-140 to 142 | 2 |
| NFR-05 | TC-DMR-050 | 1 |
| NFR-06 | TC-DMR-055 | 1 |

All FR/NFR (16 items) have at least one TC. No gaps.

---

**Test specification complete**: 2026-02-17
**Next action**: Implement Phase 1 bats tests → add FR-01 to FR-04 functions to cli_adapter.sh
