# Document slash-command recovery register

Update `doc/codex.nvim.txt` in the `builtin.execute_slash_command()` API entry and slash-command behavior section to explain that non-empty captured terminal input overwrites register `e`, while empty input leaves it unchanged. Document `:reg e` for inspection and `"ep` in Normal mode for pasting into a buffer, including recovery after command delivery fails.

Keep the behavior-section replacement focused on register `e`; omit the builder-draft, deferred-delivery, and Enter-submission bullets.

## Proposed edit

In `doc/codex.nvim.txt`, replace the introductory paragraph under `builtin.execute_slash_command({opts})` with:

```text
    Capture terminal input, save non-empty input to register `e`, clear the
    terminal input, and submit a slash command. Preserve the builder draft.
    Captured terminal input is not automatically restored.

    Register `e` is a recovery copy of the input present before the command.
    Each call with non-empty input overwrites it; empty input leaves it
    unchanged. Use `:reg e` to inspect it or `"ep` in Normal mode to paste
    it into a buffer. The copy remains available if command delivery fails.
```

In the same file's `Slash commands` behavior section, replace the bullets beginning with “Non-empty prompt input” through the end of that section with:

```text
- Non-empty prompt input overwrites register `e` before clearing the line;
  empty input leaves that register unchanged. Inspect it with `:reg e` or
  paste it into a buffer with `"ep` in Normal mode.
```

## Verification

No runtime changes. Validate helpfile syntax by generating help tags and inspect the diff. The documentation reflects the existing `vim.fn.setreg("e", current_input)` and `codex.prompt_builder.submit()` calls in `lua/codex/builtin/slash_command.lua`.
