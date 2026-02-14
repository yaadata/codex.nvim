# Architecture

## Overview

codex.nvim is a Neovim plugin that orchestrates an embedded terminal session for
the Codex CLI. The architecture centres on a **pluggable provider** abstraction:
all terminal management (opening, closing, sending text, focus, toggling) is
delegated to a provider that satisfies a 9-method interface contract, while the
core module (`init.lua`) owns session lifecycle, dependency wiring, and the
public Lua API.

```
plugin/codex.lua          (entry point, version guard, load guard)
        │
        ▼
lua/codex/init.lua        (public API, session lifecycle, DI container)
        │
        ├──► config.lua           (defaults, validation, deep merge)
        ├──► logger.lua           (level-gated vim.notify wrapper)
        ├──► nvim/commands.lua    (user command registration)
        ├──► nvim/keymaps.lua     (default keymap registration)
        ├──► providers/init.lua   (provider registry + auto-resolution)
        │        ├── native.lua
        │        ├── snacks.lua
        │        ├── external.lua
        │        └── none.lua
        ├──► context/
        │        ├── formatter.lua  (selection + mention payload formatting)
        │        ├── path.lua       (CWD-relative path normalization)
        │        └── selection.lua  (visual selection extraction)
        └──► state/
                 └── session_store.lua  (session registry, alive/dead tracking)
```

## Directory Layout

```
codex.nvim/
├── plugin/
│   └── codex.lua                    # Entry point. Guards Neovim >= 0.11.0 and
│                                    # prevents double-loading via vim.g.loaded_codex.
├── lua/codex/
│   ├── init.lua                     # Public API surface (setup, open, close, toggle,
│   │                                # send, send_selection, add_file, resume, etc.).
│   │                                # Owns the DI container and session lifecycle.
│   ├── config.lua                   # Default config table, vim.validate-based
│   │                                # validation, and deep-merge with user options.
│   ├── types.lua                    # EmmyLua annotations only (no runtime code).
│   │                                # Central type definitions for the whole plugin.
│   ├── logger.lua                   # Thin wrapper around vim.notify with level gating
│   │                                # (debug/info/warn/error) and string.format support.
│   ├── nvim/
│   │   ├── commands.lua             # Registers all :Codex* user commands. Each command
│   │                                # delegates to the corresponding init.lua API function.
│   │   └── keymaps.lua              # Registers default keymaps, skips collisions by default,
│   │                                # supports keymaps_force overrides, and handles re-register.
│   ├── providers/
│   │   ├── init.lua                 # Provider registry. Maps names to module paths,
│   │   │                            # lazy-loads on first resolve, implements auto-resolution
│   │   │                            # (prefers snacks, falls back to native).
│   │   ├── native.lua               # Built-in provider using vim.fn.termopen in
│   │   │                            # vsplit, hsplit, or float windows, plus
│   │   │                            # terminal-local keymaps from terminal.keymaps.
│   │   ├── snacks.lua               # Provider backed by snacks.nvim terminal integration.
│   │   ├── external.lua             # Reserved stub for future external terminal support.
│   │   └── none.lua                 # No-op provider for tests and headless environments.
│   ├── context/
│   │   ├── formatter.lua            # Formats selection payloads (fenced code blocks with
│   │   │                            # adaptive backtick fencing) and /mention payloads
│   │   │                            # (auto-quoting paths with special characters).
│   │   ├── path.lua                 # Normalizes file paths to CWD-relative form via
│   │   │                            # fnamemodify(":."). Falls back to the original path
│   │   │                            # on error.
│   │   └── selection.lua            # Extracts visual selection from the current buffer.
│   │                                # Resolves range via command args or visual marks.
│   └── state/
│       └── session_store.lua        # In-memory session registry. Tracks sessions by ID
│                                    # with alive/dead lifecycle, active session pointer,
│                                    # and monotonic counter for ID generation.
├── tests/
│   ├── minimal_init.lua             # Minimal Neovim config for headless test runs.
│   │                                # Resolves plenary.nvim from env, .deps/, or lazy.
│   ├── unit/                        # Unit tests (one *_spec.lua per module).
│   └── contract/
│       └── provider_contract_spec.lua  # Structural compliance tests verifying every
│                                       # provider exports the required 9 methods.
├── docs/                            # Internal planning and developer documentation.
├── justfile                         # Task runner (test, fmt, lint, bootstrap).
├── .stylua.toml                     # Stylua formatter configuration.
├── selene.toml                      # Selene linter configuration.
├── codex.yml                        # Custom selene standard (lua51 + vim/test globals).
├── mise.toml                        # Mise tool version pins (stylua, selene, mdformat,
│                                    # pre-commit).
└── .pre-commit-config.yaml          # Pre-commit hooks (fmt-check, lint, md-fmt-check,
                                     # test-unit).
```

