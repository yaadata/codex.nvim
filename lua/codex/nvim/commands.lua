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

  vim.api.nvim_create_user_command("CodexSend", function(opts)
    local codex = require("codex")
    codex.send_selection({
      line1 = opts.line1,
      line2 = opts.line2,
    })
  end, {
    desc = "Send visual selection to Codex with file path and line range",
    nargs = 0,
    range = true,
  })

  vim.api.nvim_create_user_command("CodexAdd", function(opts)
    local codex = require("codex")
    local path = opts.args
    if path == "" then
      path = nil
    end
    codex.add_file(path)
  end, {
    desc = "Add file context to Codex via /mention",
    nargs = "?",
    complete = "file",
  })
end

return M
