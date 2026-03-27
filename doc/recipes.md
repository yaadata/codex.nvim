# Recipes

Most user-facing examples now live in `:help codex.nvim`, especially:

- `|codex-nvim-install|`
- `|codex-nvim-setup|`
- `|codex-nvim-keymaps|`
- `|codex-nvim-examples|`

Use the helpfile for the lazy.nvim setup example, terminal keymap examples, and
slash-command examples.

This Markdown page is kept for integration-specific examples that are easier to
scan outside the helpfile.

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
