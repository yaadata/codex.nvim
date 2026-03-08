# Architecture

## Overview

codex.nvim is a Neovim plugin that orchestrates an embedded terminal session for
the Codex CLI. The architecture centres on a **pluggable provider** abstraction:
all terminal management (opening, closing, sending text, focus, toggling) is
delegated to a provider that satisfies a 9-method interface contract. The core
module (`init.lua`) acts as a thin **facade** -- it owns dependency wiring and
the public Lua API, while delegating session lifecycle, send dispatch,
selection-send orchestration, and slash-command orchestration to dedicated
modules.

```
plugin/codex.lua          (entry point, version guard, load guard)
        │
        ▼
lua/codex/init.lua        (public API facade, DI container, setup wiring)
        │
        ├──► config.lua           (defaults, validation, deep merge)
        ├──► logger.lua           (level-gated notify facade + in-memory capture buffer)
        ├──► nvim/
        │        ├── commands.lua (user command registration)
        │        └── visual.lua   (best-effort visual-mode exit helper for selection sends)
        ├──► providers/init.lua   (provider registry + auto-resolution)
        │        ├── native.lua
        │        └── snacks.lua
        ├──► context/
        │        ├── formatter.lua  (selection + mention payload formatting)
        │        ├── mention.lua    (mention orchestration, prompt capture/restore)
        │        ├── path.lua       (CWD-relative path normalization)
        │        ├── selection.lua  (visual selection extraction)
        │        ├── selection_send.lua (selection-send orchestration, visual fallback range resolution, and collection-failure logging)
        │        └── wrapper_command.lua (slash-wrapper orchestration for /model, /status, /compact, etc.)
        ├──► runtime/
        │        ├── send_dispatch.lua  (send pipeline, queue/retry orchestration)
        │        ├── send_queue.lua     (FIFO queue + retry timer for startup readiness)
        │        └── terminal_io.lua    (terminal I/O utilities + constants)
        └──► state/
                 ├── session_lifecycle.lua  (session open/close/toggle/focus operations)
                 └── session_store.lua      (session registry, alive/dead tracking)
```

## Directory Layout

```
codex.nvim/
├── plugin/
│   └── codex.lua                    # Entry point. Guards Neovim >= 0.11.0 and
│                                    # prevents double-loading via vim.g.loaded_codex.
├── lua/codex/
│   ├── init.lua                     # Public API facade (setup, open, close, toggle,
│   │                                # send, send_file, send_selection, mention_file, mention_directory, resume, etc.).
│   │                                # Owns the DI container, setup wiring, and thin delegates.
│   ├── config.lua                   # Default config table, vim.validate-based
│   │                                # validation, and deep-merge with user options.
│   ├── types.lua                    # EmmyLua annotations only (no runtime code).
│   │                                # Central type definitions for the whole plugin.
│   ├── logger.lua                   # Logging facade with level-gated vim.notify output,
│   │                                # verbose-only capture logs, and bounded in-memory
│   │                                # log entries exposed via get_logs()/clear_logs().
│   ├── nvim/
│   │   ├── commands.lua             # Registers all :Codex* user commands. Each command
│   │                                # delegates to the corresponding init.lua API function.
│   │   └── visual.lua               # Neovim mode helper used to best-effort exit visual
│   │                                # mode before selection payload dispatch.
│   ├── providers/
│   │   ├── init.lua                 # Provider registry. Maps names to module paths,
│   │   │                            # lazy-loads on first resolve, implements auto-resolution
│   │   │                            # (prefers snacks, falls back to native).
│   │   ├── native.lua               # Built-in provider using vim.fn.termopen in
│   │   │                            # vsplit, hsplit, or float windows configured
│   │   │                            # via terminal.provider_opts.native, plus
│   │   │                            # terminal-local keymaps from terminal.keymaps.
│   │   ├── snacks.lua               # Provider backed by snacks.nvim terminal integration.
│   ├── context/
│   │   ├── formatter.lua            # Formats selection payloads (ACP path refs + fenced
│   │   │                            # code blocks with adaptive backtick fencing), ACP buffer refs,
│   │   │                            # and /mention payloads
│   │   │                            # (auto-quoting paths with special characters).
│   │   ├── mention.lua              # Mention orchestration: captures terminal prompt input,
│   │   │                            # dispatches /mention payloads, auto-submits, and restores
│   │   │                            # previously typed text. Uses create(opts) constructor.
│   │   ├── path.lua                 # Normalizes file paths to CWD-relative form via
│   │   │                            # fnamemodify(":."). Falls back to the original path
│   │   │                            # on error.
│   │   ├── selection.lua            # Extracts visual selection from the current buffer.
│   │   │                            # Resolves range via command args or visual marks.
│   │   ├── selection_send.lua       # Selection-send orchestration:
│   │   │                            # visual fallback range derivation, selection dispatch,
│   │   │                            # follow-up focus scheduling, and warning/error logging
│   │   │                            # for selection/buffer collection failures.
│   │   └── wrapper_command.lua      # Slash-wrapper command orchestration:
│   │   │                            # prompt capture/save/clear + dispatch + submit flow.
│   │   │                            # Uses create(opts) constructor.
│   ├── runtime/
│   │   ├── send_dispatch.lua        # Send pipeline with startup/retry orchestration.
│   │   │                            # Builds PendingSend items, submits to send_queue,
│   │   │                            # handles session readiness checks and timeout logic.
│   │   │                            # Uses create(opts) constructor.
│   │   ├── send_queue.lua           # Startup-readiness send queue. Owns retry scheduling
│   │   │                            # and FIFO flushing for deferred payload dispatch.
│   │   └── terminal_io.lua          # Pure/near-pure terminal I/O utilities: bracketed paste
│   │                                # encoding, termcode expansion, prompt line parsing,
│   │                                # ANSI stripping, and shared constants.
│   └── state/
│       ├── session_lifecycle.lua    # Session lifecycle operations: open, close, toggle,
│       │                            # focus, alive/ready checks, post-send refocus.
│       │                            # All functions take (deps, config) explicitly.
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
├── docs/                            # Internal planning and user/developer documentation.
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

### Module Patterns

#### Stateless modules

Most modules follow the standard Neovim module pattern:

```lua
local M = {}

