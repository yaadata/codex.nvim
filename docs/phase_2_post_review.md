# Phase 2 Post-Review

## Scope

Review of 14 commits from `f456dba` to `28b1dbc`, covering:

- Phase 2 feature implementation (context transfer: `:CodexSend`, `:CodexAdd`)
- Phase 2 gap closures (typed annotations, path safety, range precedence, error normalization)
- Pre-phase-3 LuaLS annotation pass (all 60 exported functions)
- Pre-commit hook setup

## Findings

### Correction 1: Error message double-prefix

Severity: important

In `lua/codex/init.lua`, both `send_selection` and `add_file` wrap errors with a
`"codex: "` prefix, but the error strings returned from `selection.lua` already
carry the `"codex: "` prefix via constants (`ERR_NO_FILEPATH`, `ERR_NO_SELECTION`).

Result:

```
codex: failed to collect selection: codex: no visual selection range found
codex: failed to add file context: codex: current buffer has no file path
```

Fix: strip the `"codex: "` prefix from the error constants in `selection.lua` so
the orchestration layer in `init.lua` adds the single authoritative prefix.

Tests asserting these messages must be updated to match.

### Correction 2: `snacks.lua` ignores `on_exit` callback

Severity: minor (pre-existing from Phase 1, not a Phase 2 regression)

The snacks provider accepts `_on_exit` in its `open()` signature but discards it.
Sessions opened via snacks will never be marked dead on terminal exit, leaving
stale `alive=true` entries in the session store.

Fix: wire the `on_exit` callback to the snacks terminal's exit event, matching the
native provider's behavior. If snacks does not expose an exit hook, document the
limitation.

### Informational: `external.lua` annotation commit included behavioral changes

Commit `2c92e3e` changed `M.close = not_implemented` to
`function M.close(_handle) return not_implemented() end` (and similar for
`M.send`, `M.focus`). This adds a call frame and named parameters — functionally
equivalent but not purely documentation. No action required; noted for commit
hygiene awareness.

### Informational: Path quoting assumption

`format_mention` quotes paths containing spaces or shell-significant characters
with double quotes and backslash escaping. This assumes the Codex CLI's `/mention`
parser accepts quoted paths. The implementation is isolated to `quote_path()` in
`formatter.lua`, so adjustment is straightforward if the assumption proves wrong.

## Commit Sequence

### Correction 1: `fix(errors): remove double codex prefix from selection error constants`

Changes:
1. Strip `"codex: "` prefix from `ERR_NO_FILEPATH` and `ERR_NO_SELECTION` in
   `lua/codex/context/selection.lua`.
2. Update `tests/unit/selection_spec.lua` assertions to match.
3. Update `tests/unit/init_spec.lua` assertions to match.

Validation:
- `mise exec -- just test` passes.
- Error strings in logs contain exactly one `"codex: "` prefix.

### Correction 2: `fix(snacks): wire on_exit callback to snacks terminal lifecycle`

Changes:
1. In `lua/codex/providers/snacks.lua`, connect the `on_exit` callback to the
   snacks terminal's exit event (or document the gap if no hook exists).
2. Add test coverage if feasible within the contract test suite.

Validation:
- `mise exec -- just test` passes.
