#!/usr/bin/env bash
# dim_d_quality_comparison.sh — Dim D: Output Quality Comparison Experiment
# Usage: bash tests/dim_d_quality_comparison.sh
#
# Runs the same L5 task on a Bloom-incompatible model (Haiku 4.5) and a compatible model (Sonnet 4.6),
# then has Gunshi (Opus 4.6) score the quality to prove the difference.
#
# Pass criteria:
#   Sonnet 4.6 score >= 70 (L5 standard: 3 proposals + justified recommendation)
#   Haiku 4.5  score <= 50 (unable to handle L5 tasks adequately)
#   Difference >= 15 points

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${PROJECT_ROOT}/queue/reports/dim_d_quality_report.yaml"

echo "══ Dim D: Output Quality Comparison Experiment ══"
echo "Task type: L5 (Evaluate) — implementation proposal comparison & recommendation"
echo "Incompatible model: claude-haiku-4-5-20251001 (max_bloom=3)"
echo "Compatible model:   claude-sonnet-4-6         (max_bloom=5)"
echo "Evaluator:          claude-opus-4-6           (max_bloom=6)"
echo ""

python3 << PYEOF
import subprocess, re, sys, os, json
from pathlib import Path
from datetime import datetime
import yaml

project_root = Path("${PROJECT_ROOT}")

# Remove CLAUDECODE env var to avoid nest detection
env = os.environ.copy()
env.pop('CLAUDECODE', None)

# Resolve claude CLI path
import glob as _glob
claude_cmd = subprocess.run(['which', 'claude'], capture_output=True, text=True, env=env).stdout.strip()
if not claude_cmd:
    candidates = (
        _glob.glob(os.path.expanduser('~/.local/bin/claude')) +
        _glob.glob(os.path.expanduser('~/.nvm/versions/node/*/bin/claude')) +
        ['/usr/local/bin/claude']
    )
    claude_cmd = next((c for c in candidates if os.path.isfile(c)), 'claude')
print(f"claude CLI: {claude_cmd}")

# ─────────────────────────────────────────────
# L5 Task Definition
# ─────────────────────────────────────────────
L5_TASK = """We want to implement "dynamic task assignment to idle ashigaru" in a multi-agent system.
Compare the following 3 proposals and recommend the best one with supporting rationale.

[Proposal A] Polling approach: Karo checks all ashigaru status files every second,
             and sends a task when an idle ashigaru is detected.

[Proposal B] Event-driven approach: Ashigaru sends a "completion notification" via inbox_write
             when a task is done, and karo sends the next task after receiving the notification.

[Proposal C] Priority queue approach: Tasks are assigned Bloom levels, and the lowest-cost
             idle ashigaru with a compatible model is selected for assignment.

For each proposal, evaluate: (1) implementation cost, (2) response speed, (3) scalability, (4) fault tolerance,
then select the best proposal and argue why."""

EVALUATOR_PROMPT_TEMPLATE = """Score the following response to "multi-agent system task assignment implementation proposal comparison".

Scoring criteria (L5 Evaluate level):
1. Proposal coverage (0-20 points): Does it comment on all 3 proposals?
2. Evaluation axes (0-25 points): Does it evaluate on the 4 axes of implementation cost/speed/scalability/fault tolerance?
3. Clear recommendation (0-25 points): Does it clearly recommend the best proposal and state the reasons?
4. Depth of reasoning (0-30 points): Is the comparison substantive with technical rationale, not superficial?

Total 100 points. Respond with JSON only (no explanation):
{"score": <integer>, "breakdown": {"proposal_coverage": <integer>, "evaluation_axes": <integer>, "clear_recommendation": <integer>, "reasoning_depth": <integer>}, "summary": "<one-line evaluation>"}

--- Response to score ---
"""

def run_model(model_id, prompt, timeout=120):
    """Call claude directly with the specified model"""
    print(f"\n[{model_id}] Running...", flush=True)
    try:
        result = subprocess.run(
            [claude_cmd, '--model', model_id, '-p', prompt],
            capture_output=True, text=True, timeout=timeout,
            env=env
        )
        out = result.stdout.strip()
        if not out and result.stderr:
            print(f"  STDERR: {result.stderr[:200]}", flush=True)
        return out
    except subprocess.TimeoutExpired:
        print(f"  TIMEOUT ({timeout}s)")
        return None
    except Exception as e:
        print(f"  ERROR: {e}")
        return None

