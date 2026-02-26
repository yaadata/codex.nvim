local M = {}
local path = require("codex.context.path")

local CTRL_V = string.char(22)

M.errors = {
  NO_FILEPATH = "current buffer has no file path",
  INVALID_FILEPATH = "current buffer path is not a regular file",
  NO_SELECTION = "no visual selection range found",
}

---@class codex.SelectionOpts
---@field line1? integer
---@field line2? integer
---@field start_col? integer
---@field end_col? integer
---@field bufnr? integer
---@field visual_mode? string

--- Check whether a value is an integer >= 1.
---@param value any
---@return boolean
local function is_positive_integer(value)
  return type(value) == "number" and value >= 1 and math.floor(value) == value
end

--- Check whether a value is an integer >= 0.
---@param value any
---@return boolean
local function is_non_negative_integer(value)
  return type(value) == "number" and value >= 0 and math.floor(value) == value
end

--- Return the two line numbers in ascending order.
---@param line1 integer
---@param line2 integer
---@return integer start_line
---@return integer end_line
local function normalize_lines(line1, line2)
  if line1 <= line2 then
    return line1, line2
  end
  return line2, line1
end

--- Sort two (line, col) pairs so the earlier position comes first.
---@param start_line integer
---@param start_col integer
---@param end_line integer
---@param end_col integer
---@return integer norm_start_line
---@return integer norm_start_col
---@return integer norm_end_line
---@return integer norm_end_col
local function normalize_marks(start_line, start_col, end_line, end_col)
  if start_line < end_line then
    return start_line, start_col, end_line, end_col
  end
  if start_line > end_line then
    return end_line, end_col, start_line, start_col
  end
  if start_col <= end_col then
    return start_line, start_col, end_line, end_col
  end
  return end_line, end_col, start_line, start_col
end

--- Return the substring of a line from a 0-based column to the end.
---@param line string
---@param start_col integer
---@return string
local function slice_from_col(line, start_col)
  local start_idx = math.max(1, start_col + 1)
  if start_idx > #line then
    return ""
  end
  return line:sub(start_idx)
end

--- Return the substring of a line from the start up to a 0-based column.
---@param line string
---@param end_col integer
---@return string
local function slice_to_col(line, end_col)
  local end_idx = math.min(#line, end_col + 1)
  if end_idx < 1 then
    return ""
  end
  return line:sub(1, end_idx)
end

--- Return the substring of a line between two 0-based columns (inclusive).
---@param line string
---@param start_col integer
---@param end_col integer
---@return string
local function slice_col_range(line, start_col, end_col)
  local start_idx = math.max(1, start_col + 1)
  local end_idx = math.min(#line, end_col + 1)
  if start_idx > #line or end_idx < start_idx then
    return ""
  end
  return line:sub(start_idx, end_idx)
end

---Resolves selection range with explicit precedence:
---1) command-provided range (`opts.line1` + `opts.line2`)
---2) visual marks (`'<` and `'>`)
---@param marks table
---@param opts codex.SelectionOpts|nil
---@return integer|nil start_line
---@return integer|nil end_line
local function resolve_range(marks, opts)
  local line1 = opts and opts.line1
  local line2 = opts and opts.line2
  if is_positive_integer(line1) and is_positive_integer(line2) then
    return line1, line2
  end

  local start_line = marks.start_line
  local end_line = marks.end_line

  if start_line <= 0 or end_line <= 0 then
    return nil, nil
  end

  return start_line, end_line
end

--- Extract the visual mode string from opts if it is a recognised mode.
---@param opts codex.SelectionOpts|nil
---@return "v"|"V"|string|nil
local function resolve_visual_mode(opts)
  local explicit = opts and opts.visual_mode
  if explicit == "v" or explicit == "V" or explicit == CTRL_V then
    return explicit
  end
  return nil
end

