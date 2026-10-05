local M = {}
local CTRL_V = string.char(22)
local COMMAND_NAMES = {
  "Codex",
  "CodexFocus",
  "CodexClose",
  "CodexClearInput",
  "CodexSendSelection",
  "CodexSendFile",
  "CodexMentionFile",
  "CodexMentionDirectory",
}

--- Return the two line numbers in ascending order.
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

--- Infer the visual mode when the command range matches the visual marks.
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

--- Build visual-selection opts for the command, or reject non-visual use.
---@param opts codex.UserCommandOpts
---@return codex.SelectionOpts|nil
local function resolve_selection_command_opts(opts)
  local visual_mode = resolve_visual_mode(opts)
  if visual_mode == nil then
    vim.notify(
      "[codex] :CodexSendSelection is only available from visual mode",
      vim.log.levels.ERROR
    )
    return nil
  end

  return {
    line1 = opts.line1,
    line2 = opts.line2,
    visual_mode = visual_mode,
  }
end

--- Register all :Codex* user commands.
---@param codex codex.Api
---@return nil
function M.register(codex)
  ---@param opts codex.UserCommandOpts
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

  vim.api.nvim_create_user_command("CodexClose", function()
    codex.session.close()
  end, {
    desc = "Close the active Codex terminal session",
    nargs = 0,
  })

  vim.api.nvim_create_user_command("CodexClearInput", function()
    codex.input.clear()
  end, {
    desc = "Clear the active Codex terminal input line",
    nargs = 0,
  })

  ---@param opts codex.UserCommandOpts
  vim.api.nvim_create_user_command("CodexSendSelection", function(opts)
    local selection_opts = resolve_selection_command_opts(opts)
    if selection_opts ~= nil then
      codex.prompt_builder.clear()
      codex.prompt_builder.add_selection(selection_opts)
      codex.prompt_builder.send()
    end
  end, {
    desc = "Send visual selection to Codex with file path and line range",
    nargs = 0,
    range = true,
  })

  vim.api.nvim_create_user_command("CodexSendFile", function()
    codex.prompt_builder.clear()
    codex.prompt_builder.add_file()
    codex.prompt_builder.send()
  end, {
    desc = "Send current buffer path to Codex as ACP reference",
    nargs = 0,
  })

  ---@param opts codex.UserCommandOpts
  vim.api.nvim_create_user_command("CodexMentionFile", function(opts)
    local builtin = require("codex.builtin")
    ---@type string|nil
    local path = opts.args
    if path == "" then
      path = nil
    end
    builtin.mention_file(path)
  end, {
    desc = "Mention a file in Codex via /mention",
    nargs = "?",
    complete = "file",
  })

  ---@param opts codex.UserCommandOpts
  vim.api.nvim_create_user_command("CodexMentionDirectory", function(opts)
    local builtin = require("codex.builtin")
    ---@type string|nil
    local path = opts.args
    if path == "" then
      path = nil
    end
    builtin.mention_directory(path)
  end, {
    desc = "Mention a directory in Codex via /mention",
    nargs = "?",
    complete = "dir",
  })
end

--- Unregister all :Codex* user commands owned by the plugin.
---@return nil
function M.unregister()
  for _, name in ipairs(COMMAND_NAMES) do
    pcall(vim.api.nvim_del_user_command, name)
  end
end

---@type codex.Commands
return M
