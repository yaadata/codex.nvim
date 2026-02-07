# Phase 1 Implementation Plan: Core Terminal + Commands

## Context

`codex.nvim` is a greenfield Neovim plugin that wraps the OpenAI Codex CLI
(`codex`) in a terminal session with provider abstraction, configurable defaults,
and user commands. The repo currently contains only a design document
(`docs/claude-code-comparison.md`). This plan implements Phase 1: setup API,
terminal providers, and the `:Codex` / `:CodexFocus` commands.

**Decisions:** default command is `codex`, minimum Neovim 0.10.0, tests included.

---

## Files to Create

```
plugin/codex.lua                          -- entry point / load guard
lua/codex/init.lua                        -- setup() and public API
lua/codex/config.lua                      -- defaults, validation, merge
lua/codex/providers/init.lua              -- provider registry + auto-select
lua/codex/providers/native.lua            -- native vim.fn.termopen provider
lua/codex/providers/snacks.lua            -- snacks.nvim terminal provider
lua/codex/providers/external.lua          -- external terminal provider (stub)
lua/codex/providers/none.lua              -- no-op provider
lua/codex/state/session_store.lua         -- session tracking
lua/codex/nvim/commands.lua               -- user command registration
lua/codex/logger.lua                      -- thin logging wrapper
tests/minimal_init.lua                    -- minimal Neovim config for tests
tests/unit/config_spec.lua                -- config merge/validation tests
tests/unit/session_store_spec.lua         -- session store tests
tests/unit/provider_registry_spec.lua     -- provider selection tests
tests/contract/provider_contract_spec.lua -- shared contract for all providers
```

---

## Step-by-step Implementation

### 1. `plugin/codex.lua` — Entry point

- Guard on `vim.fn.has("nvim-0.10.0")`.
- Guard on `vim.g.loaded_codex`.
- No auto-setup; require explicit `require("codex").setup()`.

### 2. `lua/codex/logger.lua` — Logging

- Thin wrapper around `vim.notify` with configurable level.
- Levels: `debug`, `info`, `warn`, `error`.
- Prefix all messages with `[codex]`.

### 3. `lua/codex/config.lua` — Defaults and validation

Defaults table:

```lua
{
  cmd = "codex",          -- CLI binary to run
  args = {},              -- extra CLI args
  env = {},               -- extra env vars
  auto_start = false,     -- start terminal on setup()
  terminal = {
    provider = "auto",    -- "auto" | "snacks" | "native" | "external" | "none"
    split_side = "right", -- "left" | "right"
    split_width_pct = 40,
    auto_close = false,
    provider_opts = {
      snacks = {},
      external = { cmd = nil },
    },
  },
  cwd = nil,              -- explicit cwd, nil = use vim.fn.getcwd()
  log_level = "warn",
}
```

- `apply(user_opts)` — deep-merge with `vim.tbl_deep_extend("force", ...)`.
- `validate(config)` — assert types, known provider values, numeric ranges.

### 4. `lua/codex/state/session_store.lua` — Session state

Simple module-level table:

- `create(spec) -> id` — stores handle, cmd, cwd, provider name.
- `get(id) -> session | nil`
- `get_active() -> session | nil`
- `set_active(id)`
- `mark_dead(id)`
- `remove(id)`
- `list() -> session[]`

### 5. `lua/codex/providers/init.lua` — Provider registry

- `resolve(provider_name) -> provider_module, resolved_name`
  - `"auto"` → try snacks (if `is_available()`), else native.
  - Named providers looked up from internal table.
- Lazy-require provider modules to avoid load errors for missing deps.

### 6. Provider modules — shared contract

Every provider exports:

| Method | Signature | Description |
|--------|-----------|-------------|
| `is_available()` | `-> bool` | Can this provider be used? |
| `open(cmd, args, env, config, focus)` | `-> handle` | Start or show terminal |
| `close(handle)` | `-> ok, err?` | Close/kill terminal |
| `send(handle, text)` | `-> ok, err?` | Send text to terminal stdin |
| `focus(handle)` | `-> ok, err?` | Focus terminal window |
| `toggle(handle, cmd, args, env, config)` | | Toggle visibility |
| `is_alive(handle)` | `-> bool` | Is terminal still running? |
| `get_bufnr(handle)` | `-> int?` | Buffer number if applicable |

