---
name: flanders
description: |
  Review-driven development with parallel agent teams and iterative Codex review.
  Decomposes features into serial waves, spawns agent teams for parallel implementation,
  gates each wave with automated multi-lens code review via a different model.
  Use when: /flanders, large features, structured parallel development with review gates.
allowed-tools: Bash Read Edit Write Glob Grep Task TaskCreate TaskUpdate TaskList TaskGet AskUserQuestion
hooks:
  PostToolUse:
    - matcher: "Bash(git commit*)"
      hooks:
        - type: command
          command: ".ai/skills/flanders/review-hook.sh"
          timeout: 300
---

# Flanders: Review-Driven Development

Orchestrate feature implementation through parallel agent teams with automated code review gates. Each wave of work is reviewed by an external model (Codex) before the next wave begins.

## Prerequisites

- `codex` CLI installed (`npm install -g @openai/codex`)
- `CODEX_API_KEY` set (or logged in via `codex login`)
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable set
- `jq` available on PATH
- `.ai/pre-push.json` configured with lint/test commands (for pre-commit gating)

## Arguments

- First argument: feature description (required)

## 1. Initialize

```bash
mkdir -p .ai/log/plan .ai/log/review
```

Set baseline for review diff if not already set:

```bash
if [ ! -f .ai/log/review/last-approved ]; then
  git rev-parse HEAD > .ai/log/review/last-approved
fi
```

Verify agent teams are enabled:

```bash
if [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
  echo "Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 to enable agent teams"
fi
```

## 2. Decompose

Analyze the feature description. Break it into **waves** of **tasks**.

Rules:
- Each wave contains tasks that can execute in parallel (no dependencies within a wave)
- Waves execute serially (wave N+1 depends on wave N completing)
- Maximum 4 tasks per wave
- Each task should touch distinct files to avoid merge conflicts
- Earlier waves build foundations that later waves depend on

Write the plan:

```
.ai/log/plan/flanders-plan.md    — human-readable decomposition
.ai/log/plan/flanders-state.json — machine-readable progress tracker
```

State file format:
```json
{
  "feature": "feature description",
  "currentWave": 1,
  "totalWaves": 3,
  "waves": [
    {
      "id": 1,
      "status": "pending",
      "tasks": [
        { "name": "JWT token generation", "scope": "auth", "status": "pending" },
        { "name": "Auth middleware", "scope": "auth", "status": "pending" }
      ]
    }
  ]
}
```

Also create tasks via TaskCreate for in-session tracking.

## 3. Execute Waves

For each wave:

### 3a. Create Team

Create an agent team with one teammate per task in the wave. Give each teammate clear instructions:

- What to implement
- What files to work in (to avoid conflicts)
- Commit with `task(scope): description` prefix when done
- The `task:` prefix is critical — it prevents premature review triggers

### 3b. Wait for Completion

Wait for all teammates to finish and go idle. Their `task:` commits are saved to git history but do NOT trigger review.

### 3c. Commit Wave

After all teammates complete, create a wave summary commit:

```bash
git add -A
git commit -S -m "feat(scope): wave description"
```

This non-`task:` commit triggers the PostToolUse review hook automatically. The review covers the FULL diff since the last approval — including all `task:` code.

### 3d. Handle Review Results

The review hook will either:

**PASS (exit 0):** Wave approved. Update `flanders-state.json`, shut down teammates, proceed to next wave.

**FAIL (exit 2):** Findings are injected into your context. You must:

1. Read the findings carefully
2. Assign fix tasks to the relevant teammate(s)
3. Teammates fix and commit with `task:` prefix
4. You commit the fix: `fix(scope): address review findings`
5. This triggers another review cycle
6. Repeat until review passes

### 3e. Update State

After wave approval:

```json
{
  "currentWave": 2,
  "waves": [
    { "id": 1, "status": "approved", "tasks": [...] },
    { "id": 2, "status": "in_progress", "tasks": [...] }
  ]
}
```

Shut down teammates from the completed wave. Create a new team for the next wave.

## 4. Finalize

After all waves complete and pass review:

1. Clean up the agent team (shut down all teammates, then clean up team resources)
2. Remove state files:
   ```bash
   rm -f .ai/log/plan/flanders-plan.md .ai/log/plan/flanders-state.json
   ```
3. Summarize: what was built, how many review iterations, notable findings addressed
4. Update MEMORY.md with any learnings from the session

## 5. Recovery

If your context was compressed or you're unsure of current state:

1. Read `.ai/log/plan/flanders-plan.md` for the full decomposition
2. Read `.ai/log/plan/flanders-state.json` for current progress
3. Check `TaskList` for task status
4. Check `.ai/log/review/last-approved` for the last approved commit
5. Run `git log --oneline` to see recent commits and where you are
6. Teammates persist independently — message them to check their status

Resume from where the state files indicate.

## Commit Convention

| Prefix | Purpose | Triggers Review? |
|--------|---------|-----------------|
| `task(scope):` | Teammate checkpoint | No (deferred) |
| `feat(scope):` | Wave completion | Yes |
| `fix(scope):` | Review findings fix | Yes |
| `refactor:` | Any refactoring | Yes |
| `test:` | Test additions | Yes |
| `chore:` | Maintenance | Yes |

Only `task:` skips review. Everything else is reviewed.

## Anti-Patterns

- **Don't skip review** — every non-task commit must pass review before proceeding
- **Don't exceed 4 tasks per wave** — more causes merge conflicts and coordination overhead
- **Don't create dependencies within a wave** — those belong in separate sequential waves
- **Don't amend commits** — create new `fix:` commits so the review loop has clean diffs
- **Don't shut down teammates before review passes** — you may need them to fix findings
- **Don't ignore review findings** — address every finding before re-committing

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `FLANDERS_REVIEW_MODEL` | `o3` | Codex model for review |
| `CODEX_API_KEY` | — | OpenAI API key for Codex |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | — | Must be `1` to enable teams |
