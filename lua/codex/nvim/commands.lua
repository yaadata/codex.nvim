local M = {}

---@return nil
function M.register()
  ---@param opts codex.UserCommandOpts
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

  ---@param opts codex.UserCommandOpts
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

  ---@param opts codex.UserCommandOpts
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

  ---@param opts codex.UserCommandOpts
  vim.api.nvim_create_user_command("CodexResume", function(opts)
    local codex = require("codex")
    codex.resume({ last = opts.bang })
  end, {
    desc = "Resume Codex session picker (use ! to launch with --last when needed)",
    nargs = 0,
    bang = true,
  })

  vim.api.nvim_create_user_command("CodexModel", function()
    local codex = require("codex")
    codex.set_model()
  end, {
    desc = "Open Codex model picker",
    nargs = 0,
  })

  vim.api.nvim_create_user_command("CodexStatus", function()
    local codex = require("codex")
    codex.show_status()
  end, {
    desc = "Show Codex status summary",
    nargs = 0,
  })

  vim.api.nvim_create_user_command("CodexPermissions", function()
    local codex = require("codex")
    codex.show_permissions()
  end, {
    desc = "Open Codex permissions selector",
    nargs = 0,
  })

  vim.api.nvim_create_user_command("CodexCompact", function()
    local codex = require("codex")
    codex.compact()
  end, {
    desc = "Run Codex /compact in the active session",
    nargs = 0,
  })

  ---@param opts codex.UserCommandOpts
  vim.api.nvim_create_user_command("CodexReview", function(opts)
    local codex = require("codex")
    local instructions = opts.args
    if instructions == "" then
      instructions = nil
    end
    codex.review(instructions)
  end, {
    desc = "Run Codex /review (or /review <instructions>)",
    nargs = "*",
  })

  vim.api.nvim_create_user_command("CodexDiff", function()
    local codex = require("codex")
    codex.show_diff()
  end, {
    desc = "Run Codex /diff in the active session",
    nargs = 0,
  })
end

return M
