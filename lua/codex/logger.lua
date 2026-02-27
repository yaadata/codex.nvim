---Logging facade that delegates to `vim.notify` with level filtering and keeps
---a bounded in-memory log buffer for troubleshooting capture.
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
M._verbose = false
M._max_entries = 1000
M._entries = {}
M._pending_entries = {}
M._flush_scheduled = false
M._next_seq = 0

---Returns true when the given level should be emitted at current threshold.
---@param level_name codex.LogLevel
---@return boolean
local function should_emit(level_name)
  return levels[level_name] >= M._level
end

---Returns true when this log should be captured/emitted.
---@param level_name codex.LogLevel
---@param capture_verbose boolean
---@return boolean
local function should_capture(level_name, capture_verbose)
  if capture_verbose and not M._verbose then
    return false
  end
  return should_emit(level_name)
end

---Allocates the next monotonic sequence id.
---@return integer
local function next_seq()
  M._next_seq = M._next_seq + 1
  return M._next_seq
end

---Appends a structured entry to the bounded in-memory log buffer.
---@param level_name codex.LogLevel
---@param message string
---@param verbose boolean
---@param seq integer
---@param timestamp integer
---@return nil
local function append_entry(level_name, message, verbose, seq, timestamp)
  if #M._entries >= M._max_entries then
    table.remove(M._entries, 1)
  end
  table.insert(M._entries, {
    seq = seq,
    timestamp = timestamp,
    level = level_name,
    message = message,
    verbose = verbose,
  })
end

---Emits an entry into capture storage and optional notify output.
---@param entry { level: codex.LogLevel, message: string, verbose: boolean, notify_user: boolean, seq: integer, timestamp: integer }
---@return nil
local function emit_entry(entry)
  append_entry(entry.level, entry.message, entry.verbose, entry.seq, entry.timestamp)
  if entry.notify_user then
    vim.notify("[codex] " .. entry.message, vim_levels[entry.level])
  end
end

---Flushes all deferred non-critical logs in sequence order.
---@return nil
local function flush_pending()
  M._flush_scheduled = false
  if #M._pending_entries == 0 then
    return
  end
  table.sort(M._pending_entries, function(a, b)
    return a.seq < b.seq
  end)
  for _, entry in ipairs(M._pending_entries) do
    emit_entry(entry)
  end
  M._pending_entries = {}
end

---Schedules deferred flush for non-critical logs.
---@return nil
local function schedule_flush()
  if M._flush_scheduled then
    return
  end
  M._flush_scheduled = true
  vim.schedule(flush_pending)
end

--- Set the minimum log level. Messages below this level are silently dropped.
---@param name codex.LogLevel|string Falls back to `warn` if the name is unrecognised.
---@return nil
function M.set_level(name)
  M._level = levels[name] or levels.warn
end

---Enable or disable verbose capture logs.
---@param enabled boolean
---@return nil
function M.set_verbose(enabled)
  M._verbose = enabled == true
end

---Format, capture, and optionally emit a log message when level threshold allows it.
---@param level_name codex.LogLevel
---@param msg string Format string (passed to `string.format`).
---@param capture_verbose boolean
---@param notify_user boolean
---@param ... any Arguments interpolated into `msg`.
---@return nil
local function log(level_name, msg, capture_verbose, notify_user, ...)
  if not should_capture(level_name, capture_verbose) then
    return
  end
  local entry = {
    level = level_name,
    message = string.format(msg, ...),
    verbose = capture_verbose,
    notify_user = notify_user,
    seq = next_seq(),
    timestamp = vim.uv.now(),
  }
  if level_name == "warn" or level_name == "error" then
    flush_pending()
    emit_entry(entry)
    return
  end
  table.insert(M._pending_entries, entry)
  schedule_flush()
end

--- Log a message at the `debug` level (only shown when level is set to `debug`).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.debug(msg, ...)
  log("debug", msg, false, true, ...)
end

--- Log a message at the `info` level (hidden by default).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.info(msg, ...)
  log("info", msg, false, true, ...)
end

--- Log a message at the `warn` level (shown by default).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.warn(msg, ...)
  log("warn", msg, false, true, ...)
end

--- Log a message at the `error` level (always shown unless logging is fully disabled).
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.error(msg, ...)
  log("error", msg, false, true, ...)
end

---Logs capture-only verbose debug details when verbose mode is enabled.
---@param msg string Format string.
---@param ... any Format arguments.
---@return nil
function M.vdebug(msg, ...)
  log("debug", msg, true, false, ...)
end

---Returns a deep-copied snapshot of captured log entries.
---@return codex.LogEntry[]
function M.get_logs()
  flush_pending()
  local entries = vim.deepcopy(M._entries)
  table.sort(entries, function(a, b)
    return a.seq < b.seq
  end)
  return entries
end

---Clears all captured log entries from the in-memory buffer.
---@return nil
function M.clear_logs()
  M._entries = {}
  M._pending_entries = {}
end

return M
