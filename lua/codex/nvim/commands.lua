local M = {}

function M.register()
  vim.api.nvim_create_user_command("Codex", function(opts)
    local codex = require("codex")
    if opts.bang then
      codex.open(true)
    else
      codex.toggle()
    end
  end, {
    desc = "Toggle Codex terminal (use ! to force open and focus)",
    bang = true,
    nargs = 0,
  })

  vim.api.nvim_create_user_command("CodexFocus", function()
    local codex = require("codex")
    codex.focus()
  end, {
    desc = "Focus the Codex terminal, starting it if needed",
    nargs = 0,
  })
end

return M
