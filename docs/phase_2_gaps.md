# Phase 2 Gaps (Post-Implementation)

## Summary

Phase 2 core features are implemented (`:CodexSend`, `:CodexAdd`, selection/context modules),
but a few quality and clarity gaps remain before we treat it as fully hardened.

This document tracks those gaps with concrete acceptance criteria.

## Gap 1: Function Documentation With Typed Inputs/Returns

Status:
- Completed in `bbe6cae`.

Goal:
- Add function-level documentation with explicit input and return types for all new Phase 2 APIs.

Why:
- The Phase 2 API surface is now non-trivial (`send_selection`, `add_file`, formatter/selection modules).
- Typed doc comments reduce misuse and improve maintainability/test readability.

Scope:
- `lua/codex/init.lua`
- `lua/codex/context/formatter.lua`
- `lua/codex/context/selection.lua`
- Any shared type aliases needed by those modules.

Required format:
- Use EmmyLua/LuaLS-style annotations.
- Include `---@param` and `---@return` on public and exported module functions.
- Add table-shape aliases for core data structs.

Minimum type aliases to define:
- `codex.SelectionSpec`
- `codex.SelectionOpts`
- `codex.SendResult` (or equivalent `boolean, string|nil` convention)

Acceptance criteria:
1. Every exported function in the files above has `---@param` and `---@return`.
2. `send_selection(opts)` documents success/error returns explicitly.
3. `add_file(path)` documents nil-path fallback behavior and error contract.
4. Selection spec fields (`filepath`, `start_line`, `end_line`, `filetype`, `lines`) are typed.

## Gap 2: Mention Payload Path Safety

Status:
- Completed in `ebd6f35`.

Goal:
- Define and enforce path formatting behavior for `/mention` payloads.

Why:
- Paths with spaces/special characters can produce ambiguous slash-command parsing.

Scope:
- `lua/codex/context/formatter.lua`
- `tests/unit/formatter_spec.lua`
- `README.md` command notes

Acceptance criteria:
1. Document exact path formatting strategy (raw, quoted, or escaped).
2. Unit tests cover spaces and at least one shell-significant character case.
3. README documents the expected path behavior.

## Gap 3: Selection Source Rules and Mode Semantics

Status:
- Completed in current branch (pending commit).

Goal:
- Clarify and test selection behavior across command ranges and visual marks.

Why:
- `:CodexSend` can be invoked from visual mode or with explicit line ranges.
- Behavior should stay deterministic and documented.

Scope:
- `lua/codex/context/selection.lua`
- `tests/unit/selection_spec.lua`
- `README.md`

Acceptance criteria:
1. Source precedence is explicit: command range (`line1/line2`) vs visual marks.
2. Reversed range normalization is documented and tested.
3. Unsupported selection modes (if any) are documented clearly.

## Gap 4: User-Facing Error Message Consistency

Status:
- Pending.

Goal:
- Standardize error strings/log lines for Phase 2 flows.

Why:
- Current errors are functional but not yet normalized for UX/debugging consistency.

Scope:
- `lua/codex/init.lua`
- `lua/codex/context/selection.lua`
- unit tests asserting error text

Acceptance criteria:
1. Error strings follow a consistent prefix style.
2. Tests assert normalized messages for:
- unnamed buffer path
- missing selection range
- failed selection extraction
- failed add_file path resolution

## Suggested Commit Sequence

1. `docs(types): add typed function annotations for phase 2 APIs`
2. `fix(context): define mention path formatting and edge-case tests`
3. `test(selection): lock range precedence and mode semantics`
4. `chore(errors): normalize phase 2 error messages and assertions`
