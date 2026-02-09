# Pre-Phase-3 Checklist

## Objective

Before starting Phase 3 (`:CodexResume`, model/session controls), close remaining
LuaLS annotation and function documentation gaps so the codebase has a clear,
typed contract for core modules.

Also enforce local validation gates before each commit via `pre-commit`.

## Commit Gate (Required)

Install and enable pre-commit hooks for this repo:

```sh
mise install
just pre-commit-install
```

Hooks run on each commit and execute:

- `just fmt-check`
- `just lint`
- `just test-unit`

## Audit Snapshot (2026-02-09)

- Files audited: `lua/**`, `plugin/**`
- Exported functions detected: `60`
- Exported functions missing nearby LuaLS docs (`---@param`/`---@return`): `47`

Per-module exported-function coverage:

- `lua/codex/init.lua`: `0/10` missing
- `lua/codex/context/formatter.lua`: `0/2` missing
- `lua/codex/context/selection.lua`: `0/1` missing
- `lua/codex/config.lua`: `2/2` missing
- `lua/codex/state/session_store.lua`: `8/8` missing
- `lua/codex/providers/init.lua`: `2/2` missing
- `lua/codex/providers/native.lua`: `8/8` missing
- `lua/codex/providers/snacks.lua`: `8/8` missing
- `lua/codex/providers/none.lua`: `8/8` missing
- `lua/codex/providers/external.lua`: `5/5` missing
- `lua/codex/logger.lua`: `5/5` missing
- `lua/codex/nvim/commands.lua`: `1/1` missing

## Plan

### 1) Define Shared LuaLS Types First

Add or consolidate aliases/classes used across modules (either in a dedicated
types file or at module headers, but consistently):

- `codex.ProviderName` (`"auto"|"native"|"snacks"|"external"|"none"`)
- `codex.LogLevel`
- `codex.TerminalConfig`
- `codex.Config`
- `codex.SessionSpec`
- `codex.Session`
- `codex.ProviderHandle` (provider-specific handle shape documented as `table`)
- `codex.Provider` interface (method signatures for contract)

### 2) Annotate Core Config/State/Logging Modules

Add `---@param` and `---@return` for all exported functions in:

- `lua/codex/config.lua`
- `lua/codex/state/session_store.lua`
- `lua/codex/logger.lua`

Also add brief function doc comments where behavior is not obvious
(validation errors, reset semantics, log filtering behavior).

### 3) Annotate Provider Registry + Implementations

Add complete function annotations in:

- `lua/codex/providers/init.lua`
- `lua/codex/providers/native.lua`
- `lua/codex/providers/snacks.lua`
- `lua/codex/providers/none.lua`
- `lua/codex/providers/external.lua`

Requirements:

- Keep signatures aligned with the provider contract tests.
- Document multi-return contracts (`ok, err`, `handle|nil, err|nil`).
- Document optional callback semantics (`on_exit`) where present.

### 4) Annotate Command Adapter Layer

Add typed docs for:

- `lua/codex/nvim/commands.lua` exported registration function

Include callback `opts` table shapes used by user commands
(`bang`, `line1`, `line2`, `args`).

### 5) Optional Local-Helper Pass (Same PR if low risk)

Add docs for non-trivial local helpers that affect behavior and are worth
making explicit for maintainers/LuaLS readers:

- command builders (`build_cmd`)
- window lookup helper (`find_win_for_buf`)
- provider loader (`load_provider`)
- logger internal `log` formatter function

## Acceptance Criteria

1. Every exported `function M.*` in `lua/codex/**/*.lua` has:
- `---@param` entries for all inputs
- `---@return` entries for all return values
2. Provider function docs reflect actual contract behavior already enforced by
tests.
3. No functional behavior changes are introduced in this pass.
4. Verification passes:
- `mise exec -- just fmt-check`
- `mise exec -- just lint`
- `mise exec -- just test-unit`
5. `pre-commit` is installed and active for local commit-time validation.

## Suggested Commit Sequence

1. `docs(types): define shared lualls aliases for config/session/provider contracts`
2. `docs(config): annotate config, session_store, and logger function contracts`
3. `docs(providers): annotate provider registry and implementations`
4. `docs(commands): annotate neovim command registration layer`
