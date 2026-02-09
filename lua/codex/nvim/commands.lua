local M = {}
local CTRL_V = string.char(22)

---@param line1 integer
---@param line2 integer
---@return integer
---@return integer
local function normalize_lines(line1, line2)
  if line1 <= line2 then
    return line1, line2
  end
  return line2, line1
end

---@param opts codex.UserCommandOpts
---@return string|nil
local function resolve_visual_mode(opts)
  if not opts.range or opts.range <= 0 then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local start_mark = vim.api.nvim_buf_get_mark(bufnr, "<")
  local end_mark = vim.api.nvim_buf_get_mark(bufnr, ">")
  if start_mark[1] <= 0 or end_mark[1] <= 0 then
    return nil
  end

  local range_start, range_end = normalize_lines(opts.line1, opts.line2)
  local mark_start, mark_end = normalize_lines(start_mark[1], end_mark[1])
  if range_start ~= mark_start or range_end ~= mark_end then
    return nil
  end

  local ok, mode = pcall(vim.fn.visualmode, 1)
  if not ok then
    return nil
  end
  if mode == "v" or mode == "V" or mode == CTRL_V then
    return mode
  end
  return nil
end

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

  vim.api.nvim_create_user_command("CodexClose", function()
    local codex = require("codex")
    codex.close()
  end, {
    desc = "Close the active Codex terminal session",
    nargs = 0,
  })

  ---@param opts codex.UserCommandOpts
  vim.api.nvim_create_user_command("CodexSend", function(opts)
    local codex = require("codex")
    local selection_opts = {
      line1 = opts.line1,
      line2 = opts.line2,
    }
    local visual_mode = resolve_visual_mode(opts)
    if visual_mode ~= nil then
      selection_opts.visual_mode = visual_mode
    end
    codex.send_selection(selection_opts)
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
