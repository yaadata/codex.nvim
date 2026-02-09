local M = {}

---@class codex.SelectionOpts
---@field line1? integer
---@field line2? integer
---@field bufnr? integer

local function resolve_range(vim_api, bufnr, opts)
  if opts and opts.line1 and opts.line2 then
    return opts.line1, opts.line2
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
    return nil, "current buffer has no file path"
  end

  local start_line, end_line = resolve_range(vim_api, bufnr, opts)
  if not start_line or not end_line then
    return nil, "no visual selection range found"
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

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