--- Determine whether filepath points to a regular file.
---@param vim_api table
---@param filepath string
---@return boolean
local function is_regular_file(vim_api, filepath)
  local uv = vim_api.uv or vim_api.loop
  if uv and type(uv.fs_stat) == "function" then
    local ok, stat = pcall(uv.fs_stat, filepath)
    if ok then
      return type(stat) == "table" and stat.type == "file"
    end
  end

  local fn = vim_api.fn
  if type(fn) == "table" and type(fn.filereadable) == "function" then
    local ok, readable = pcall(fn.filereadable, filepath)
    if ok then
      return readable == 1
    end
  end

  return true
end

--- Trim lines to the selected columns based on the visual mode.
---@param lines string[]
---@param visual_mode string|nil
---@param range table
---@return string[]
local function shape_lines(lines, visual_mode, range)
  if visual_mode == "v" then
    local out = vim.deepcopy(lines)
    if #out == 1 then
      out[1] = slice_col_range(out[1], range.start_col, range.end_col)
      return out
    end
    out[1] = slice_from_col(out[1], range.start_col)
    out[#out] = slice_to_col(out[#out], range.end_col)
    return out
  end

  if visual_mode == CTRL_V then
    local out = {}
    for _, line in ipairs(lines) do
      table.insert(out, slice_col_range(line, range.block_start_col, range.block_end_col))
    end
    return out
  end

  return lines
end

--- Capture the current visual selection as a SelectionSpec.
---@param vim_api table|nil
---@param opts? codex.SelectionOpts
---@return codex.SelectionSpec|nil spec
---@return string|nil err
function M.get_visual_selection(vim_api, opts)
  vim_api = vim_api or vim
  opts = opts or {}

  local bufnr = opts.bufnr or vim_api.api.nvim_get_current_buf()
  local filepath = vim_api.api.nvim_buf_get_name(bufnr)
  if not filepath or filepath == "" then
    return nil, M.errors.NO_FILEPATH
  end

  if not is_regular_file(vim_api, filepath) then
    return nil, M.errors.INVALID_FILEPATH
  end

  local start_mark = vim_api.api.nvim_buf_get_mark(bufnr, "<")
  local end_mark = vim_api.api.nvim_buf_get_mark(bufnr, ">")
  local explicit_start_line = opts.line1
  local explicit_end_line = opts.line2
  local explicit_start_col = opts.start_col
  local explicit_end_col = opts.end_col
  local marks = {
    start_line = is_positive_integer(explicit_start_line) and explicit_start_line
      or (start_mark[1] or 0),
    start_col = is_non_negative_integer(explicit_start_col) and explicit_start_col
      or (start_mark[2] or 0),
    end_line = is_positive_integer(explicit_end_line) and explicit_end_line or (end_mark[1] or 0),
    end_col = is_non_negative_integer(explicit_end_col) and explicit_end_col or (end_mark[2] or 0),
  }

  local start_line, end_line = resolve_range(marks, opts)
  if not start_line or not end_line then
    return nil, M.errors.NO_SELECTION
  end

  start_line, end_line = normalize_lines(start_line, end_line)

  local norm_start_line, norm_start_col, norm_end_line, norm_end_col =
    normalize_marks(marks.start_line, marks.start_col, marks.end_line, marks.end_col)
  local range = {
    start_col = norm_start_col,
    end_col = norm_end_col,
    block_start_col = math.min(norm_start_col, norm_end_col),
    block_end_col = math.max(norm_start_col, norm_end_col),
  }
  if start_line == end_line and norm_start_line ~= norm_end_line then
    range.start_col = 0
    range.end_col = #(
      vim_api.api.nvim_buf_get_lines(bufnr, start_line - 1, start_line, false)[1] or ""
    )
    range.block_start_col = 0
    range.block_end_col = range.end_col
  end

  local lines = vim_api.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local visual_mode = resolve_visual_mode(opts)
  lines = shape_lines(lines, visual_mode, range)
  local filetype = vim_api.bo[bufnr].filetype or ""

  return {
    filepath = path.to_relative(vim_api, filepath),
    start_line = start_line,
    end_line = end_line,
    filetype = filetype,
    lines = lines,
  }
end

return M
