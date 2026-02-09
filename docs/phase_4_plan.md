# Phase 4 Implementation Plan: Review & Diff Helpers

## Context

Phases 1–3 delivered terminal lifecycle, context transfer, and session/model controls.
Phase 4 adds the final two Codex CLI slash command wrappers: `/review` and `/diff`.

**User decision:** Skip git rollback helpers — users can use standard git commands.

---

## Codex CLI Slash Command Reference

| CLI Command | Behavior | Interactive? | Inline args? |
|---|---|---|---|
| `/review` | AI code review with 4-option picker | Yes | Yes — `/review <instructions>` bypasses picker |
| `/diff` | Show `git diff` including untracked files | No | No |

### `/review` details

When invoked with no args, opens a selection popup with four presets:
1. "Review against a base branch" (PR-style) — picks branch, diffs merge base
2. "Review uncommitted changes" — staged + unstaged + untracked
3. "Review a commit" — picks from recent 100 commits
4. "Custom review instructions" — free-form text input

When invoked with inline args (`/review focus on security`), bypasses the popup
entirely and submits a custom review directly.

### `/diff` details

Runs `git diff --color` for tracked changes plus `git diff --no-index` for each
untracked file. Output rendered in the TUI. No arguments, no interaction.

---

## Architecture

Both commands build on the existing `M.send_command(slash_cmd)` primitive from
Phase 3. The key insight is that `send_command` already handles compound strings
correctly — `send_command("review focus on security")` sends `/review focus on
security\n`, which is exactly what the CLI expects.

### `M.review(instructions)`

```
review(instructions):
  1. if instructions is nil or empty → send_command("review")
  2. else → send_command("review " .. instructions)
```

This is the only Phase 4 function with argument handling. The rest are
single-line `send_command` wrappers.

### `M.show_diff()`

```
show_diff():
  return send_command("diff")
```

Same pattern as `M.show_status()` / `M.compact()` from Phase 3.

### Named API Functions

- `M.review(instructions)` — sends `/review` or `/review <instructions>` (public)
- `M.show_diff()` → `send_command("diff")` (public)

---

## Modified Files

### `lua/codex/init.lua`

1. Add `M.review(instructions)` — conditional argument forwarding.
2. Add `M.show_diff()` — thin wrapper over `send_command("diff")`.

### `lua/codex/nvim/commands.lua`

Add 2 new command registrations:

| Command | nargs | Dispatches to |
|---|---|---|
| `:CodexReview [instructions]` | `*` | `codex.review(args)` — passes `nil` when args is empty |
| `:CodexDiff` | `0` | `codex.show_diff()` |

### `tests/unit/init_spec.lua`

New test cases (~5):
- `review` with no args sends `/review\n`
- `review` with instructions sends `/review <instructions>\n`
- `review` auto-opens with focus when no session (inherits from `send_command`)
- `review` with empty string sends `/review\n` (treated same as nil)
- `show_diff` sends `/diff\n`

### `tests/unit/commands_spec.lua`

New test cases (~4):
- Registration check includes `CodexReview` and `CodexDiff` with correct opts
- `:CodexReview` with no args dispatches `review(nil)`
- `:CodexReview focus on security` dispatches `review("focus on security")`
- `:CodexDiff` dispatches `show_diff()`

### `README.md`

Add Phase 4 commands and Lua API.

---

## Commit Sequence

### Commit 1: `feat(core): add review and diff slash command wrappers`
- Add `M.review(instructions)` and `M.show_diff()` in `lua/codex/init.lua`
- Add ~5 tests in `tests/unit/init_spec.lua`

### Commit 2: `feat(commands): register CodexReview and CodexDiff commands`
- Add 2 commands in `lua/codex/nvim/commands.lua`
- Add ~4 tests in `tests/unit/commands_spec.lua`

### Commit 3: `docs(readme): document review and diff commands`
- Update `README.md` with new commands and API functions

---

## Verification

```sh
mise exec -- just test          # all tests pass (existing + new)
mise exec -- just fmt-check     # formatting clean
mise exec -- just lint          # linting clean
```
