# Flanders

Review-driven development skill for Claude Code. See `README.md` for usage.

## Structure

- `skill/` — The distributable skill (SKILL.md, review-hook.sh, review-schema.json)
- `hooks/` — Git hooks for target projects (pre-commit)
- `.ai/log/plan/` — Runtime plan state (gitignored)
- `.ai/log/review/` — Runtime review state (gitignored)

## Development

This repo IS the skill — `skill/SKILL.md` is what users copy into their projects.
When making changes, test by copying `skill/` into a test project and invoking `/flanders`.

## Rules

- Sign all commits with `-S`
- Use conventional commits
- Keep the skill self-contained — no external dependencies beyond `codex` and `jq`
