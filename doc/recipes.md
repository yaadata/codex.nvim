# Recipes

- [Context](#context)
- [Custom Neovim Commands](#custom-neovim-commands)
- [Lua API Recipes](#lua-api-recipes)
  - [Disable spellcheck in Codex terminal buffers](#disable-spellcheck)
  - [Send arbitrary text from a normal-mode keymap](#send-arbitrary-text)
  - [Insert a skill invocation from a normal-mode keymap](#send-skill)
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

This Markdown page is kept for custom command patterns and integration-specific
examples that are easier to scan outside the helpfile.

<a id="custom-neovim-commands"></a>

## Custom Neovim Commands

`codex.nvim` does not register Neovim user commands (`:Codex*`) out of the box.
If you want ex-commands alongside (or instead of) keymaps, register your own
with `vim.api.nvim_create_user_command` on top of `require("codex")` and
`require("codex.builtin")`.

Define them in your Neovim config (for example inside your `lazy.nvim` `config`
function after `require("codex").setup(opts)`):

```lua
local codex = require("codex")
local builtin = require("codex.builtin")

-- Session lifecycle
vim.api.nvim_create_user_command("Codex", function(opts)
  if opts.bang then
    codex.session.open(true)
  else
    codex.session.toggle()
  end
end, {
  desc = "Toggle Codex terminal (use ! to force open and focus)",
  bang = true,
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexFocus", function()
  codex.session.focus()
end, {
  desc = "Focus the Codex terminal, starting it if needed",
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexTeardown", function()
  codex.session.teardown()
end, {
  desc = "Teardown the active Codex terminal session",
  nargs = 0,
})

-- Terminal input and prompt builder
vim.api.nvim_create_user_command("CodexClearInput", function()
  codex.input.clear()
end, {
  desc = "Clear the active Codex terminal input line",
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexSendFile", function()
  codex.prompt_builder.clear()
  local ok, err = codex.prompt_builder.add_file()
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  codex.prompt_builder.send()
end, {
  desc = "Send current buffer path to Codex as an @path reference",
  nargs = 0,
})

vim.api.nvim_create_user_command("CodexSendSelection", function(opts)
  if opts.range == 0 then
    vim.notify("CodexSendSelection requires a visual range", vim.log.levels.ERROR)
    return
  end
  codex.prompt_builder.clear()
  local ok, err = codex.prompt_builder.add_selection({
    line1 = opts.line1,
    line2 = opts.line2,
  })
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  codex.prompt_builder.send()
end, {
  desc = "Send visual selection range to Codex",
  nargs = 0,
  range = true,
})

-- Agent-specific builtins (Codex CLI)
vim.api.nvim_create_user_command("CodexMentionFile", function(opts)
  local path = opts.args ~= "" and opts.args or nil
  builtin.mention_file(path)
end, {
  desc = "Mention a file in Codex via /mention",
  nargs = "?",
  complete = "file",
})

vim.api.nvim_create_user_command("CodexMentionDirectory", function(opts)
  local path = opts.args ~= "" and opts.args or nil
  builtin.mention_directory(path)
end, {
  desc = "Mention a directory in Codex via /mention",
  nargs = "?",
  complete = "dir",
})

-- Slash-command wrappers
vim.api.nvim_create_user_command("CodexReview", function(opts)
  builtin.execute_slash_command({
    command = "review",
    args = opts.args,
  })
end, {
  desc = "Run /review (or /review <instructions>)",
  nargs = "*",
})
```

For more slash-command wrapper examples, see `|codex-nvim-examples|`.

## Lua API Recipes

These recipes build custom editor keymaps on top of the public Lua API
documented in `:help codex.nvim`, especially `|codex.prompt_builder.send|`,
`|codex.prompt_builder.add_skill|`, `|codex.builtin.execute_slash_command|`,
`|codex.input.copy|`, and `|codex-nvim-keymaps|`.

<a id="disable-spellcheck"></a>

### Disable spellcheck in Codex terminal buffers

Use lifecycle hooks when you want editor-local behavior applied whenever a Codex
terminal is opened or restored.

```lua
local function disable_spell(ctx)
  if type(ctx.winid) == "number" and vim.api.nvim_win_is_valid(ctx.winid) then
    vim.wo[ctx.winid].spell = false
    return
  end

  if type(ctx.bufnr) ~= "number" then
    return
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == ctx.bufnr then
      vim.wo[winid].spell = false
    end
  end
end
require("codex").setup({
  hooks = {
    on_terminal_open = disable_spell,
    on_terminal_restore = disable_spell,
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

<a id="send-skill"></a>

### Insert a skill invocation from a normal-mode keymap

Use `require("codex").send_skill()` to insert a skill invocation without
focusing Codex or submitting the prompt. Pass plugin-provided skills as separate
`plugin` and `name` fields; omit `plugin` for a standalone skill.

```lua
vim.keymap.set("n", "<leader>ac", function()
  local ok, err = require("codex").send_skill({
    plugin = "code",
    name = "comment",
  })
  if not ok then
    vim.notify(
      ("Codex: failed to insert skill%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
  end
end, { desc = "Codex: Insert comment skill" })
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
    local codex = require("codex")
    local ok, err = codex.prompt_builder.add(input)
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
  local ok, err = codex.prompt_builder.add_selection()
  if not ok then
    vim.notify(
      ("Codex: failed to collect selection%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
    return
  end

  ok, err = codex.prompt_builder.add("$code-review the current selection ")
  if not ok then
    vim.notify(
      ("Codex: failed to send follow-up text%s"):format(err and (": " .. err) or ""),
      vim.log.levels.ERROR
    )
    return
  end

  ok, err = codex.prompt_builder.submit()
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
    "yaadata/codex.nvim",
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

            local err = require("codex.builtin").mention_file(dir .. entry.name)
            if err ~= nil then
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

            local err = require("codex.builtin").mention_directory(dir)
            if err ~= nil then
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
            local codex = require("codex")
            local ok, err = codex.prompt_builder.add_file({
              path = fp,
            })
            if not ok then
              warn(string.format("Oil: failed to send file reference (%s)", err or "unknown error"))
              return
            end
            ok, err = codex.prompt_builder.send()
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
