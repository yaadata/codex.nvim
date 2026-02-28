local M = {}
local CTRL_V = string.char(22)

---Exit visual mode when currently in a visual variant.
---@param vim_api table|nil
---@return boolean exited True when Escape was sent successfully.
function M.exit_visual_mode_if_active(vim_api)
  vim_api = vim_api or vim
  local fn = vim_api.fn or {}
  local api = vim_api.api or {}

  if type(fn.mode) ~= "function" then
    return false
  end
  if type(api.nvim_replace_termcodes) ~= "function" or type(api.nvim_input) ~= "function" then
    return false
  end

  local ok_mode, mode = pcall(fn.mode, 1)
  if not ok_mode then
    return false
  end
  if mode ~= "v" and mode ~= "V" and mode ~= CTRL_V then
    return false
  end

  local ok_esc, esc = pcall(api.nvim_replace_termcodes, "<Esc>", true, false, true)
  if not ok_esc or type(esc) ~= "string" then
    return false
  end

  local ok_input = pcall(api.nvim_input, esc)
  return ok_input
end

return M
