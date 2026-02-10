# Flanders

Review-driven development with parallel agent teams and automated Codex code review.

Decomposes features into waves of parallel tasks, spawns Claude Code agent teams to implement them, then gates each wave with multi-lens code review from Codex (a different model than the one writing the code).

## How It Works

```
/flanders "Add user authentication"

1. Decompose → Wave 1: [JWT, middleware]  Wave 2: [login, tests]
2. Spawn agent team (up to 4 teammates per wave)
3. Teammates implement + commit with task: prefix (no review)
4. Lead commits wave with feat: prefix → triggers Codex review
5. Security lens → PASS, Correctness lens → FAIL
6. Lead assigns fixes to teammates → fix → re-commit → re-review
7. All lenses pass → next wave
8. Done
```

## Prerequisites

- [Claude Code](https://claude.ai/claude-code) with agent teams enabled
- [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`)
- `jq` on PATH

## Install

```bash
/plugin marketplace add spengrah/flanders
/plugin install flanders
```

## Setup

### 1. Enable agent teams

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

### 2. Set Codex credentials

```bash
export CODEX_API_KEY=your-openai-key  # or run: codex login
```

### 3. Configure lint + test commands (optional)

Create `.ai/pre-commit.json` in your project:

```json
{
  "lint": {
    "enabled": true,
    "commands": [
      { "name": "ESLint", "command": "npx eslint ." },
      { "name": "TypeScript", "command": "npx tsc --noEmit" }
    ]
  },
  "test": {
    "enabled": true,
    "commands": [
      { "name": "Unit tests", "command": "npm test" }
    ]
  }
}
```

The `/flanders` init step installs the pre-commit git hook automatically.

## Usage

```
/flanders "Add user authentication with JWT tokens and protected routes"
```

The skill handles everything: decomposition, team creation, implementation, review, fixes, and wave progression.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `FLANDERS_REVIEW_MODEL` | `o3` | Codex model used for review |
| `CODEX_API_KEY` | — | OpenAI API key |

## Review Lenses

Each wave is reviewed through two lenses (V1, hardcoded):

- **Security**: exploits, injection, auth bypass, secrets, race conditions
- **Correctness**: logic errors, off-by-ones, null handling, resource leaks

## Commit Convention

| Prefix | Triggers Review? | Who |
|--------|-----------------|-----|
| `task(scope):` | No (deferred) | Teammates |
| `feat(scope):` | Yes | Lead |
| `fix(scope):` | Yes | Lead |
| Everything else | Yes | Lead |

`task:` commits defer review — the code is reviewed when the lead makes the wave commit (`feat:`), which covers the full accumulated diff.

## Attribution

Inspired by [Dennison Bertram's](https://x.com/DennisonBertram) parallel agent swarm and Ralph Loop pattern for iterative code review with rotating lenses.
