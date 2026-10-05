local function feed_terminal_keys(keys)
  local encoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(encoded, "n", false)
end

return {
  toggle = function()
    ---@type codex.Api
    local codex = require("codex")
    codex.session.toggle()
  end,

  clear_input = function()
    ---@type codex.Api
    local codex = require("codex")
    codex.input.clear()
  end,

  unfocus = function()
    ---@type codex.Api
    local codex = require("codex")
    codex.session.unfocus()
  end,

  close = function()
    vim.schedule(function()
      ---@type codex.Api
      local codex = require("codex")
      codex.session.close()
    end)
  end,

  nav_left = function()
    feed_terminal_keys("<C-\\><C-n><C-w>h")
  end,

  nav_down = function()
    feed_terminal_keys("<C-\\><C-n><C-w>j")
  end,

  nav_up = function()
    feed_terminal_keys("<C-\\><C-n><C-w>k")
  end,

  nav_right = function()
    feed_terminal_keys("<C-\\><C-n><C-w>l")
  end,
}
