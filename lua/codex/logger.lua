local M = {}

local levels = { debug = 0, info = 1, warn = 2, error = 3 }
local vim_levels = {
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

M._level = levels.warn

function M.set_level(name)
  M._level = levels[name] or levels.warn
end

local function log(level_name, msg, ...)
  if levels[level_name] < M._level then
    return
  end
  local formatted = string.format(msg, ...)
  vim.notify("[codex] " .. formatted, vim_levels[level_name])
end

function M.debug(msg, ...)
  log("debug", msg, ...)
end

function M.info(msg, ...)
  log("info", msg, ...)
end

function M.warn(msg, ...)
  log("warn", msg, ...)
end

function M.error(msg, ...)
  log("error", msg, ...)
end

return M