## Key Design Patterns

### Module Pattern

Every Lua module follows the standard Neovim module pattern:

```lua
local M = {}

-- private function (not on M)
local function helper() end

-- public function (on M)
function M.public_method() end

return M
```

Functions on `M` are the public API; bare `local function` declarations are
private. This convention is consistent across every file in `lua/codex/`.

### Provider Abstraction

Providers implement a 9-method interface defined in `types.lua` as
`codex.Provider`:

| Method         | Signature                                                                        |
| -------------- | -------------------------------------------------------------------------------- |
| `is_available` | `fun(): boolean`                                                                 |
| `open`         | `fun(cmd, args, env, config, focus, on_exit?): ProviderHandle\|nil, string\|nil` |
| `close`        | `fun(handle): boolean, string\|nil`                                              |
| `send`         | `fun(handle, text): boolean, string\|nil`                                        |
| `focus`        | `fun(handle): boolean, string\|nil`                                              |
| `toggle`       | `fun(handle, cmd, args, env, config): ProviderHandle\|nil, string\|nil`          |
| `is_alive`     | `fun(handle): boolean`                                                           |
| `is_ready`     | `fun(handle): boolean`                                                           |
| `get_bufnr`    | `fun(handle): integer\|nil`                                                      |

The provider registry (`providers/init.lua`) maps provider names to module paths
and lazy-loads them on first resolve. Auto-resolution prefers `snacks` when
available, falling back to `native`.

Contract tests (`tests/contract/provider_contract_spec.lua`) verify that every
registered provider exports all 9 methods as functions and handles nil handles
gracefully.

### Handle-Based State

`session_store.lua` maintains an in-memory registry of sessions keyed by
monotonically-generated IDs (`session_1`, `session_2`, ...). Each session
tracks:

- `handle` -- opaque `codex.ProviderHandle` returned by `provider.open()`
- `alive` -- boolean lifecycle flag
- `cmd`, `cwd`, `provider_name` -- metadata

The store exposes `create`, `get`, `get_active`, `mark_dead`, `remove`, `list`,
and `reset`. Only one session is "active" at a time. When a provider fires its
`on_exit` callback, `init.lua` walks the session list to find the matching
handle and calls `mark_dead`.

### Dependency Injection

`init.lua` defines a `default_deps` table containing all collaborators:

```lua
local default_deps = {
  config = require("codex.config"),
  logger = require("codex.logger"),
  providers = require("codex.providers"),
  session_store = require("codex.state.session_store"),
  commands = require("codex.nvim.commands"),
  keymaps = require("codex.nvim.keymaps"),
  formatter = require("codex.context.formatter"),
  selection = require("codex.context.selection"),
  vim = vim,
}
```

During `setup()`, if the options table contains a `_deps` key, those entries
override the corresponding defaults. The `_deps` key is then stripped before
config validation. This enables full isolation in unit tests: every collaborator
(including `vim` itself) can be replaced with a mock.

### Error Handling

The codebase uses two error-reporting strategies:

- **`(ok, err_string)` two-value returns** for operational failures (provider
  send failed, selection extraction failed). Callers check the first value and
  log or propagate the error string.
- **`error()`** for programmer errors only (calling API before `setup()`,
  requesting an unknown provider). These indicate bugs, not runtime conditions.

### Guard Pattern

Every public API method in `init.lua` calls `ensure_setup()` as its first
statement. This function raises an error if `setup()` has not been called,
giving an immediate and clear diagnostic rather than obscure nil-reference
failures downstream.

### Auto-Open

APIs that need an active session (`send`, `send_command`, `focus`,
`send_selection`, `add_file`) automatically open one when needed. The lower-level
`send` API opens without focus, while command-facing flows (`:CodexSend`,
`:CodexAdd`) ensure the terminal is opened with focus before payload dispatch.
If the provider handle is not yet ready, payloads are queued and retried on a
timer (`terminal.startup_retry_interval_ms`) until ready or timeout
(`terminal.startup_timeout_ms`). Providers apply a startup grace delay via
`terminal.startup_grace_ms` before reporting readiness.

## Component Interaction

### `setup()` Registration Flow

```
User calls require("codex").setup(opts)
    │
    ▼
init.lua setup()
    ├── build deps (default_deps + opts._deps)
    ├── apply config defaults + validation
    ├── commands.register()
    ├── keymaps.register(config)
    │     ├── unregister stale Codex keymaps from previous setup
    │     ├── skip keymaps when keymaps=false
    │     ├── skip mapping collisions unless keymaps_force=true
    │     └── register n/x mappings for Codex actions
    └── register VimLeavePre cleanup autocmd
```

