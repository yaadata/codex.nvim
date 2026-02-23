# codex.nvim

Neovim plugin for running the Codex CLI in an embedded terminal.

> **Primary home:** [Codeberg](https://codeberg.org/yaadata/codex.nvim) ·
> mirrored on [GitHub](https://github.com/yaadata/codex.nvim)

## Requirements

- Neovim >= 0.11.0
- `codex` available on your `PATH` (or configure `cmd`)

> [!CAUTION]
> You are reading the `main` branch README. Install and configuration details
> may differ from tagged releases. The current latest release tag is
> [`v0.2.2`](https://codeberg.org/yaadata/codex.nvim/src/tag/v0.2.2). For
> version-accurate instructions, read the README for your target tag from
> [Codeberg releases](https://codeberg.org/yaadata/codex.nvim/releases).

## Install

```lua
{
  url = "https://codeberg.org/yaadata/codex.nvim.git",
  version = '0.2.2',
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
  log_level = "warn",
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
      grace_ms = 700, -- minimum delay after terminal open before first send
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
- `:CodexSend` sends selected lines with path and range context.
- `:CodexAdd [path]` sends `/mention` for a path (or current buffer path).
- `:CodexResume[!]` resumes in-process or launches `codex resume` (`!` uses
  `--last` when launching).
- `:CodexModel` sends `/model`
- `:CodexStatus` sends `/status`
- `:CodexPermissions` sends `/permissions`
- `:CodexCompact` sends `/compact`
- `:CodexReview [instructions]` sends `/review`.
- `:CodexDiff` sends `/diff`

For detailed command behavior and component interactions, see
[`docs/command-interactions.md`](docs/command-interactions.md).

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

- `require("codex").setup(opts)` initialize plugin config, commands, and keymaps.
- `require("codex").open(focus)` open terminal session.
- `require("codex").close()` close active session.
- `require("codex").toggle()` toggle terminal visibility.
- `require("codex").focus()` focus active session.
- `require("codex").send(text)` send raw text.
- `require("codex").clear_input()` clear current prompt input.
- `require("codex").send_command(slash_cmd)` send slash command text.
- `require("codex").set_model()` send `/model`.
- `require("codex").show_status()` send `/status`.
- `require("codex").show_permissions()` send `/permissions`.
- `require("codex").compact()` send `/compact`.
- `require("codex").review(instructions)` send `/review`.
- `require("codex").show_diff()` send `/diff`.
- `require("codex").resume(opts)` resume (`opts.last` supports `--last`).
- `require("codex").send_selection(opts)` send visual/range selection.
- `require("codex").add_file(path)` send `/mention` for a file path.
- `require("codex").is_running()` check whether active session is alive.
- `require("codex").get_config()` return resolved config snapshot.

For command and component interaction details, see
[`docs/command-interactions.md`](docs/command-interactions.md).

## Providers

`auto` (default) prefers `snacks` when available, falls back to `native`. See
[docs/architecture.md](docs/architecture.md) for the full provider interface and
implementation details.

## Development

See [docs/contributing.md](docs/contributing.md) for setup, testing, formatting,
linting, and code style guidelines.
