# Phase 2 Implementation Plan: Context Transfer

## Context

Phase 1 (complete) delivered: setup API, terminal providers, `:Codex`/`:CodexFocus`
commands, session lifecycle, and DI seam. Phase 2 adds context transfer — sending
editor selections and file references into the active Codex CLI terminal session.

**User decisions:**
- `:CodexSend` wraps selection with file path, line range, and language fence.
- `:CodexAdd` is path-only and uses the Codex CLI `/mention filepath` slash command.
- `:CodexTreeAdd` is a generic `codex.add_file(path)` Lua API only (no built-in explorer adapters).

---

## New Files

### `lua/codex/context/formatter.lua` — Pure data-to-string transformer

Zero vim dependency. Two functions:

- `format_selection(spec)` — takes `{ filepath, start_line, end_line, filetype, lines }`, returns:
  ```
  # Selection from {filepath} (lines {start}-{end})

  ```{filetype}
  {lines}
  ```
  ```
- `format_mention(filepath)` — returns `"/mention {filepath}\n"`

### `lua/codex/context/selection.lua` — Vim-aware selection extraction

Receives `vim_api` parameter (injectable for tests).

- `get_visual_selection(vim_api)` — reads `'<`/`'>` marks, buffer lines, filepath, filetype. Returns spec table or `nil, err`.

---

## Modified Files

### `lua/codex/init.lua`

Extend `default_deps` with `formatter`, `selection`. Add two public functions:

- `M.send_selection()` — extracts selection via `deps.selection`, formats via `deps.formatter`, sends via `M.send()`.
- `M.add_file(path)` — formats `/mention path` via `deps.formatter`, sends.
- `M.add_file(nil)` resolves path from current buffer via `vim.fn.expand("%:p")`.

### `lua/codex/nvim/commands.lua`

Add inside `M.register()`:

| Command | nargs | range | complete | Dispatches to |
|---------|-------|-------|----------|---------------|
| `:CodexSend` | 0 | true | — | `codex.send_selection()` |
| `:CodexAdd [path]` | `"?"` | false | `"file"` | `codex.add_file(args or current buffer)` |

### `justfile`

Add `formatter_spec.lua` and `selection_spec.lua` to `test-unit`.

### `README.md`

Document new commands and `codex.add_file(path)` Lua API.

---

## Commit Sequence

### Commit 1: `feat(context): add pure selection formatter module`
- Create `lua/codex/context/formatter.lua`
- Create `tests/unit/formatter_spec.lua`
- Update `justfile`

### Commit 2: `feat(context): add visual selection extraction module`
- Create `lua/codex/context/selection.lua`
- Create `tests/unit/selection_spec.lua`
- Update `justfile`

### Commit 3: `feat(core): add send_selection and add_file public API`
- Modify `lua/codex/init.lua` (DI wiring + 2 new public functions)
- Update `tests/unit/init_spec.lua` (8 new tests)

### Commit 4: `feat(commands): register CodexSend and CodexAdd user commands`
- Modify `lua/codex/nvim/commands.lua`
- Update `tests/unit/commands_spec.lua` (5 new tests)

### Commit 5: `docs: update README with Phase 2 commands and Lua API`
- Modify `README.md`

---

## Test Cases

**formatter_spec.lua** (8 tests): multi-line selection, single-line, empty filetype,
empty filepath, backticks in content, mention format, mention with spaces, trailing
newline.

**selection_spec.lua** (6 tests): multi-line extraction, single-line, invalid marks,
filetype, expanded path, unnamed buffer.

**init_spec.lua additions** (8 tests): send_selection happy path, selection error,
auto-open, add_file happy path, add_file nil-path uses current buffer, add_file empty path error,
send_selection preserves filepath and line range in payload.

**commands_spec.lua additions** (5 tests): CodexSend registration, CodexSend dispatch,
CodexAdd registration, CodexAdd no args, CodexAdd with args.

---

## Public API After Phase 2

```lua
-- Existing (Phase 1):
M.setup(opts)
M.open(focus)
M.close()
M.toggle()
M.focus()
M.send(text)
M.is_running()
M.get_config()

-- New (Phase 2):
M.send_selection()           -- reads visual marks, formats, sends
M.add_file(path)             -- sends /mention path to terminal
```

---

## Verification

```sh
mise exec -- just test          # all tests pass (existing + new)
mise exec -- just fmt-check     # formatting clean
mise exec -- just lint          # linting clean
```
