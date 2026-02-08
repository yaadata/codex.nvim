# codex.nvim

Neovim plugin for running the Codex CLI in an embedded terminal with a provider
abstraction.

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

## Providers

- `auto`: prefers `snacks` when available, falls back to `native`
- `snacks`: `snacks.nvim` terminal integration
- `native`: built-in `vim.fn.termopen` split terminal
- `external`: reserved stub provider
- `none`: no-op provider for tests/headless flows

## Development

```sh
mise exec -- just test
mise exec -- just fmt-check
mise exec -- just lint
```