-- private function (not on M)
local function helper() end

-- public function (on M)
function M.public_method() end

return M
```

Functions on `M` are the public API; bare `local function` declarations are
private. Examples: `terminal_io.lua`, `session_lifecycle.lua`, `config.lua`.

#### Constructor modules

Modules that need runtime accessors (closures over `get_deps`, `get_config`,
etc.) use a `create(opts)` constructor that returns a table of bound functions:

```lua
local M = {}

function M.create(opts)
  local get_deps = opts.get_deps

  local function private_helper() ... end

  local function public_method()
    local deps = get_deps()
    ...
  end

  return { public_method = public_method }
end

return M
```

`init.lua` calls `create()` during `setup()` and stores the returned instance in
`state`. This pattern avoids circular dependencies -- extracted modules never
`require("codex")` back. Examples: `send_dispatch.lua`, `mention.lua`,
`send_queue.lua`.

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
`on_exit` callback, `session_lifecycle.mark_session_dead_by_handle()` walks the
session list to find the matching handle and calls `mark_dead`.

`state/session_lifecycle.lua` builds on the session store with higher-level
operations: `open_session`, `close_session`, `toggle_session`, `focus_session`,
and alive/ready checks. All functions take `(deps, config)` explicitly, making
them stateless and testable without the full `init.lua` setup.

### Dependency Injection

`init.lua` defines a `default_deps` table containing all collaborators:

```lua
local default_deps = {
  config = require("codex.config"),
  logger = require("codex.logger"),
  providers = require("codex.providers"),
  session_store = require("codex.state.session_store"),
  send_queue = require("codex.runtime.send_queue"),
  commands = require("codex.nvim.commands"),
  nvim_visual = require("codex.nvim.visual"),
  formatter = require("codex.context.formatter"),
  selection = require("codex.context.selection"),
  selection_send = require("codex.context.selection_send"),
  path = require("codex.context.path"),
  vim = vim,
}
```

During `setup()`, if the options table contains a `_deps` key, those entries
override the corresponding defaults. The `_deps` key is then stripped before
config validation. This enables full isolation in unit tests: every collaborator
(including `vim` itself) can be replaced with a mock.

After resolving deps and config, `setup()` wires the constructor modules:

1. `send_dispatch.create()` -- receives `get_deps`, `get_config`,
   `get_send_queue`, and an `open_session` closure.
2. `send_queue.new()` -- receives the send dispatch's
   `process_pending_send_item` as its process callback.
3. `mention.create()` -- receives `get_deps`, `get_config`, and a
   `dispatch_send` closure that delegates to the send dispatch instance.
4. `wrapper_command.create()` -- receives `get_deps`, `get_config`, and a
   `dispatch_send` closure used by `execute_slash_command()` and in-process
   `resume()`.

This wiring order allows `send_dispatch` to reference the send queue (via
closure) even though the queue is created after the dispatch instance.

After wiring, setup registers `:Codex*` commands and cleanup autocmds. In
lazy.nvim `cmd + opts` setups, first-command discovery and plugin load are
handled by lazy command stubs before `setup()` runs. Global keymaps are
intentionally not managed in runtime setup; users configure them in their
plugin manager (for example lazy.nvim `keys`).

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

APIs that need an active session (`send`, `execute_slash_command`, `focus`,
`send_selection`, `mention_file`, `mention_directory`) automatically open one
when needed. The lower-level `send` API opens without focus, while
command-facing flows (`:CodexSendSelection`, `:CodexMentionFile`) ensure the terminal is
opened with focus before payload dispatch. If the provider handle is not yet
ready, payloads are queued and retried on a timer
(`terminal.startup.retry_interval_ms`) until ready or timeout
(`terminal.startup.timeout_ms`). Queueing/scheduling is implemented in
`runtime/send_queue.lua`, while `runtime/send_dispatch.lua` owns
session/open/reopen decisions. Providers apply a startup grace delay via
`terminal.startup.grace_ms` before reporting readiness.

## Component Interaction

Component-level command and setup flow diagrams are maintained in
[`docs/command-interactions.md`](./command-interactions.md).

## Type System

All shared types are defined in `lua/codex/types.lua` using EmmyLua `---@class`
and `---@alias` annotations. This file contains no runtime code (`return {}`).

Key types:

| Type                         | Kind  | Purpose                                                                |
| ---------------------------- | ----- | ---------------------------------------------------------------------- |
| `codex.Config`               | class | Merged configuration after `setup()`                                   |
| `codex.TerminalConfig`       | class | Nested terminal-specific options                                       |
| `codex.ProviderOptsConfig`   | class | Provider-specific options table (`native`, `snacks`)                   |
| `codex.NativeProviderOpts`   | class | Native provider window options (`window`, `vsplit`, `hsplit`, `float`) |
| `codex.WindowType`           | alias | Window mode union: `vsplit`, `hsplit`, `float`                         |
| `codex.VsplitConfig`         | class | Vertical split options (`side`, `size_pct`)                            |
| `codex.HsplitConfig`         | class | Horizontal split options (`side`, `size_pct`)                          |
| `codex.FloatConfig`          | class | Floating window options (size, border, title, title_pos)               |
| `codex.TerminalKeymapConfig` | alias | Terminal-local keymaps (`lhs -> { mode, action, desc? }`)              |
| `codex.ProviderName`         | alias | Union of valid provider name strings                                   |
| `codex.LogLevel`             | alias | Union of log level strings                                             |
| `codex.LogConfig`            | class | Logging config (`level`, `verbose`)                                    |
| `codex.LogEntry`             | class | Captured in-memory log entry shape                                     |
| `codex.Provider`             | class | 9-method structural interface for providers                            |
| `codex.ProviderHandle`       | alias | Opaque handle (`table`) returned by `provider.open()`                  |
| `codex.Session`              | class | Session record extending `codex.SessionSpec`                           |
| `codex.SessionSpec`          | class | Spec for creating a new session                                        |
| `codex.SelectionSpec`        | class | Visual selection data (defined in `formatter.lua`)                     |
| `codex.SelectionOpts`        | class | Options for selection extraction (defined in `selection.lua`)          |
| `codex.SendFileOpts`         | class | Options for `send_file` (`path`, `bufnr`, optional `focus`)            |
| `codex.UserCommandOpts`      | class | Neovim user command callback argument shape                            |
| `codex.PendingSend`          | class | Queued send item (defined in `send_dispatch.lua`)                      |
| `codex.DispatchSendOpts`     | class | Options for dispatch_send (defined in `send_dispatch.lua`)             |
| `codex.ResumeOpts`           | class | Options for the resume API (defined in `init.lua`)                     |
| `codex.SendResult`           | alias | Boolean result alias (defined in `init.lua`)                           |

`codex.ProviderHandle` is intentionally opaque (`table`). Providers define their
own internal handle structure; the core never inspects handle contents.

## Adding a New Provider

1. Create `lua/codex/providers/<name>.lua` following the
   `local M = {} / return M` pattern.
2. Implement all 9 methods from `codex.Provider` (use `native.lua` or
   `snacks.lua` as a reference).
3. Register the module path in the `provider_modules` table in
   `providers/init.lua`.
4. Add the new name to the `valid_providers` table in `config.lua`.
5. Add the name to the `codex.ProviderName` alias in `types.lua`.
6. Add an entry to `provider_modules` in
   `tests/contract/provider_contract_spec.lua` so the contract tests cover it.
7. If the provider accepts options, add a default entry under
   `terminal.provider_opts` in `config.lua` and honor shared
   `terminal.keymaps` semantics via `codex.keymaps.apply_terminal`.
