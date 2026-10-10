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

---Creates a selection-send dispatcher with selection-specific orchestration.
---@param opts codex.SelectionAddCreateOpts
---@return codex.SelectionAdd
function M.create(opts)
  local get_deps = opts.get_deps
  local prompt_buffer = opts.get_prompt_buffer()

  ---Resolve active visual selection metadata when explicit range opts are missing.
  ---This supports first-use lazy-key visual mappings where visual marks may be unset.
  ---@param deps table
  ---@param selection_opts? codex.SelectionOpts
  ---@return codex.SelectionOpts
  local function resolve_selection_opts(deps, selection_opts)
    local resolved = copy_opts(selection_opts)
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
    local api = deps.vim.api

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
  ---@param subject "selection"|"buffer"
  ---@param err string|nil
  ---@return nil
  local function log_collection_failure(subject, err)
    local deps = get_deps()
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

  ---Formats visual selection and adds it to the prompt buffer.
  ---@param selection_opts? codex.SelectionOpts
  ---@return codex.Outcome ok
  ---@return string|nil err
  local function buffer(selection_opts)
    local deps = get_deps()
    local resolved_opts = resolve_selection_opts(deps, selection_opts)
    local spec, err = deps.selection.get_visual_selection(deps.vim, resolved_opts)
    if not spec then
      log_collection_failure("selection", err)
      return false, err
    end

    deps.nvim_visual.exit_visual_mode_if_active(deps.vim)
    local payload = deps.formatter.format_selection(spec)
    prompt_buffer:add(payload)
    return true, nil
  end

  return {
    buffer = buffer,
    log_collection_failure = log_collection_failure,
  }
end

return M
