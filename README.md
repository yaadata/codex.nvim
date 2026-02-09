# codex.nvim

Neovim plugin for running the Codex CLI in an embedded terminal.

## Requirements

- Neovim >= 0.11.0
- `codex` available on your `PATH` (or configure `cmd`)

## Install

```lua
{
  "yaadata/codex.nvim",
  config = function()
    require("codex").setup({})
  end,
}
```

## Configuration

```lua
require("codex").setup({
  cmd = "codex",
  args = {},
  env = {},
  auto_start = false,
  terminal = {
    provider = "auto", -- auto | snacks | native | external | none
    split_side = "right",
    split_width_pct = 40,
  },
})
```

## Commands

- `:Codex` toggles the Codex terminal
- `:Codex!` force-opens and focuses the Codex terminal
- `:CodexFocus` focuses the terminal (opens it if needed)
- `:CodexSend` sends selected lines with file path and line range
  - when a command range is provided, it takes precedence over visual marks
  - selection is linewise; visual columns are ignored (charwise/blockwise still
    send full lines)
- `:CodexAdd [path]` sends `/mention <path>` (or current buffer path when
  omitted)
  - paths are auto-quoted/escaped when they contain whitespace or
    shell-significant characters
- `:CodexResume[!]` resumes a session
  - with an active Codex session, sends `/resume` in-process
  - without an active session, launches `codex resume` (or `codex resume --last`
    with `!`)
- `:CodexModel` sends `/model`
- `:CodexStatus` sends `/status`
- `:CodexPermissions` sends `/permissions`
- `:CodexCompact` sends `/compact`
- `:CodexReview [instructions]` sends `/review` (or `/review <instructions>`
  when provided)
- `:CodexDiff` sends `/diff`

## Lua API

- `require("codex").send_selection()`
- `require("codex").add_file(path)`
- `require("codex").send_command(slash_cmd)`
- `require("codex").resume(opts)`
- `require("codex").set_model()`
- `require("codex").show_status()`
- `require("codex").show_permissions()`
- `require("codex").compact()`
- `require("codex").review(instructions)`
- `require("codex").show_diff()`

## Providers

`auto` (default) prefers `snacks` when available, falls back to `native`. See
[docs/architecture.md](docs/architecture.md) for the full provider interface and
implementation details.

## Development

See [docs/contributing.md](docs/contributing.md) for setup, testing, formatting,
linting, and code style guidelines.
