# Troubleshooting

Use this guide when `codex.nvim` behavior is unexpected and you need diagnostic
data for an issue report.

## Enable Detailed Logging

Turn on debug-level logging and verbose capture while reproducing the issue:

```lua
require("codex").setup({
  log = {
    level = "debug",
    verbose = true,
  },
})
```

- `log.level` controls which log levels are emitted/captured.
- `log.verbose` enables additional detailed capture entries used for debugging.

## Reproduce Cleanly

1. Start Neovim with your failing workflow.
2. Clear old logs before reproducing:

```vim
:lua require("codex").clear_logs()
```

3. Reproduce the problem once.
4. Capture logs:

```vim
:lua vim.print(require("codex").get_logs())
```

5. Copy logs to your system clipboard:

```vim
:lua vim.fn.setreg("+", vim.inspect(require("codex").get_logs()))
```

The returned entries are tables with:

- `seq` (monotonic sequence number for stable ordering)
- `timestamp` (monotonic milliseconds)
- `level` (`debug`, `info`, `warn`, `error`)
- `message`
- `verbose` (`true` for verbose-only debug entries)

## What To Include In An Issue

- Your Neovim version (`nvim --version`).
- Your `codex.nvim` version/commit.
- Relevant `setup()` config (`cmd`, `terminal.*`, and `log.*`).
- Reproduction steps.
- Captured output from `require("codex").get_logs()` (printed or pasted from clipboard).

## Reset After Debugging

Verbose capture is intended for troubleshooting sessions. After collecting logs,
switch back to normal logging:

```lua
require("codex").setup({
  log = {
    level = "warn",
    verbose = false,
  },
})
```
