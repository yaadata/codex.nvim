<p align="center">
    <img src="logo.svg" width="288" alt="codex.nvim logo" />
</p>

<div align="center" >

# CODEX.NVIM

<i>Bringing Coding Harness' to Neovim </i>

![pi within neovim session](images/pi_harness.png "codex.nvim")
![codex within neovim session](images/codex_harness.jpeg "codex.nvim")

| **Primary home:** [Codeberg](https://codeberg.org/yaadata/codex.nvim) | Mirrored on [GitHub](https://github.com/yaadata/codex.nvim) |
| :-------------------------------------------------------------------: | :---------------------------------------------------------: |

</div>

## ✨ Features

- 🧩 Compose workflows with session, input, prompt-builder, and log APIs.
- 🔌 Use `codex.builtin` for agent-specific mentions, slash commands, skills,
  and resume flows.
- 🌱 Use the native terminal provider or `snacks`, lazy-load on commands, and
  configure terminal-local keymaps.
- 📚 Use `:help codex.nvim` for configuration, commands, and keymap examples.

## Requirements

- Neovim >= 0.12.0
- `codex` available on your `PATH` (or configure `launch.cmd`)

> [!CAUTION]
> You are reading the `main` branch README. Install details may differ from
> tagged releases. The current v2 beta release tag is
> [`2.0.0-beta.2`](https://codeberg.org/yaadata/codex.nvim/src/tag/v2.0.0-beta.2).
> For version-accurate instructions, read the README for your target tag from
> [Codeberg releases](https://codeberg.org/yaadata/codex.nvim/releases).

## Install

```lua
{
  url = "https://codeberg.org/yaadata/codex.nvim.git",
  version = "2.0.0-beta.2",
  lazy = false,
  cmd = {
    "Codex",
    "CodexFocus",
    "CodexTeardown",
    "CodexClearInput",
    "CodexSendSelection",
    "CodexSendFile",
    "CodexMentionFile",
    "CodexMentionDirectory",
  },
  opts = {},
  config = function(_, opts)
    require("codex").setup(opts)
  end,
}
```

This configuration supports `:Lazy reload codex.nvim`. Reload closes any active
Codex terminal.

## Configuration

See `:help codex-nvim-config` for defaults and terminal options.

```lua
local codex = require("codex")
codex.setup({
  profiles = {
    default = {},
    home = { launch = { cwd = vim.fn.expand("~") } },
  },
})
```

Later, call `require("codex").set_profile("home")` to switch profiles without
stopping existing sessions.

Named profiles inherit `launch` (`cmd`, `cwd`, `env`), `auto_start`, and `terminal`
from `default`. Global `keymaps` are per profile and do not inherit. Only the
selected profile auto-starts, without taking focus.

## Usage

Common entry points:

- `:Codex` toggles the terminal; `:Codex!` opens and focuses it.
- `:CodexSendSelection` sends the active visual selection.
- `:CodexSendFile` sends the current buffer as an ACP file reference.
- `:CodexMentionFile [path]` and `:CodexMentionDirectory [path]` send
  `/mention`.

For Lua workflows, use [`require("codex")`](lua/codex/init.lua) for `session`,
`input`, `prompt_builder`, and `logs`. Use
[`require("codex.builtin")`](lua/codex/builtin/init.lua) for agent-specific
workflows.

Example:

```lua
local prompt = require("codex").prompt_builder
prompt.clear()
prompt.add("Review this file: ")
local ok, err = prompt.add_file()
if not ok then
  vim.notify(err, vim.log.levels.ERROR)
  return
end
prompt.send() -- paste the draft without pressing Enter
```

Open `:help codex.nvim` for configuration, commands, and keymaps. If help is
missing after a raw install, run `:helptags {path-to-codex.nvim}/doc`. Plugin
managers usually generate tags automatically.

## Developer Docs

- [doc/architecture.md](doc/architecture.md)
- [doc/contributing.md](doc/contributing.md)
- [doc/troubleshooting.md](doc/troubleshooting.md)
