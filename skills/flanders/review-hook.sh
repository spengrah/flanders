#!/bin/bash
# PostToolUse hook: automated code review via Codex
#
# Fires after git commit (skill-scoped, only active during /flanders).
# Skips review for task: prefix commits (deferred to wave commit).
# Runs Codex review for each lens against accumulated diff since last approval.
#
# Exit codes:
#   0 = review passed (or skipped for task: commits)
#   2 = review failed, stderr contains findings for Claude

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$PROJECT_ROOT"

# --- Check commit message prefix ---

COMMIT_MSG=$(git log -1 --pretty=%s HEAD 2>/dev/null || echo "")
if [[ -z "$COMMIT_MSG" ]]; then
  exit 0
fi

if [[ "$COMMIT_MSG" == task* ]]; then
  exit 0
fi

# --- Determine diff scope ---

REVIEWS_DIR=".ai/log/review"
mkdir -p "$REVIEWS_DIR"
LAST_APPROVED_FILE="$REVIEWS_DIR/last-approved"

if [[ -f "$LAST_APPROVED_FILE" ]]; then
  LAST_APPROVED=$(cat "$LAST_APPROVED_FILE")
  if ! git rev-parse --verify "$LAST_APPROVED" >/dev/null 2>&1; then
    LAST_APPROVED=""
  fi
fi

if [[ -z "${LAST_APPROVED:-}" ]]; then
  LAST_APPROVED=$(git merge-base HEAD main 2>/dev/null || git rev-list --max-parents=0 HEAD 2>/dev/null || echo "")
fi

if [[ -z "$LAST_APPROVED" ]]; then
  echo "[flanders] Could not determine baseline commit, skipping review." >&2
  exit 0
fi

HEAD_SHA=$(git rev-parse HEAD)

# Check if there's a diff to review
if git diff --quiet "$LAST_APPROVED" HEAD 2>/dev/null; then
  exit 0
fi

# --- Check for codex ---

if ! command -v codex &>/dev/null; then
  echo "[flanders] codex CLI not found. Install: npm install -g @openai/codex" >&2
  echo "[flanders] Skipping review." >&2
  exit 0
fi

# --- Configuration ---

REVIEW_MODEL="${FLANDERS_REVIEW_MODEL:-o3}"
SCHEMA_FILE="$SCRIPT_DIR/review-schema.json"

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "[flanders] review-schema.json not found at $SCHEMA_FILE" >&2
  exit 0
fi

# --- Lens definitions ---

declare -a LENS_NAMES=("security" "correctness")

declare -A LENS_PROMPTS
LENS_PROMPTS[security]="You are a security reviewer. Find exploits, injection vectors, authentication bypass, secrets exposure, race conditions, unsafe deserialization, path traversal, and privilege escalation vulnerabilities."
LENS_PROMPTS[correctness]="You are a correctness reviewer. Find logic errors, off-by-one mistakes, null/undefined handling issues, race conditions, resource leaks, error handling gaps, and broken invariants."

# --- Run reviews ---

OVERALL_RESULT="PASS"
ALL_FINDINGS=""
TEMP_OUT=$(mktemp)
trap "rm -f '$TEMP_OUT'" EXIT

for LENS in "${LENS_NAMES[@]}"; do
  LENS_PROMPT="${LENS_PROMPTS[$LENS]}"

  echo "[flanders] Running $LENS review ($LAST_APPROVED..HEAD)..." >&2

  REVIEW_PROMPT="You are reviewing code changes in $PROJECT_ROOT.
The diff since last approval covers commits ${LAST_APPROVED:0:8}..${HEAD_SHA:0:8}.
Run 'git diff $LAST_APPROVED $HEAD_SHA' to see the full changes.
You can also read any files in the project for context.

$LENS_PROMPT

Review the changes and respond with structured JSON per the output schema.
Set result to PASS if no issues found, FAIL if any issues found.
Only report genuine issues — no style nits or suggestions for improvement."

  CODEX_EXIT=0
  codex exec \
    --model "$REVIEW_MODEL" \
    --full-auto \
    --ephemeral \
    --skip-git-repo-check \
    -o "$TEMP_OUT" \
    "$REVIEW_PROMPT" 2>/dev/null || CODEX_EXIT=$?

  if [[ $CODEX_EXIT -ne 0 ]] || [[ ! -s "$TEMP_OUT" ]]; then
    echo "[flanders] $LENS review: codex failed (exit $CODEX_EXIT), treating as FAIL" >&2
    OVERALL_RESULT="FAIL"
    ALL_FINDINGS="${ALL_FINDINGS}\n\n=== $LENS review: ERROR ===\nCodex exited with code $CODEX_EXIT. Review manually."
    continue
  fi

  REVIEW_OUTPUT=$(cat "$TEMP_OUT")

  # Parse result
  RESULT=$(echo "$REVIEW_OUTPUT" | jq -r '.result // "FAIL"' 2>/dev/null || echo "FAIL")

  if [[ "$RESULT" == "FAIL" ]]; then
    OVERALL_RESULT="FAIL"
    SUMMARY=$(echo "$REVIEW_OUTPUT" | jq -r '.summary // "No summary"' 2>/dev/null || echo "Parse error")
    FINDINGS=$(echo "$REVIEW_OUTPUT" | jq -r '.findings[]? | "  [\(.severity)] \(.file):\(.line // "?") — \(.issue)\n    Fix: \(.suggestion // "none")"' 2>/dev/null || echo "  Could not parse findings")
    ALL_FINDINGS="${ALL_FINDINGS}\n\n=== $LENS review: FAIL ===\n$SUMMARY\n$FINDINGS"
    # Stop on first failure — no point running more lenses
    break
  else
    echo "[flanders] $LENS review: PASS" >&2
  fi
done

# --- Write review result ---

REVIEW_RESULT="{\"sha\": \"$HEAD_SHA\", \"result\": \"$OVERALL_RESULT\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
echo "$REVIEW_RESULT" > "$REVIEWS_DIR/${HEAD_SHA:0:8}.json"

# --- Report ---

if [[ "$OVERALL_RESULT" == "FAIL" ]]; then
  cat >&2 << EOF

==============================================================
            FLANDERS: CODE REVIEW FAILED
==============================================================
Reviewing diff: ${LAST_APPROVED:0:8}..${HEAD_SHA:0:8}
$(echo -e "$ALL_FINDINGS")

Fix the findings above and commit again to re-trigger review.
==============================================================
EOF
  exit 2
fi

# All passed — update last-approved
echo "$HEAD_SHA" > "$LAST_APPROVED_FILE"
echo "[flanders] All reviews passed. Approved: ${HEAD_SHA:0:8}" >&2
exit 0
