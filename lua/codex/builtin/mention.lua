local M = {}
local slash = require("codex.builtin.slash_command")
local codex_path = require("codex.context.path")
local logger = require("codex.logger")

---@param path string?
---@return codex.Error
function M.file(path)
  local resolved_path = path
  if resolved_path == nil then
    resolved_path = vim.fn.expand("%:p")
  end

  if not resolved_path or resolved_path == "" then
    local err = "current buffer has no file path"
    logger.error("failed to mention file: %s", err)
    return err
  end

  resolved_path = codex_path.to_relative(vim, resolved_path)
  return slash.execute({
    command = "mention",
    args = resolved_path,
  })
end

---@param path string?
---@return codex.Error
function M.directory(path)
  local resolved_path = path
  if resolved_path == nil then
    resolved_path = vim.fn.expand("%:p:h")
  end

  if not resolved_path or resolved_path == "" then
    local err = "current buffer has no directory path"
    logger.error("failed to mention directory: %s", err)
    return err
  end
  resolved_path = codex_path.to_relative(vim, resolved_path)
  resolved_path = codex_path.ensure_dir_trailing_separator(vim, resolved_path)
  return slash.execute({
    command = "mention",
    args = resolved_path,
  })
end

return M
