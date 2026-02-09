local M = {}

local levels = { debug = 0, info = 1, warn = 2, error = 3 }
local vim_levels = {
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

M._level = levels.warn

---@param name codex.LogLevel|string
---@return nil
function M.set_level(name)
  M._level = levels[name] or levels.warn
end

---@param level_name codex.LogLevel
---@param msg string
---@param ... any
---@return nil
local function log(level_name, msg, ...)
  if levels[level_name] < M._level then
    return
  end
  local formatted = string.format(msg, ...)
  vim.notify("[codex] " .. formatted, vim_levels[level_name])
end

---@param msg string
---@param ... any
---@return nil
function M.debug(msg, ...)
  log("debug", msg, ...)
end

---@param msg string
---@param ... any
---@return nil
function M.info(msg, ...)
  log("info", msg, ...)
end

---@param msg string
---@param ... any
---@return nil
function M.warn(msg, ...)
  log("warn", msg, ...)
end

---@param msg string
---@param ... any
---@return nil
function M.error(msg, ...)
  log("error", msg, ...)
end

return M
