# Recipes

This page collects copy-pasteable `codex.nvim` configuration patterns and
workflow examples.

## Table of contents

- [Example Lazy Config](#example-lazy-config)
- [Execute slash commands](#execute-slash-commands)
  - [Execute from user commands](#execute-from-user-commands)
  - [Execute from keymaps](#execute-from-keymaps)
- [Integrations](#integrations)
  - [`oil.nvim`](#oilnvim)

## Example Lazy Config

Config showcases

- Creating custom keymaps (top-level and terminal level)
- Usage of various plugin Lua APIs.
- Creating a custom Neovim User Command

<details>
<summary>Config </summary>

```lua
return {
  url = "https://codeberg.org/yaadata/codex.nvim.git",
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
  keys = {
    {
      "<leader>aot",
      function()
        require("codex").toggle()
      end,
      desc = "Codex: Toggle terminal",
      mode = { "n", "v" },
    },
    {
      "<leader>aoo",
      function()
        require("codex").open(true)
      end,
      desc = "Codex: Open and focus",
      mode = { "n", "v" },
    },
    {
      "<leader>aof",
      function()
        require("codex").focus()
      end,
      desc = "Codex: Focus terminal",
      mode = { "n", "v" },
    },
    {
      "<leader>aox",
      function()
        require("codex").close()
      end,
      desc = "Codex: Close session",
      mode = { "n", "v" },
    },
    {
      "<leader>aos",
      function()
        require("codex").send_file()
      end,
      desc = "Codex: Add current buffer",
      mode = "n",
    },
    {
      "<leader>aos",
      function()
        require("codex").send_selection()
      end,
      desc = "Codex: Send selection",
      mode = "x",
    },
    {
      "<leader>aom",
      function()
        local codex = require("codex")
        codex.mention_file()
        vim.defer_fn(function()
          codex.unfocus()
        end, 350)
      end,
      desc = "Codex: Mention current file",
      mode = { "n", "v" },
    },
    {
      "<leader>aoM",
      function()
        local codex = require("codex")
        codex.mention_directory()
        vim.defer_fn(function()
          if codex.is_focused() then
            codex.unfocus()
          end
        end, 350)
      end,
      desc = "Codex: Mention current directory",
      mode = { "n", "v" },
    },
    {
      "<leader>aoi",
      function()
        require("codex").execute_slash_command({ command = "status" })
      end,
      desc = "Codex: Show status",
      mode = { "n", "v" },
    },
    {
      "<leader>aor",
      function()
        require("codex").resume()
      end,
      desc = "Codex: Resume session",
      mode = { "n", "v" },
    },
    {
      "<leader>aoc",
      function()
        local codex = require("codex")
        codex.execute_slash_command({ command = "copy" })
        vim.defer_fn(function()
          if codex.is_focused() then
            codex.unfocus()
          end
        end, 300)
      end,
      desc = "Codex: Copy Latest Response",
      mode = { "n", "v" },
    },
  },
  opts = {
    launch = {
      cmd = "codex",
      args = {},
      env = {},
      auto_start = false,
      cwd = nil,
    },
    log = {
      level = "debug",
      verbose = true,
    },
    terminal = {
      provider = "auto",
      auto_close = true,
      startup = {
        timeout_ms = 2000,
        retry_interval_ms = 50, -- retry interval while waiting for startup readiness
        grace_ms = 800, -- minimum delay after terminal open before first send
      },
      provider_opts = {
        snacks = {
          win = {
            title = " Openai Codex ",
            position = "right",
            title_pos = "center",
            width = 0.25,
            wo = {
              winbar = " Openai Codex ",
            },
            border = "rounded",
            footer_keys = true,
          },
        },
        native = {
          window = "vsplit",
          vsplit = {
            side = "right", -- left | right
            size_pct = 20, -- 10-90
          },
          hsplit = {
            side = "bottom", -- top | bottom
            size_pct = 30, -- 10-90
          },
        },
      },
    },
  },
  config = function(_, opts)
    local km = require("codex.keymaps").builtins
    opts.terminal.keymaps = {
      ["<C-c>"] = { mode = { "t", "n" }, action = km.toggle },
      ["<C-n>"] = {
        mode = { "t", "n" },
        action = function()
          vim.cmd("stopinsert")
        end,
        desc = "normal mode",
      },
      ["<M-BS>"] = { mode = { "t", "n" }, action = km.clear_input },
      ["<C-g>"] = { mode = { "t", "n" }, action = km.unfocus },
      ["<C-x>"] = { mode = { "t", "n" }, action = km.close },
      ["<C-h>"] = { mode = { "t", "n" }, action = km.nav_left },
      ["<C-j>"] = { mode = { "t", "n" }, action = km.nav_down },
      ["<C-k>"] = { mode = { "t", "n" }, action = km.nav_up },
      ["<C-l>"] = { mode = { "t", "n" }, action = km.nav_right },
    }
    require("codex").setup(opts)
  end,
}
```

</details>

## Execute slash commands

### Execute from user commands

The following commands were previously built-in and can be recreated as
user-defined commands using execute_slash_command

```lua
local codex = require("codex")

vim.api.nvim_create_user_command("CodexModel", function()
  codex.execute_slash_command({ command = "model" })
end, {
  desc = "Open Codex model picker",
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexStatus", function()
  codex.execute_slash_command({ command = "status" })
end, {
  desc = "Show Codex status summary",
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexPermissions", function()
  codex.execute_slash_command({ command = "permissions" })
end, {
  desc = "Open Codex permissions selector",
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexCompact", function()
  codex.execute_slash_command({ command = "compact" })
end, {
  desc = "Run Codex /compact in the active session",
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexReview", function(opts)
  codex.execute_slash_command({
    command = "review",
    args = opts.args,
  })
end, {
  desc = "Run Codex /review (or /review <instructions>)",
  nargs = "*",
})

vim.api.nvim_create_user_command("CodexDiff", function()
  codex.execute_slash_command({ command = "diff" })
end, {
  desc = "Run Codex /diff in the active session",
  nargs = 0,
})
```

`execute_slash_command` accepts an opts table:

- `command` is required and may be provided with or without a leading `/`.
- `args` is optional; empty or whitespace-only values are ignored.

This API uses the same wrapper flow as built-in mentions and in-process
`resume`: it captures the current prompt when possible, saves it to the unnamed
register, clears the terminal input, sends the slash command atomically, and
submits it.

### Execute from keymaps

```lua
vim.keymap.set({ "n", "v" }, "<leader>om", function()
  require("codex").execute_slash_command({ command = "model" })
end, {
  desc = "Codex: Model picker",
})

vim.keymap.set({ "n", "v" }, "<leader>oi", function()
  require("codex").execute_slash_command({ command = "status" })
end, {
  desc = "Codex: Show status",
})

vim.keymap.set({ "n", "v" }, "<leader>op", function()
  require("codex").execute_slash_command({ command = "permissions" })
end, {
  desc = "Codex: Permissions",
})

vim.keymap.set({ "n", "v" }, "<leader>oc", function()
  require("codex").execute_slash_command({ command = "compact" })
end, {
  desc = "Codex: Compact context",
})

vim.keymap.set({ "n", "v" }, "<leader>oR", function()
  require("codex").execute_slash_command({ command = "review" })
end, {
  desc = "Codex: Review changes",
})

vim.keymap.set({ "n", "v" }, "<leader>od", function()
  require("codex").execute_slash_command({ command = "diff" })
end, {
  desc = "Codex: Show diff",
})
```

## Integrations

### `oil.nvim`

This example shows how to trigger `codex.nvim` actions from
[`oil.nvim`](https://github.com/stevearc/oil.nvim) keymaps while browsing files
inside Oil's floating window.

<details>

<summary>Config </summary>

```lua
return {
  "stevearc/oil.nvim",
  opts = {},
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    { "echasnovski/mini.icons", opts = {} },
  },
  config = function()
    local oil = require("oil")
    local function warn(msg)
      vim.notify(msg, vim.log.levels.WARN)
    end

    oil.setup({
      keymaps = {
        ["<A-m>"] = {
          desc = "Codex: Mention selected file",
          mode = "n",
          callback = function()
            local entry = oil.get_cursor_entry()
            local dir = oil.get_current_dir(0)
            if not entry or not dir then
              warn("Oil: unable to resolve selected file")
              return
            end
            if entry.type == "directory" then
              warn("Oil: selected entry is a directory; use Alt+Shift+M")
              return
            end

            local ok, err = require("codex").mention_file(dir .. entry.name)
            if not ok then
              warn(string.format("Oil: failed to mention file (%s)", err or "unknown error"))
              return
            end

            vim.defer_fn(function()
              oil.toggle_float(dir)
            end, 500)
          end,
        },
        ["<A-S-m>"] = {
          desc = "Codex: Mention current directory",
          mode = "n",
          callback = function()
            local dir = oil.get_current_dir(0)
            if not dir then
              warn("Oil: unable to resolve current directory")
              return
            end

            local ok, err = require("codex").mention_directory(dir)
            if not ok then
              warn(string.format("Oil: failed to mention directory (%s)", err or "unknown error"))
              return
            end

            vim.defer_fn(function()
              oil.toggle_float(dir)
            end, 500)
          end,
        },
        ["<A-s>"] = {
          desc = "Codex: send selected file @reference",
          mode = "n",
          callback = function()
            local entry = oil.get_cursor_entry()
            local dir = oil.get_current_dir(0)
            if not entry or not dir then
              warn("Oil: unable to resolve selected file")
              return
            end
            if entry.type == "directory" then
              warn("Oil: selected entry is a directory; use Alt+Shift+M")
              return
            end

            local fp = dir .. entry.name
            local ok, err = require("codex").send_file({ path = fp, focus = false })
            if not ok then
              warn(string.format("Oil: failed to send file reference (%s)", err or "unknown error"))
              return
            end

            vim.notify(string.format("Sent @%s to codex.nvim", fp))
          end,
        },
      },
    })
  end,
}
```

</details>