### `:Codex` Toggle Flow

```
User runs :Codex
    │
    ▼
commands.lua     →  codex.toggle() (or codex.open(true) for :Codex!)
    │
    ▼
init.lua toggle()
    ├── ensure_setup()
    ├── session_store.get_active()
    ├── providers.resolve(config.terminal.provider)
    │
    ├── [active + provider.is_alive(handle)] → provider.toggle(handle, cmd, args, env, config)
    │                       └── if new_handle returned, update session.handle
    │
    └── [no active session] → open_session(args, focus=true)
                                ├── provider.open(cmd, args, env, config, focus, on_exit_cb)
                                └── session_store.create({ handle, cmd, cwd, provider_name })
```

### `:CodexSend` with Visual Selection

```
User visually selects lines, runs :'<,'>CodexSend
    │
    ▼
commands.lua     →  codex.send_selection({ line1, line2 })
    │
    ▼
init.lua send_selection()
    ├── ensure_setup()
    ├── selection.get_visual_selection(vim, opts)
    │       ├── resolve_range(vim_api, bufnr, opts)  -- command range or visual marks
    │       ├── nvim_buf_get_lines(bufnr, start-1, end, false)
    │       └── return SelectionSpec { relative filepath, start_line, end_line, filetype, lines }
    │
    ├── formatter.format_selection(spec)
    │       └── build fenced code block with adaptive backtick fencing
    │
    └── dispatch_send(payload)
            ├── [active + ready] → provider.send(session.handle, text)
            ├── [no active session] → open_session(args, focus=true)
            └── [not ready yet] → queue + retry loop (defer_fn) until ready/timeout
```

## Type System

All shared types are defined in `lua/codex/types.lua` using EmmyLua `---@class`
and `---@alias` annotations. This file contains no runtime code (`return {}`).

Key types:

| Type                         | Kind  | Purpose                                                       |
| ---------------------------- | ----- | ------------------------------------------------------------- |
| `codex.Config`               | class | Merged configuration after `setup()`                          |
| `codex.TerminalConfig`       | class | Nested terminal-specific options                              |
| `codex.WindowType`           | alias | Window mode union: `vsplit`, `hsplit`, `float`                |
| `codex.VsplitConfig`         | class | Vertical split options (`side`, `size_pct`)                   |
| `codex.HsplitConfig`         | class | Horizontal split options (`side`, `size_pct`)                 |
| `codex.FloatConfig`          | class | Floating window options (size, border, title, title_pos)      |
| `codex.TerminalKeymapConfig` | class | Terminal-local keymaps (`toggle`, `close`)                    |
| `codex.KeymapConfig`         | class | Keymap action table (`string` or `false` per action)          |
| `codex.ProviderName`         | alias | Union of valid provider name strings                          |
| `codex.LogLevel`             | alias | Union of log level strings                                    |
| `codex.Provider`             | class | 9-method structural interface for providers                   |
| `codex.ProviderHandle`       | alias | Opaque handle (`table`) returned by `provider.open()`         |
| `codex.Session`              | class | Session record extending `codex.SessionSpec`                  |
| `codex.SessionSpec`          | class | Spec for creating a new session                               |
| `codex.SelectionSpec`        | class | Visual selection data (defined in `formatter.lua`)            |
| `codex.SelectionOpts`        | class | Options for selection extraction (defined in `selection.lua`) |
| `codex.UserCommandOpts`      | class | Neovim user command callback argument shape                   |
| `codex.ResumeOpts`           | class | Options for the resume API (defined in `init.lua`)            |
| `codex.SendResult`           | alias | Boolean result alias (defined in `init.lua`)                  |

`codex.ProviderHandle` is intentionally opaque (`table`). Providers define their
own internal handle structure; the core never inspects handle contents.

## Adding a New Provider

1. Create `lua/codex/providers/<name>.lua` following the
   `local M = {} / return M` pattern.
2. Implement all 9 methods from `codex.Provider` (use `none.lua` as a minimal
   skeleton).
3. Register the module path in the `provider_modules` table in
   `providers/init.lua`.
4. Add the new name to the `valid_providers` table in `config.lua`.
5. Add the name to the `codex.ProviderName` alias in `types.lua`.
6. Add an entry to `provider_modules` in
   `tests/contract/provider_contract_spec.lua` so the contract tests cover it.
7. If the provider accepts options, add a default entry under
   `terminal.provider_opts` in `config.lua` and honor shared
   `terminal.keymaps` semantics for terminal-local toggle/close mappings.
