# codex.nvim

Neovim plugin for running the Codex CLI in an embedded terminal.

> **Primary home:** [Codeberg](https://codeberg.org/yaadata/codex.nvim) · mirrored on [GitHub](https://github.com/yaadata/codex.nvim)

## Requirements

- Neovim >= 0.11.0
- `codex` available on your `PATH` (or configure `cmd`)

## Install

```lua
{
  url = "https://codeberg.org/yaadata/codex.nvim.git",
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
    window = "vsplit", -- vsplit | hsplit | float
    vsplit = {
      side = "right", -- left | right
      size_pct = 40, -- 10-90
    },
    hsplit = {
      side = "bottom", -- top | bottom
      size_pct = 30, -- 10-90
    },
    float = {
      width_pct = 80, -- 10-100
      height_pct = 80, -- 10-100
      border = "rounded",
      title = " Codex ",
      title_pos = "center", -- left | center | right
    },
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

## Keymaps

Default keymaps are registered under `<leader>o`:

```lua
require("codex").setup({
  keymaps = {
    toggle = "<leader>ot",
    open = "<leader>oo",
    focus = "<leader>of",
    send = "<leader>os",
    add = "<leader>oa",
    resume = "<leader>or",
    model = "<leader>om",
    status = "<leader>oi",
    permissions = "<leader>op",
    compact = "<leader>oc",
    review = "<leader>oR",
    diff = "<leader>od",
  },
  keymaps_force = false, -- keep existing user mappings by default
})
```

Override examples:

```lua
-- Disable all default mappings
require("codex").setup({
  keymaps = false,
})

-- Override one mapping and disable another
require("codex").setup({
  keymaps = {
    toggle = "<leader>xx",
    status = false,
  },
})

-- Intentionally overwrite existing mappings
require("codex").setup({
  keymaps_force = true,
})
```

Set `vim.g.mapleader` before calling `require("codex").setup()` so `<leader>`
expands to the expected key.

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
