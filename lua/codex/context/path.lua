local M = {}

--- Convert an absolute file path to a cwd-relative path via fnamemodify.
---@param vim_api table|nil
---@param filepath string
---@return string
function M.to_relative(vim_api, filepath)
  vim_api = vim_api or vim
  if filepath == "" then
    return filepath
  end

  local ok, relative_path = pcall(vim_api.fn.fnamemodify, filepath, ":.")
  if ok and type(relative_path) == "string" and relative_path ~= "" then
    return relative_path
  end

  return filepath
end

return M
