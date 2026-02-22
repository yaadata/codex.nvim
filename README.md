# codex.nvim

Neovim plugin for running the Codex CLI in an embedded terminal.

> **Primary home:** [Codeberg](https://codeberg.org/yaadata/codex.nvim) ·
> mirrored on [GitHub](https://github.com/yaadata/codex.nvim)

## Requirements

- Neovim >= 0.11.0
- `codex` available on your `PATH` (or configure `cmd`)

> [!CAUTION]
> You are reading the `master` branch README. Install and configuration details
> may differ from tagged releases. The current latest release tag is
> [`v0.2.1`](https://codeberg.org/yaadata/codex.nvim/src/tag/v0.2.1). For
> version-accurate instructions, read the README for your target tag from
> [Codeberg releases](https://codeberg.org/yaadata/codex.nvim/releases).

## Install

```lua
{
  url = "https://codeberg.org/yaadata/codex.nvim.git",
  version = '0.2.1',
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
    provider = "auto", -- auto | snacks | native
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
    auto_close = false, -- close terminal buffer automatically when process exits
    startup = {
      timeout_ms = 2000, -- max time to wait for startup readiness before dropping queued sends
      retry_interval_ms = 50, -- retry interval while waiting for startup readiness
      grace_ms = 400, -- minimum delay after terminal open before first send
    },
    keymaps = {
      toggle = "<C-c>", -- terminal-mode toggle for Codex window
      clear_input = "<M-BS>", -- clear the current terminal input line
      close = false, -- set a string (e.g. "<C-x>") to close Codex session
      nav = {
        left = "<C-h>", -- split windows only; set false to disable
        down = "<C-j>", -- split windows only; set false to disable
        up = "<C-k>", -- split windows only; set false to disable
        right = "<C-l>", -- split windows only; set false to disable
      },
    },
  },
  keymaps = {
    toggle = "<leader>ot",
    open = "<leader>oo",
    focus = "<leader>of",
    close = "<leader>ox",
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
  keymaps_force = false, -- do not override existing mappings unless true
})
```

## Commands

- `:Codex` toggles the Codex terminal
- `:Codex!` force-opens and focuses the Codex terminal
- `:CodexFocus` focuses the terminal (opens it if needed)
- `:CodexClose` closes the active Codex terminal session
- `:CodexClearInput` clears the active Codex terminal input line
- `:CodexSend` sends selected lines with relative file path and line range
  - when a command range is provided, it takes precedence over visual marks
  - selection is linewise; visual columns are ignored (charwise/blockwise still
    send full lines)
  - payload is inserted via bracketed paste and is not auto-submitted
  - if the terminal is still starting, payloads are queued and retried until
    ready (or until `terminal.startup.timeout_ms` elapses)
  - after sending, codex.nvim focuses the Codex terminal in insert mode; press
    Enter to submit
- `:CodexAdd [path]` sends `/mention <path>` (or current buffer path when
  omitted)
  - paths are normalized to be relative to the current working directory
  - paths are auto-quoted/escaped when they contain whitespace or
    shell-significant characters
  - payload is inserted via bracketed paste and is not auto-submitted
  - if the terminal is still starting, payloads are queued and retried until
    ready (or until `terminal.startup.timeout_ms` elapses)
  - after sending, codex.nvim focuses the Codex terminal in insert mode; press
    Enter to submit
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
    close = "<leader>ox",
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

Terminal-local keymaps inside the Codex terminal buffer are configured
separately via `terminal.keymaps`:

```lua
require("codex").setup({
  terminal = {
    keymaps = {
      toggle = "<C-c>",
      clear_input = "<M-BS>",
      close = "<C-x>",
      nav = {
        left = "<A-h>",
        down = "<A-j>",
        up = "<A-k>",
        right = "<A-l>",
      },
    },
  },
})
```

`terminal.keymaps.clear_input` clears the current terminal input line.
`terminal.keymaps.close` triggers an intentional Codex session close.
`terminal.auto_close` controls whether provider windows auto-close only after
the terminal process exits. `terminal.keymaps.nav` is applied only for split
windows (`vsplit`/`hsplit`). Set `terminal.keymaps.nav = false` to disable all
navigation keymaps, or set individual directions to `false`.

## Lua API

- `require("codex").send_selection()`
- `require("codex").add_file(path)`
- `require("codex").close()`
- `require("codex").clear_input()`
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
