local M = {}

local ERR_NO_FILEPATH = "codex: current buffer has no file path"
local ERR_NO_SELECTION = "codex: no visual selection range found"

---@class codex.SelectionOpts
---@field line1? integer
---@field line2? integer
---@field bufnr? integer

local function is_positive_integer(value)
  return type(value) == "number" and value >= 1 and math.floor(value) == value
end

---Resolves selection range with explicit precedence:
---1) command-provided range (`opts.line1` + `opts.line2`)
---2) visual marks (`'<` and `'>`)
local function resolve_range(vim_api, bufnr, opts)
  local line1 = opts and opts.line1
  local line2 = opts and opts.line2
  if is_positive_integer(line1) and is_positive_integer(line2) then
    return line1, line2
  end

  local start_mark = vim_api.api.nvim_buf_get_mark(bufnr, "<")
  local end_mark = vim_api.api.nvim_buf_get_mark(bufnr, ">")
  local start_line = start_mark[1]
  local end_line = end_mark[1]

  if start_line <= 0 or end_line <= 0 then
    return nil, nil
  end

  return start_line, end_line
end

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
    return nil, ERR_NO_FILEPATH
  end

  local start_line, end_line = resolve_range(vim_api, bufnr, opts)
  if not start_line or not end_line then
    return nil, ERR_NO_SELECTION
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  -- Selection is linewise only: mark columns are intentionally ignored.
  local lines = vim_api.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local filetype = vim_api.bo[bufnr].filetype or ""

  return {
    filepath = vim_api.fn.fnamemodify(filepath, ":p"),
    start_line = start_line,
    end_line = end_line,
    filetype = filetype,
    lines = lines,
  }
end

return M
