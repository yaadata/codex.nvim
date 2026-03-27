# <p style="text-align:center;">codex.nvim</p>

<p style="text-align:center;">
Neovim plugin for running the Codex CLI in an embedded terminal.
</p>

- **Primary home:** [Codeberg](https://codeberg.org/yaadata/codex.nvim)
- Mirrored on [GitHub](https://github.com/yaadata/codex.nvim)

## Requirements

- Neovim >= 0.11.0
- `codex` available on your `PATH` (or configure `launch.cmd`)

> [!CAUTION]
> You are reading the `main` branch README. Install and configuration details
> may differ from tagged releases. The current latest release tag is
> [`v0.6.1`](https://codeberg.org/yaadata/codex.nvim/src/tag/v0.6.1). For
> version-accurate instructions, read the README for your target tag from
> [Codeberg releases](https://codeberg.org/yaadata/codex.nvim/releases).

## Install

```lua
{
  url = "https://codeberg.org/yaadata/codex.nvim.git",
  version = "0.6.1",
  cmd = {
    "Codex",
    "CodexFocus",
    "CodexClose",
    "CodexClearInput",
    "CodexSendSelection",
    "CodexSendFile",
    "CodexMentionFile",
    "CodexMentionDirectory",
    "CodexResume",
  },
  opts = {},
  config = function(_, opts)
    require("codex").setup(opts)
  end,
}
```

## Configuration

Use this table as your lazy.nvim plugin `opts` value:

<details>
<summary>Show default <code>opts</code> table</summary>

```lua
opts = {
  launch = {
    cmd = "codex",
    args = {},
    env = {},
    auto_start = true,
    cwd = nil,
  },
  log = {
    level = "warn",
    verbose = false,
  },
  terminal = {
    provider = "auto", -- auto | snacks | native
    provider_opts = {
      native = {
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
      snacks = {
        -- pass-through for snacks.terminal(..., opts)
      },
    },
    auto_close = true, -- close terminal buffer automatically when process exits
    startup = {
      timeout_ms = 2000, -- max time to wait for startup readiness before dropping queued sends
      retry_interval_ms = 50, -- retry interval while waiting for startup readiness
      grace_ms = 800, -- minimum delay after terminal open before first send
    },
    keymaps = {}, -- terminal-local keymaps are opt-in; no defaults are registered
  },
}
```

</details>

## Commands

- `:Codex` toggles the Codex terminal
- `:Codex!` force-opens and focuses the Codex terminal
- `:CodexFocus` focuses the terminal (opens it if needed)
- `:CodexClose` closes the active Codex terminal session
- `:CodexClearInput` clears the active Codex terminal input line
- `:CodexSendSelection` sends the active visual selection with path and range
  context.
- `:CodexSendFile` sends current buffer path as ACP file reference (`@path`).
- `:CodexMentionFile [path]` sends `/mention` for a file path, normalized to
  cwd-relative.
- `:CodexMentionDirectory [path]` sends `/mention` for a directory path,
  normalized to cwd-relative and forced to end with a path separator.
- `:CodexResume[!]` resumes in-process or launches `codex resume` (`!` uses
  `--last` when launching).

For detailed command behavior and component interactions, see
[`docs/command-interactions.md`](docs/command-interactions.md).

When using lazy.nvim with `cmd` + `opts`, prefer wiring setup explicitly in
`config` and passing lazy's resolved opts through:

```lua
config = function(_, opts)
  require("codex").setup(opts)
end
```

The `cmd` list still ensures first-use lazy loading when a `:Codex*` command is
run.

## Keymaps

codex.nvim does not register global keymaps in `setup()`. Define global mappings
in your lazy.nvim plugin spec `keys`:

<details>
<summary>Show lazy <code>keys</code> table</summary>

```lua
{
  url = "https://codeberg.org/yaadata/codex.nvim.git",
  version = "0.6.1",
  main = "codex",
  cmd = {
    "Codex",
    "CodexFocus",
    "CodexClose",
    "CodexClearInput",
    "CodexSendSelection",
    "CodexSendFile",
    "CodexMentionFile",
    "CodexMentionDirectory",
    "CodexResume",
  },
  opts = {},
  config = function(_, opts)
    require("codex").setup(opts)
  end,
  keys = {
    {
      "<leader>ot",
      function()
        require("codex").toggle()
      end,
      desc = "Codex: Toggle terminal",
      mode = { "n", "v" },
    },
    {
      "<leader>os",
      function()
        require("codex").send_file()
      end,
      desc = "Codex: Send @{file_path}",
      mode = "n",
    },
    {
      "<leader>os",
      function()
        require("codex").send_selection()
      end,
      desc = "Codex: Send selection",
      mode = "x",
    },
    {
      "<leader>om",
      function()
        require("codex").mention_file()
      end,
      desc = "Codex: Mention current file",
      mode = { "n", "v" },
    },
    {
      "<leader>oM",
      function()
        require("codex").mention_directory()
      end,
      desc = "Codex: Mention current directory",
      mode = { "n", "v" },
    },
    {
      "<leader>or",
      function()
        require("codex").resume()
      end,
      desc = "Codex: Resume session",
      mode = { "n", "v" },
    },
  },
}
```

</details>

Set `vim.g.mapleader` before plugin setup so `<leader>` expands as expected.

Terminal-local keymaps inside the Codex terminal buffer are configured
separately via `terminal.keymaps`:

```lua
local km = require("codex.keymaps").builtins

require("codex").setup({
  log = {
    level = "warn",
    verbose = false,
  },
  terminal = {
    keymaps = {
      ["<C-c>"] = { mode = { "t", "n" }, action = km.toggle },
      ["<M-BS>"] = { mode = { "t", "n" }, action = km.clear_input },
      ["<C-g>"] = { mode = { "t", "n" }, action = km.unfocus },
      ["<C-x>"] = { mode = { "t", "n" }, action = km.close },
      ["<A-h>"] = { mode = { "t", "n" }, action = km.nav_left },
      ["<A-j>"] = { mode = { "t", "n" }, action = km.nav_down },
      ["<A-k>"] = { mode = { "t", "n" }, action = km.nav_up },
      ["<A-l>"] = { mode = { "t", "n" }, action = km.nav_right },
    },
  },
})
```

Each entry uses `{ mode, action, desc? }`, where:

- `mode` is a string or list of modes accepted by `vim.keymap.set`.
- `action` is a function (for builtins, use
  `require("codex.keymaps").builtins`).
- `desc` is optional for builtin actions (auto-filled), required for custom
  actions.

`terminal.auto_close` controls whether provider windows auto-close only after
the terminal process exits.

## Providers

`auto` (default) prefers `snacks` when available, falls back to `native`. See
[docs/architecture.md](docs/architecture.md) for the full provider interface and
implementation details.

## Lua API

The authoritative Lua API reference lives in [`docs/api.md`](docs/api.md).

For `:Codex*` command behavior and component interaction details, see
[`docs/command-interactions.md`](docs/command-interactions.md).

## Recipes

See [`docs/recipes.md`](docs/recipes.md) for copy-pasteable configuration
patterns, workflow examples, integration with other plugins etc.

## Development

See [docs/contributing.md](docs/contributing.md) for setup, testing, formatting,
linting, and code style guidelines.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for logging-focused
debugging steps and issue report guidance.
