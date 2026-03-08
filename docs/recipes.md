# Recipes

This page collects copy-pasteable `codex.nvim` configuration patterns and
workflow examples.

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