**`native.lua`** — Full implementation:
- Creates a vertical split with `vim.cmd("vsplit")`.
- Runs terminal via `vim.fn.termopen(cmd, { env, cwd, on_exit })`.
- Tracks `bufnr`, `winid`, `jobid` in returned handle table.
- `send` uses `vim.fn.chansend(jobid, text)`.
- `focus` sets current window and enters insert mode.
- `toggle` hides (closes window, keeps buffer) or re-shows.

**`snacks.lua`** — Delegates to `snacks.terminal`:
- `is_available()` checks `pcall(require, "snacks")`.
- `open` calls `Snacks.terminal(cmd, opts)`, passes `provider_opts.snacks`.
- Wraps snacks terminal object in handle for uniform API.

**`external.lua`** — Stub for Phase 1:
- `is_available()` returns `false`.
- All methods return error indicating not yet implemented.

**`none.lua`** — No-op:
- All methods are no-ops or return `false`.
- Useful for headless/test scenarios.

### 7. `lua/codex/nvim/commands.lua` — Command registration

Register two commands:

- **`:Codex[!] [args]`** — Open/toggle the Codex terminal.
  - Without `!`: toggle (hide if visible and focused, show if hidden).
  - With `!`: open and force focus.
  - Optional `args` appended to CLI invocation.
- **`:CodexFocus`** — Focus the terminal if alive, else start it.

Implementation: thin functions that call into `codex.init` public API.

### 8. `lua/codex/init.lua` — Public API and setup

```lua
M.setup(opts)    -- merge config, register commands, optional auto_start
M.open(focus)    -- resolve provider, open terminal, create session
M.close()        -- close active session
M.toggle()       -- toggle active session
M.focus()        -- focus or open+focus
M.send(text)     -- send text to active session
M.is_running()   -- is active session alive?
M.get_config()   -- return resolved config (read-only copy)
```

- `setup` stores config, sets up logger, registers commands, creates augroup
  for `VimLeavePre` cleanup.
- All public functions resolve provider lazily via registry.

### 9. Test scaffolding

**`tests/minimal_init.lua`** — Minimal Neovim headless config that adds plugin
to runtimepath so `require("codex")` works.

**`tests/unit/config_spec.lua`:**
- Default config is valid.
- User overrides merge correctly.
- Invalid provider name raises error.
- Numeric range validation works.

**`tests/unit/session_store_spec.lua`:**
- Create/get/remove sessions.
- Active session tracking.
- `mark_dead` updates state.

**`tests/unit/provider_registry_spec.lua`:**
- `"native"` resolves to native module.
- `"auto"` falls back to native when snacks unavailable.
- Unknown provider name errors.

**`tests/contract/provider_contract_spec.lua`:**
- Parameterized test that verifies `native` and `none` providers expose all
  required methods with correct signatures.

Test runner: `busted` via `nlua` or `nvim --headless -u tests/minimal_init.lua`.

---

## Verification

1. **Unit tests:** `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/unit"` (or busted equivalent).
2. **Manual smoke test:**
   - Open Neovim, run `:lua require("codex").setup({})`.
   - Run `:Codex` — should open a vertical split running `codex`.
   - Run `:CodexFocus` — should focus the terminal and enter insert mode.
   - Run `:Codex` again while focused — should toggle (hide).
   - Run `:Codex!` — should force-open and focus.
3. **Provider contract:** run contract spec confirming all providers have the
   required methods.

---

## Out of Scope (deferred to later phases)

- `:CodexSend`, `:CodexAdd`, `:CodexTreeAdd` (Phase 2)
- `:CodexResume`, `:CodexSelectModel` (Phase 3)
- `:CodexReview`, `:CodexDiff` (Phase 4)
- WebSocket/lock-file bridge
- README / rockspec / CI
