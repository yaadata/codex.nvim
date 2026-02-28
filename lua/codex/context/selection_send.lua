local M = {}
local CTRL_V = string.char(22)

---Check whether a value is an integer >= 1.
---@param value any
---@return boolean
local function is_positive_integer(value)
  return type(value) == "number" and value >= 1 and math.floor(value) == value
end

---Check whether a value is an integer >= 0.
---@param value any
---@return boolean
local function is_non_negative_integer(value)
  return type(value) == "number" and value >= 0 and math.floor(value) == value
end

---Return a shallow copy of a possibly nil table.
---@param opts table|nil
---@return table
local function copy_opts(opts)
  local copied = {}
  for key, value in pairs(opts or {}) do
    copied[key] = value
  end
  return copied
end

---Resolve active visual selection metadata when explicit range opts are missing.
---This supports first-use lazy-key visual mappings where visual marks may be unset.
---@param deps table
---@param opts? codex.SelectionOpts
---@return codex.SelectionOpts
function M.resolve_selection_opts(deps, opts)
  local resolved = copy_opts(opts)
  if is_positive_integer(resolved.line1) and is_positive_integer(resolved.line2) then
    return resolved
  end

  local fn = deps.vim.fn or {}
  if type(fn.mode) ~= "function" then
    return resolved
  end

  local ok_mode, visual_mode = pcall(fn.mode, 1)
  if not ok_mode then
    return resolved
  end
  if visual_mode ~= "v" and visual_mode ~= "V" and visual_mode ~= CTRL_V then
    return resolved
  end

  if resolved.visual_mode == nil then
    resolved.visual_mode = visual_mode
  end

  if type(fn.getpos) ~= "function" then
    return resolved
  end
  local api = deps.vim.api or {}
  if type(api.nvim_win_get_cursor) ~= "function" then
    return resolved
  end

  local ok_anchor, anchor = pcall(fn.getpos, "v")
  local ok_cursor, cursor = pcall(api.nvim_win_get_cursor, 0)
  if not ok_anchor or type(anchor) ~= "table" then
    return resolved
  end
  if not ok_cursor or type(cursor) ~= "table" then
    return resolved
  end

  local anchor_line = anchor[2]
  local anchor_col = anchor[3]
  local cursor_line = cursor[1]
  local cursor_col = cursor[2]

  if not is_positive_integer(anchor_line) or not is_positive_integer(cursor_line) then
    return resolved
  end
  if not is_positive_integer(anchor_col) or not is_non_negative_integer(cursor_col) then
    return resolved
  end

  if not is_positive_integer(resolved.line1) then
    resolved.line1 = anchor_line
  end
  if not is_positive_integer(resolved.line2) then
    resolved.line2 = cursor_line
  end
  if not is_non_negative_integer(resolved.start_col) then
    resolved.start_col = anchor_col - 1
  end
  if not is_non_negative_integer(resolved.end_col) then
    resolved.end_col = cursor_col
  end

  return resolved
end

---Log selection/buffer extraction failures with warning or error severity.
---@param deps table
---@param subject "selection"|"buffer"
---@param err string|nil
---@return nil
function M.log_selection_failure(deps, subject, err)
  local target = subject or "selection"
  local selection_errors = deps.selection.errors or {}
  if err == selection_errors.BUFFER_NOT_FOUND then
    deps.logger.warn("failed to collect %s: %s", target, err or "unknown error")
    return
  end
  if err == selection_errors.NO_FILEPATH or err == selection_errors.INVALID_FILEPATH then
    deps.logger.warn("failed to collect %s: %s", target, err or "unknown error")
    return
  end
  deps.logger.error("failed to collect %s: %s", target, err or "unknown error")
end

return M
