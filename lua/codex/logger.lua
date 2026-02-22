--- Logging facade that delegates to `vim.notify` with level filtering.
---
--- The default level is `warn`, so only `warn` and `error` messages are
--- shown unless explicitly lowered via `set_level`.
local M = {}

local levels = { debug = 0, info = 1, warn = 2, error = 3 }
local vim_levels = {
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

M._level = levels.warn

--- Set the minimum log level. Messages below this level are silently dropped.
---@param name codex.LogLevel|string Falls back to `warn` if the name is unrecognised.
---@return nil
function M.set_level(name)
  M._level = levels[name] or levels.warn
end

--- Format and emit a log message via `vim.notify` if it meets the current level threshold.
---@param level_name codex.LogLevel
---@param msg string Format string (passed to `string.format`).
---@param ... any Arguments interpolated into `msg`.
---@return nil
local function log(level_name, msg, ...)
  if levels[level_name] < M._level then
    return
  end
  local formatted = string.format(msg, ...)
  vim.notify("[codex] " .. formatted, vim_levels[level_name])
end

--- Log a message at the `debug` level (only shown when level is set to `debug`).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.debug(msg, ...)
  log("debug", msg, ...)
end

--- Log a message at the `info` level (hidden by default).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.info(msg, ...)
  log("info", msg, ...)
end

--- Log a message at the `warn` level (shown by default).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.warn(msg, ...)
  log("warn", msg, ...)
end

--- Log a message at the `error` level (always shown unless logging is fully disabled).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.error(msg, ...)
  log("error", msg, ...)
end

return M
