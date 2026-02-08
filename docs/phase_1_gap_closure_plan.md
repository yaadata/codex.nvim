# Phase 1 Gap Corrections Plan (Commit per Gap)

## Summary

This plan closes all retrospective TODO items in `docs/phase_1_implementation.md`.
Execution policy is strict: one commit per gap correction.

Locked decisions:

- Minimum Neovim version: `0.11.0`.
- Prioritize behavioral and testability gaps first.
- Lint/format stack: `stylua` + `selene`.
- Test portability: `.deps` clone strategy with env-var path override.
- CI scope: repo-local only for now (no workflow YAML).
- README scope: very short.
- Test seam style: internal dependency injection via `setup({ _deps = ... })`.

## Scope

In scope:

1. Fix native provider lifecycle correctness (`on_exit` -> session liveness).
2. Add tests for `init.lua` public API and command registration.
3. Make test harness portable without global `busted` or `nlua`.
4. Add baseline repo hygiene (`.gitignore`, `justfile`, formatter/linter config).
5. Add short README.

Out of scope:

- Phase 2+ feature work (`CodexSend`, `CodexAdd`, `CodexTreeAdd`, etc.).
- CI workflow files.
- Large architecture rewrite beyond test seams needed for phase closure.

## Commit Sequence (One Gap = One Commit)

### Commit 1: Make tests CI-portable

Goal:
- Remove hard dependency on local lazy path for plenary.

Changes:
1. Update `tests/minimal_init.lua` path resolution order:
- `CODEX_PLENARY_PATH`
- `.deps/plenary.nvim`
- `~/.local/share/nvim/lazy/plenary.nvim`
2. Emit explicit error if plenary cannot be found.

Validation:
- Run test entrypoints with env-var and `.deps` scenarios.

Message:
- `test: make plenary bootstrap portable via env var and .deps fallback`

### Commit 2: Add `.gitignore`

Goal:
- Add baseline repository ignore rules.

Changes:
1. Add `.gitignore` for `.deps/`, swap/temp/editor artifacts, and local tooling artifacts.

Validation:
- `git status --short` stays clean after test and tooling runs.

Message:
- `chore: add repo gitignore for deps and local artifacts`

### Commit 3: Add `justfile`

Goal:
- Standardize local bootstrap and quality commands.

Changes:
1. Add `justfile` targets:
- `bootstrap-test-deps`
- `test`
- `test-unit`
- `test-contract`
- `fmt`
- `fmt-check`
- `lint`
2. `bootstrap-test-deps` clones/updates plenary into `.deps/plenary.nvim`.

Validation:
- `just test` runs the same commands as manual test runs.

Message:
- `chore: add justfile for bootstrap, test, lint, and format commands`

### Commit 4: Add `stylua` config

Goal:
- Enforce deterministic Lua formatting.

Changes:
1. Add `.stylua.toml`.
2. Ensure `just fmt` and `just fmt-check` use it.

Validation:
- `just fmt-check` passes on repository Lua files.

Message:
- `style: add stylua configuration and format check workflow`

### Commit 5: Add `selene` config

Goal:
- Add static analysis for Lua and Neovim globals.

Changes:
1. Add `selene.toml` for plugin code conventions.
2. Ensure `just lint` uses selene.

Validation:
- `just lint` passes on tracked Lua files.

Message:
- `lint: add selene configuration for neovim plugin code`

### Commit 6: Add `init.lua` public API tests with injection seam

Goal:
- Test core logic without concrete providers.

Changes:
1. Extend `require("codex").setup(opts)` with internal `_deps` support.
2. Allow substitution of:
- provider resolver or registry
- session store
- logger
- command registration adapter
3. Add `tests/unit/init_spec.lua` (or equivalent) for:
- setup lifecycle
- `open`, `toggle`, `focus`, `send`, `close`, `is_running`
- stale session cleanup
- error paths

Validation:
- New unit suite passes without real terminal backend.

Message:
- `test(core): add init public API tests via internal dependency injection seam`

### Commit 7: Add command registration tests

Goal:
- Verify command registration and dispatch behavior.

Changes:
1. Add command tests to check:
- `:Codex` registered
- `:CodexFocus` registered
- `:Codex!` bang behavior
- commands dispatch to expected core paths

