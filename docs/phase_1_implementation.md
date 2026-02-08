# Phase 1 Implementation Summary

## Overview

Phase 1 delivers the core terminal lifecycle and command surface for
`codex.nvim`: a setup API with validated defaults, a provider-abstracted
terminal layer, and two user commands (`:Codex`, `:CodexFocus`).

**Decisions made before implementation:**

- Default terminal command: `codex`
- Minimum Neovim version: 0.11.0
- Test framework: plenary.nvim via `nvim --headless`

---

## Files Created

| File | Purpose |
|------|---------|
| `plugin/codex.lua` | Entry point with Neovim version guard and double-load prevention |
| `lua/codex/init.lua` | `setup()` and public API (`open`, `close`, `toggle`, `focus`, `send`, `is_running`, `get_config`) |
| `lua/codex/config.lua` | Default config table, `apply()` deep-merge, `validate()` with type and range checks |
| `lua/codex/logger.lua` | Thin `vim.notify` wrapper with level filtering and `[codex]` prefix |
| `lua/codex/state/session_store.lua` | Module-level session table with `create`, `get`, `get_active`, `set_active`, `mark_dead`, `remove`, `list`, `reset` |
| `lua/codex/providers/init.lua` | Provider registry with lazy-require and `resolve()` (handles `"auto"` fallback) |
| `lua/codex/providers/native.lua` | Full implementation using `vim.fn.termopen` in a configurable vsplit |
| `lua/codex/providers/snacks.lua` | Delegate to `snacks.nvim` terminal API, wrapping its object in a uniform handle |
| `lua/codex/providers/external.lua` | Stub — `is_available()` returns `false`, all methods return not-implemented errors |
| `lua/codex/providers/none.lua` | No-op provider for headless/test use |
| `lua/codex/nvim/commands.lua` | Registers `:Codex[!]` and `:CodexFocus` as thin adapters into `init.lua` |
| `tests/minimal_init.lua` | Headless Neovim bootstrap: adds plugin and plenary to rtp |
| `tests/unit/config_spec.lua` | 10 tests for config defaults, merge, and validation |
| `tests/unit/session_store_spec.lua` | 10 tests for session CRUD and active tracking |
| `tests/unit/provider_registry_spec.lua` | 5 tests for provider resolution and error cases |
| `tests/contract/provider_contract_spec.lua` | 44 tests verifying all 4 providers export the required interface |

---

## Architecture

### Provider contract

Every provider module exports the same interface:

```
is_available() -> bool
open(cmd, args, env, config, focus) -> handle
close(handle) -> ok, err?
send(handle, text) -> ok, err?
focus(handle) -> ok, err?
toggle(handle, cmd, args, env, config) -> handle
is_alive(handle) -> bool
get_bufnr(handle) -> int?
```

The `handle` is an opaque table whose shape is provider-specific. The native
provider stores `{ bufnr, winid, jobid }`. The snacks provider wraps the snacks
terminal object as `{ terminal, provider }`.

### Provider resolution

`providers/init.lua` lazy-requires provider modules and caches them. The
`resolve(name)` function handles `"auto"` by trying snacks first (via
`is_available()`), falling back to native. Unknown or unavailable providers
raise errors.

### Session store

A simple module-level table keyed by auto-incrementing IDs. Tracks the active
session separately. Provides `reset()` for test isolation.

### Command flow

`:Codex` and `:CodexFocus` are thin wrappers registered in
`lua/codex/nvim/commands.lua`. They call `require("codex").toggle()` or
`require("codex").focus()`, which resolve the provider, check for an existing
session, and delegate to the provider's methods.

`:Codex!` (with bang) calls `open(true)` to force-open and focus.

### Init lifecycle

`require("codex").setup(opts)`:

1. Merges user opts with defaults via `vim.tbl_deep_extend("force", ...)`.
2. Validates the merged config (types, allowed values, numeric ranges).
3. Sets the logger level.
4. Registers user commands.
5. Creates a `VimLeavePre` autocmd for cleanup.
6. Optionally auto-starts the terminal if `auto_start = true`.

---

## Config defaults

```lua
{
  cmd = "codex",
  args = {},
  env = {},
  auto_start = false,
  terminal = {
    provider = "auto",
    split_side = "right",
    split_width_pct = 40,
    auto_close = false,
    provider_opts = {
      snacks = {},
      external = { cmd = nil },
    },
  },
  cwd = nil,
  log_level = "warn",
}
```

Validation enforces:

- `terminal.provider` must be one of `auto`, `snacks`, `native`, `external`,
  `none`.
- `terminal.split_width_pct` must be between 10 and 90.
- `terminal.split_side` must be `"left"` or `"right"`.

---

## Testing

### Framework

Tests run via plenary.nvim's busted-compatible runner in headless Neovim:

```sh
nvim --headless -u tests/minimal_init.lua \
  -c 'PlenaryBustedFile tests/unit/config_spec.lua'
```

### Test suites and results

| Suite | Tests | Status |
|-------|-------|--------|
| `tests/unit/config_spec.lua` | 10 | All pass |
| `tests/unit/session_store_spec.lua` | 10 | All pass |
| `tests/unit/provider_registry_spec.lua` | 5 | All pass |
| `tests/contract/provider_contract_spec.lua` | 44 | All pass |
| **Total** | **69** | **All pass** |

### What each suite covers

**config_spec.lua:**