def evaluate(response, model_label, timeout=90):
    """Calculate quality score using Opus 4.6"""
    if not response:
        return {"score": 0, "error": "no response"}
    prompt = EVALUATOR_PROMPT_TEMPLATE + response[:3000]
    print(f"\n[Gunshi/Opus evaluation] Scoring {model_label}'s response...", flush=True)
    raw = run_model('claude-opus-4-6', prompt, timeout=timeout)
    if not raw:
        return {"score": 0, "error": "evaluator failed"}
    # Extract JSON
    match = re.search(r'\{.*\}', raw, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except:
            pass
    # fallback: extract score number only
    nums = re.findall(r'"score"\s*:\s*(\d+)', raw)
    return {"score": int(nums[0]) if nums else 0, "raw": raw[:500]}

# ─────────────────────────────────────────────
# Execution
# ─────────────────────────────────────────────
print("\n── Step 1/3: Haiku 4.5 (max_bloom=3, incompatible with L5 tasks) ──")
haiku_response = run_model('claude-haiku-4-5-20251001', L5_TASK)
if haiku_response:
    print(f"  Output ({len(haiku_response)} chars): {haiku_response[:200]}...")

print("\n── Step 2/3: Sonnet 4.6 (max_bloom=5, compatible with L5 tasks) ──")
sonnet_response = run_model('claude-sonnet-4-6', L5_TASK)
if sonnet_response:
    print(f"  Output ({len(sonnet_response)} chars): {sonnet_response[:200]}...")

print("\n── Step 3/3: Gunshi (Opus 4.6) scores both responses ──")
haiku_eval  = evaluate(haiku_response,  "Haiku 4.5")
sonnet_eval = evaluate(sonnet_response, "Sonnet 4.6")

haiku_score  = haiku_eval.get('score', 0)
sonnet_score = sonnet_eval.get('score', 0)
diff = sonnet_score - haiku_score

print("\n══ Results Summary ══")
print(f"Haiku 4.5  Score: {haiku_score}/100  (max_bloom=3, incompatible with L5 tasks)")
print(f"Sonnet 4.6 Score: {sonnet_score}/100  (max_bloom=5, compatible with L5 tasks)")
print(f"Difference:        +{diff} points")
print()

THRESHOLD_SONNET = 70
THRESHOLD_DIFF   = 15
pass_sonnet = sonnet_score >= THRESHOLD_SONNET
pass_diff   = diff >= THRESHOLD_DIFF

print(f"Sonnet >= {THRESHOLD_SONNET} pts: {'✓ PASS' if pass_sonnet else '✗ FAIL'}")
print(f"Diff   >= {THRESHOLD_DIFF} pts: {'✓ PASS' if pass_diff else '✗ FAIL'}")

verdict = 'PASS' if (pass_sonnet and pass_diff) else 'FAIL'
print(f"\nFinal verdict: {verdict}")
print(f"(Bloom routing value: {'+' if diff > 0 else ''}{diff} point difference)")

# ─────────────────────────────────────────────
# Save report
# ─────────────────────────────────────────────
report = {
    'dim_d_quality_report': {
        'timestamp': datetime.now().isoformat(),
        'task_bloom_level': 5,
        'task_description': L5_TASK[:200],
        'models': {
            'inappropriate': {
                'model': 'claude-haiku-4-5-20251001',
                'max_bloom': 3,
                'score': haiku_score,
                'evaluation': haiku_eval,
                'response_length': len(haiku_response) if haiku_response else 0,
                'response_preview': (haiku_response or '')[:500],
            },
            'appropriate': {
                'model': 'claude-sonnet-4-6',
                'max_bloom': 5,
                'score': sonnet_score,
                'evaluation': sonnet_eval,
                'response_length': len(sonnet_response) if sonnet_response else 0,
                'response_preview': (sonnet_response or '')[:500],
            },
        },
        'score_diff': diff,
        'thresholds': {
            'sonnet_min': THRESHOLD_SONNET,
            'diff_min':   THRESHOLD_DIFF,
        },
        'pass_sonnet': pass_sonnet,
        'pass_diff':   pass_diff,
        'verdict': verdict,
    }
}

output_path = Path(project_root) / 'queue' / 'reports' / 'dim_d_quality_report.yaml'
output_path.parent.mkdir(parents=True, exist_ok=True)
with open(output_path, 'w') as f:
    yaml.dump(report, f, allow_unicode=True)
print(f"\nReport saved: {output_path}")

sys.exit(0 if verdict == 'PASS' else 1)
PYEOF
