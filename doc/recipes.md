# Recipes

- [Context](#context)
- [Lua API Recipes](#lua-api-recipes)
  - [Disable spellcheck in Codex terminal buffers](#disable-spellcheck)
  - [Send arbitrary text from a normal-mode keymap](#send-arbitrary-text)
  - [Prompt for text, then send it to Codex](#prompt-and-send)
  - [Send a visual selection, then add a follow-up instruction](#send-selection-follow-up)
  - [Copy the current prompt input](#copy-prompt-input)
  - [Copy the latest Codex response with `/copy`](#copy-latest-response)
- [Integrations](#integrations)
  - [`oil.nvim`](#oilnvim)

### Context

Most user-facing examples now live in `:help codex.nvim`, especially:

- `|codex-nvim-install|`
- `|codex-nvim-setup|`
- `|codex-nvim-keymaps|`
- `|codex-nvim-examples|`

Use the helpfile for the lazy.nvim setup example, terminal keymap examples, and
slash-command examples.

This Markdown page is kept for integration-specific examples that are easier to
scan outside the helpfile.

## Lua API Recipes

These recipes build custom editor keymaps on top of the public Lua API
documented in `:help codex.nvim`, especially `|codex-nvim-api-send|`,
`|codex.execute_slash_command|`, `|codex.copy_input|`, and
`|codex-nvim-keymaps|`.

<a id="disable-spellcheck"></a>

### Disable spellcheck in Codex terminal buffers

Use lifecycle hooks when you want editor-local behavior applied whenever a Codex
terminal is opened or restored.

```lua
require("codex").setup({
  hooks = {
    on_terminal_open = function(ctx)
      if ctx.bufnr then
        vim.bo[ctx.bufnr].spell = false
      end
    end,
    on_terminal_restore = function(ctx)
      if ctx.bufnr then
        vim.bo[ctx.bufnr].spell = false
      end
    end,
  },
})
```

<a id="send-arbitrary-text"></a>

### Send arbitrary text from a normal-mode keymap

Use `require("codex").send()` when you want a keymap to write text directly into
the active Codex prompt.

```lua
vim.keymap.set("n", "<leader>aw", function()
  local ok, err = require("codex").send("Write a failing test for the current buffer")
  if not ok then
    vim.notify(
      ("Codex: failed to send text%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
  end
end, { desc = "Codex: Write a test" })
```

<a id="prompt-and-send"></a>

### Prompt for text, then send it to Codex

This pattern is useful when the prompt should be decided at runtime instead of
hardcoded into the keymap.

```lua
vim.keymap.set("n", "<leader>ap", function()
  vim.ui.input({ prompt = "Send to Codex: " }, function(input)
    if not input or input == "" then
      return
    end

    local ok, err = require("codex").send(input)
    if not ok then
      vim.notify(
        ("Codex: failed to send text%s"):format(err and (": " .. err) or ""),
        vim.log.levels.ERROR
      )
    end
  end)
end, { desc = "Codex: Prompt and send" })
```

<a id="send-selection-follow-up"></a>

### Send a visual selection, then add a follow-up instruction

This mirrors the pattern from a real user config: send the selected code first,
append an instruction, then submit the prompt explicitly.

```lua
vim.keymap.set("x", "<leader>ar", function()
  local codex = require("codex")
  local ok, err = codex.send_selection()
  if not ok then
    vim.notify(
      ("Codex: failed to collect selection%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
    return
  end

  ok, err = codex.send("$code-review the current selection ")
  if not ok then
    vim.notify(
      ("Codex: failed to send follow-up text%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
    return
  end

  ok, err = codex.submit_input()
  if not ok then
    vim.notify(
      ("Codex: failed to submit input%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
  end
end, { desc = "Codex: Review selection" })
```

<a id="copy-prompt-input"></a>

### Copy the current prompt input

`copy_input()` copies whatever is currently typed in the Codex prompt into the
unnamed register.

```lua
vim.keymap.set("n", "<leader>ayi", function()
  local ok, err = require("codex").copy_input()
  if not ok then
    vim.notify(
      ("Codex: failed to copy prompt input%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
  end
end, { desc = "Codex: Copy prompt input" })
```

<a id="copy-latest-response"></a>

### Copy the latest Codex response with `/copy`

Use the slash-command wrapper when you want the same flow as typing `/copy`
inside the terminal.

```lua
vim.keymap.set("n", "<leader>ayr", function()
  local codex = require("codex")
  local ok, err = codex.execute_slash_command({ command = "copy" })
  if not ok then
    vim.notify(
      ("Codex: failed to copy latest response%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
    return
  end

  vim.defer_fn(function()
    if codex.is_focused() then
      codex.unfocus()
    end
  end, 300)
end, { desc = "Codex: Copy latest response" })
```

## Integrations

### `oil.nvim`

This example shows how to trigger `codex.nvim` actions from
[`oil.nvim`](https://github.com/stevearc/oil.nvim) keymaps while browsing files
inside Oil's floating window.

<details>
<summary>Config</summary>

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
