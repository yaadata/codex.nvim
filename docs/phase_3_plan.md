# Phase 3 Implementation Plan: Session & Model Controls

## Context

Phase 1 delivered terminal lifecycle, provider abstraction, and `:Codex`/`:CodexFocus`.
Phase 2 delivered context transfer with `:CodexSend` and `:CodexAdd`. Phase 3 adds
session management and model controls — wrapping Codex CLI slash commands that users
commonly invoke from normal mode via keybindings.

**Pre-requisite:** Fix the snacks provider `on_exit` callback gap identified in the
Phase 2 post-review (sessions opened via snacks never mark dead on terminal exit).

**User decisions:**
- Scope: Resume, Model, Status, Permissions, Compact (5 commands).
- Fix snacks `on_exit` as a prerequisite commit before Phase 3 features.

---

## Codex CLI Slash Command Reference

| CLI Command | Behavior | Interactive? |
|---|---|---|
| `/model` | Picker to switch active model | Yes |
| `/resume` | Picker to reload previous conversation | Yes |
| `/status` | Show model, approval policy, token usage | No |
| `/permissions` | Selector to change approval preset | Yes |
| `/compact` | Summarize earlier turns to save tokens | Yes (confirm) |

CLI launch: `codex resume [session_id]` opens directly in resume mode.
Flags: `--last` (most recent session), `--all` (any directory).

---

## Architecture

### Core Primitive: `send_command(slash_cmd)`

A new internal function in `init.lua` that differs from `M.send()` in two ways:
1. Auto-opens **with focus** (not background like `send()`), since the user needs
   to see/interact with the CLI's response.
2. Focuses existing session before sending.

```
send_command(slash_cmd):
  1. ensure_setup()
  2. if no alive session → M.open(true)     # open + focus
     else → provider.focus(session.handle)   # focus existing
  3. provider.send(handle, "/" .. slash_cmd .. "\n")
```

### Resume: Dual-Mode Behavior

`:CodexResume` has context-dependent behavior:
- **Active session exists:** Focus terminal, send `/resume\n` — uses the CLI's
  interactive session picker within the current process.
- **No active session:** Close stale session if any, then launch
  `codex resume [--last]` — starts a new CLI process directly in resume mode.

This requires an internal `open_session(args, focus)` helper extracted from
`M.open()` so resume can pass different launch args (`{"resume"}` or
`{"resume", "--last"}`).

### Named API Functions

Thin wrappers over `send_command` for discoverability and documentation:
- `M.send_command(slash_cmd)` — generic primitive (public)
- `M.resume(opts)` — special dual-mode logic (public)
- `M.set_model()` → `send_command("model")` (public)
- `M.show_status()` → `send_command("status")` (public)
- `M.show_permissions()` → `send_command("permissions")` (public)
- `M.compact()` → `send_command("compact")` (public)

---

## Pre-Requisite: Snacks `on_exit` Fix

**File:** `lua/codex/providers/snacks.lua`

The `open()` function accepts `_on_exit` but ignores it. Sessions opened via snacks
never auto-mark dead when the terminal exits.

**Fix:** After `snacks.terminal(opts)` creates the terminal, set up a `TermClose`
autocmd on the terminal's buffer to call `on_exit(handle)` when the job exits:

```lua
function M.open(cmd, args, env, config, focus, on_exit)
  -- ... existing terminal creation ...
  local handle = { terminal = terminal, provider = "snacks" }

  if on_exit and terminal.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = terminal.buf,
      once = true,
      callback = function()
        on_exit(handle)
      end,
    })
  end

  return handle
end
```

**Test:** Update `tests/contract/provider_contract_spec.lua` if the snacks contract
test can exercise the callback (may need to skip if snacks is not available in CI).

---

## Modified Files

### `lua/codex/providers/snacks.lua`
- Wire `on_exit` callback via `TermClose` autocmd on the terminal buffer.

### `lua/codex/init.lua`

1. Extract `open_session(args, focus)` from `M.open()` — internal helper that
   accepts arbitrary args (instead of reading from `state.config.args`).
2. Refactor `M.open(focus)` to delegate to `open_session(state.config.args, focus)`.
3. Refactor `M.toggle()` to also use `open_session` for its "no active session" path.
4. Add `M.send_command(slash_cmd)` — focus-aware slash command dispatcher.
5. Add `M.resume(opts)` — dual-mode resume.
6. Add `M.set_model()`, `M.show_status()`, `M.show_permissions()`, `M.compact()`.

### `lua/codex/nvim/commands.lua`

Add 5 new command registrations:

| Command | nargs | bang | Dispatches to |
|---|---|---|---|
| `:CodexResume[!]` | 0 | yes | `codex.resume({ last = bang })` |
| `:CodexModel` | 0 | no | `codex.set_model()` |
| `:CodexStatus` | 0 | no | `codex.show_status()` |
| `:CodexPermissions` | 0 | no | `codex.show_permissions()` |
| `:CodexCompact` | 0 | no | `codex.compact()` |

### `tests/unit/init_spec.lua`

New test cases (~12):
- `send_command` auto-opens with focus when no session
- `send_command` focuses existing session and sends slash text
- `send_command` logs error on send failure
- `resume` sends `/resume` to active session and focuses
- `resume` opens `codex resume` when no session
- `resume({ last = true })` opens `codex resume --last` when no session
- `resume` closes stale session before opening resume
- `set_model` sends `/model\n`
- `show_status` sends `/status\n`
- `show_permissions` sends `/permissions\n`
- `compact` sends `/compact\n`
- `open_session` refactor: existing open/toggle tests still pass

### `tests/unit/commands_spec.lua`

New test cases (~7):
- Registration check includes all 5 new commands with correct opts
- `:CodexResume` dispatches `resume()` with `{ last = false }`
- `:CodexResume!` dispatches `resume()` with `{ last = true }`
- `:CodexModel` dispatches `set_model()`
- `:CodexStatus` dispatches `show_status()`
- `:CodexPermissions` dispatches `show_permissions()`
- `:CodexCompact` dispatches `compact()`

### `README.md`

Add Phase 3 commands and Lua API.

---

## Commit Sequence

### Commit 0 (`ed2df91`): `fix(snacks): wire on_exit callback to terminal lifecycle`
- Modify `lua/codex/providers/snacks.lua` — wire `on_exit` via `TermClose` autocmd
- Update Phase 2 post-review doc to mark correction as complete

### Commit 1 (`7066ce7`): `feat(core): add slash command dispatch primitives`
- Extract `open_session(args, focus)` helper from `M.open()`
- Add `M.send_command(slash_cmd)`
- Add `M.set_model()`, `M.show_status()`, `M.show_permissions()`, `M.compact()`
- Add ~8 tests in `tests/unit/init_spec.lua`

### Commit 2 (`a2ae837`): `feat(core): add resume api with dual-mode behavior`
- Add `M.resume(opts)` with dual-mode behavior
- Add ~4 tests in `tests/unit/init_spec.lua`

### Commit 3 (`ab5bf32`): `feat(commands): register phase 3 codex commands`
- Add 5 commands in `lua/codex/nvim/commands.lua`
- Add ~7 tests in `tests/unit/commands_spec.lua`

### Commit 4 (`43da6a1`): `docs(readme): document phase 3 resume and slash commands`
- Update `README.md` with new commands and API functions

---

## Verification

```sh
mise exec -- just test          # all tests pass (existing + new)
mise exec -- just fmt-check     # formatting clean
mise exec -- just lint          # linting clean
```