Validation:
- Command test suite passes in headless Neovim.

Message:
- `test(commands): verify Codex and CodexFocus registration and dispatch`

### Commit 8: Fix native provider `on_exit` session liveness

Goal:
- Session state becomes correct immediately on process exit.

Changes:
1. Wire provider exit callback to mark session dead in core/store.
2. Keep provider contract stable (no method renames).
3. Add lifecycle tests for immediate dead-state transition.

Validation:
- `is_running()` returns `false` after simulated exit callback.

Message:
- `fix(native): mark session dead on terminal exit callback`

### Commit 9: Remove global `busted` and `nlua` assumptions

Goal:
- Remove obsolete global-runner guidance.

Changes:
1. Update docs to use headless Neovim + plenary and `just` commands only.
2. Remove stale references to global `busted` or `nlua`.

Validation:
- `rg` confirms docs/scripts contain no global-runner instructions.

Message:
- `docs(test): remove global busted and nlua assumptions from guidance`

### Commit 10: Add short README

Goal:
- Provide minimal user-facing documentation for Phase 1.

Changes:
1. Create `README.md` with:
- scope
- install
- `setup({})` example
- `:Codex`, `:Codex!`, `:CodexFocus`
- provider summary
- `just test`
- minimum Neovim `0.11.0`

Validation:
- README setup and command examples match implemented behavior.

Message:
- `docs: add minimal README for phase 1 usage and testing`

## Public API / Interface Changes

1. `require("codex").setup(opts)` gains internal `_deps` override.
- Intended for tests only.
- Backward compatible for existing user setups.

2. Native provider lifecycle callback path updates session state in core.
- No change to end-user command names.
- No provider interface rename required.

## Test Cases and Scenarios

Core API scenarios:

1. Setup guard triggers before API calls when not initialized.
2. `open` creates a session when none exists.
3. `open` or `focus` reuses alive session.
4. `toggle` opens when missing and toggles visibility when present.
5. `send` auto-opens when no active session.
6. `close` clears active session.
7. Resolver and send failure paths log or raise correctly.

Command scenarios:

1. `:Codex` registration exists after `setup`.
2. `:CodexFocus` registration exists after `setup`.
3. `:Codex!` routes to force-open and focus path.
4. Commands dispatch to core functions correctly.

Lifecycle scenarios:

1. Provider exit callback marks active session dead immediately.
2. `is_running()` returns `false` after exit event.
3. Active session state is cleared or marked dead per policy.

Portability scenarios:

1. Plenary resolved from `CODEX_PLENARY_PATH`.
2. Plenary resolved from `.deps/plenary.nvim`.
3. Failure mode gives clear missing-plenary error.

Tooling scenarios:

1. `just test` runs all suites.
2. `just fmt-check` validates formatting.
3. `just lint` validates static analysis.

## Post-Review Corrections

### Commit 11: Fix `toggle()` missing `on_exit` callback

Goal:
- Ensure the `on_exit` session-liveness fix applies to all code paths that
  create sessions, not only `M.open()`.

Background:
- Code review of commits 1–10 identified that `M.toggle()` in `init.lua`
  called `provider.open()` with five arguments, omitting the sixth `on_exit`
  callback added in commit 8 (`ec31161`).
- Since `:Codex` (the primary user command) routes through `M.toggle()`, most
  sessions opened in practice would never have their exit callback wired,
  leaving stale `alive=true` entries in the session store.

Changes:
1. Pass the same `mark_session_dead_by_handle` closure as the sixth argument to
   `provider.open()` inside `M.toggle()`, matching the pattern in `M.open()`.
2. Add regression test `"marks session dead when opened via toggle and exit
   callback fires"` in `tests/unit/init_spec.lua`.

Validation:
- `just test` passes all 85 tests, including the new toggle on_exit test.

Message:
- `fix(core): pass on_exit callback when toggle opens a new session`

## Assumptions and Defaults

1. This phase produces 10 commits, one per retrospective gap correction, plus
   post-review corrections as needed.
2. Existing intentional working-tree changes remain unless directly modified by a matching gap correction.
3. No GitHub Actions workflow is added in this phase.
4. `_deps` remains internal and undocumented for end users.
