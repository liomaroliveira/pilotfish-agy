# Attribution & Provenance

`pilotfish-agy` is an adapted port for **Google Antigravity (AGY)** derived from
[Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish) release `v1.5.0`
(MIT License).

## Upstream Lineage

- **Upstream project:** `Nanako0129/pilotfish` (`v1.5.0`)
- **Upstream license:** MIT License — Copyright (c) 2026 Nanako0129
- **Interaction shape design credit:** Adapted upstream from
  `miyago9267/pilotfish-codex` PR #14 (`co_discover` / `explore_then_plan` / `execute`).

## Key Adaptations for Antigravity

| Upstream (Claude Code) | Antigravity Port (`pilotfish-agy`) |
| --- | --- |
| `SessionStart` hook (`emit-sessionstart.sh` + `hooks.json`) | Native `rules/AGENTS.md` (always-on while plugin is enabled) + on-demand `skills/pilotfish/SKILL.md` |
| `pilotfish:<role>` namespace | Explicit `pf-<role>` subagent names (`pf-scout`, `pf-plan-verifier`, `pf-security-reviewer`, `pf-mech-executor`, `pf-executor`, `pf-verifier`, `pf-security-executor`) |
| Agent frontmatter `model: haiku / sonnet / opus` + `effort` | Explicit `invoke_subagent(..., Model="flash_lite" \| "flash" \| "pro")` tier policy in `rules/AGENTS.md` |
| Claude Code tool allowlists (`Read, Glob, Grep, Edit, Write, Bash, WebSearch`) | Native Antigravity tool allowlists (`read_file`, `edit_file`, `write_file`, `run_command`, `manage_task`, `search_web`) with leaf and read-only capability boundaries preserved |
| `isolation: "worktree"` | `invoke_subagent(..., Workspace="share")` for parallel writers in Git repositories |
| `AskUserQuestion` | `ask_question` |