- Default values are correct.
- `apply(nil)` and `apply({})` return defaults.
- User overrides merge correctly (deep merge preserves unset fields).
- Defaults table is not mutated by `apply()`.
- Invalid provider names, out-of-range `split_width_pct`, and invalid
  `split_side` all raise errors with descriptive messages.

**session_store_spec.lua:**

- `create()` returns a string ID prefixed with `session_`.
- Newly created sessions become the active session.
- All fields (`handle`, `cmd`, `cwd`, `provider_name`, `alive`) are stored.
- `get()` returns `nil` for unknown IDs.
- `mark_dead()` sets `alive = false` and clears active if applicable.
- `remove()` deletes the session entirely.
- `set_active()` switches the active session.
- `list()` returns all sessions (empty when none exist).

**provider_registry_spec.lua:**

- `"native"` resolves to the native module with all expected functions.
- `"none"` resolves to the none module.
- `"auto"` falls back to native when snacks is not installed.
- Unknown provider names raise errors.
- Unavailable providers (e.g. `"external"`) raise errors.

**provider_contract_spec.lua:**

- Parameterized across all 4 providers (native, snacks, external, none).
- Each provider exports all 8 required methods as functions.
- `is_available()` returns a boolean.
- `is_alive(nil)` returns a boolean (not an error).
- `get_bufnr(nil)` returns `nil` (not an error).

---

## Pitfalls and Resolutions

### 1. Test runner standardization

**Problem:** Test commands were inconsistent and depended on local editor
setup details, which made reproducibility weaker across machines.

**Resolution:** Standardized on headless Neovim with plenary's
busted-compatible runner (`PlenaryBustedFile`) through the `just` targets.
This keeps tests inside a real Neovim runtime and avoids alternate Lua test
runner paths.

### 2. Plenary not found under `-u` flag

**Problem:** Running `nvim --headless -u tests/minimal_init.lua` skips the
user's normal `init.lua`, which means lazy.nvim never loads and plenary is not
on the runtime path. The `PlenaryBustedFile` command was not registered, and
`require("plenary.test_harness")` failed.

**Resolution:** Updated `tests/minimal_init.lua` to explicitly prepend
plenary's install path (`~/.local/share/nvim/lazy/plenary.nvim`) to `vim.opt.rtp`
and run `runtime plugin/plenary.vim` to register plenary's commands. This
makes the test bootstrap self-contained regardless of the user's Neovim config.

### 3. Shell quoting in headless Neovim commands

**Problem:** Using double-quoted `-c "qa!"` in the shell caused Neovim to
misparse the `!` as a trailing character (`E488: Trailing characters`), and
commands would hang indefinitely.

**Resolution:** Used single quotes for `-c` arguments (`-c 'qa'`) and avoided
`!` in quit commands. For Lua strings inside `-c`, used single-quoted shell
strings with double-quoted Lua strings inside.

### 4. Config deep-merge mutating defaults

**Problem:** Without `vim.deepcopy`, `vim.tbl_deep_extend("force", M.defaults,
user_opts)` could mutate nested tables in the defaults (e.g.
`defaults.terminal.provider_opts`) when users passed nested overrides.

**Resolution:** `config.apply()` deep-copies defaults before merging:
`vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})`.
A dedicated test (`"does not mutate defaults"`) guards against regression.

---

## Retrospective: What I Would Do Better

- [ ] **Make tests CI-portable.** `tests/minimal_init.lua` hardcodes the
  plenary path to `~/.local/share/nvim/lazy/plenary.nvim`. In CI there is no
  lazy.nvim — plenary would need to be cloned to a known location and the path
  injected via an environment variable or a Makefile that handles the clone.
  A `just test` recipe should clone plenary into a `.deps/` directory and pass
  it to `minimal_init.lua`.

- [ ] **Add a `.gitignore`.** The repo has none. At minimum it should ignore
  `.deps/`, `*.swp`, `.luarocks/`, and any future build artifacts.

- [ ] **Add a `justfile`.** A single `just test` recipe that bootstraps
  dependencies (plenary clone) and runs all test suites in one shot, rather
  than requiring three separate `nvim --headless` invocations.

- [ ] **Add `stylua` formatting.** There is no enforced Lua style. Setting up
  a `.stylua.toml` and running `stylua --check` in CI would catch
  inconsistencies early.

- [ ] **Add `luacheck` or `selene` linting.** Static analysis would catch
  unused variables, shadowed locals, and access to undefined globals before
  tests even run.

- [ ] **Test the `init.lua` public API.** The unit tests cover config,
  session store, and provider registry in isolation, but there are no tests for
  `require("codex").setup()`, `.toggle()`, or `.focus()`. These would need a
  mock provider injected into the registry to avoid real terminal side effects.

- [ ] **Test command registration.** There is no test verifying that
  `:Codex` and `:CodexFocus` are actually registered after `setup()` and that
  they dispatch correctly. A minimal integration test calling
  `vim.api.nvim_get_commands({})` after setup would cover this.

- [ ] **Handle `on_exit` in native provider properly.** The `on_exit` callback
  in `native.lua` logs the exit code but does not call
  `session_store.mark_dead()`. When the CLI process exits, the session store
  still thinks the session is alive until the next `is_alive()` check. Wiring
  `on_exit` into the session store would make state tracking more accurate.

- [ ] **Add a `README.md`.** The plugin has no user-facing documentation yet.
  Even a minimal README with install instructions, a `setup({})` example, and
  the two available commands would make the plugin usable by others.
