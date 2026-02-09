local log = require("codex.logger")

local M = {}

---@return boolean
function M.is_available()
  return true
end

---@param cmd string
---@param args string[]
---@return string
local function build_cmd(cmd, args)
  local parts = { cmd }
  for _, arg in ipairs(args) do
    table.insert(parts, arg)
  end
  return table.concat(parts, " ")
end

---@param bufnr integer
---@return integer|nil winid
local function find_win_for_buf(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

---@param size number
---@return integer
local function clamp_size(size)
  return math.max(1, size)
end

---@param total number
---@param pct number
---@return integer
local function pct_size(total, pct)
  return clamp_size(math.floor(total * pct / 100))
end

---@param side "left"|"right"
---@return integer winid
local function open_vsplit(side)
  if side == "left" then
    vim.cmd("topleft vsplit")
  else
    vim.cmd("botright vsplit")
  end
  return vim.api.nvim_get_current_win()
end

---@param side "top"|"bottom"
---@return integer winid
local function open_hsplit(side)
  if side == "top" then
    vim.cmd("topleft split")
  else
    vim.cmd("botright split")
  end
  return vim.api.nvim_get_current_win()
end

---@param term_config codex.TerminalConfig
---@param bufnr integer
---@return integer winid
local function open_window_for_buf(term_config, bufnr)
  if term_config.window == "vsplit" then
    local winid = open_vsplit(term_config.vsplit.side)
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.api.nvim_win_set_width(winid, pct_size(vim.o.columns, term_config.vsplit.size_pct))
    return winid
  end

  if term_config.window == "hsplit" then
    local winid = open_hsplit(term_config.hsplit.side)
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.api.nvim_win_set_height(winid, pct_size(vim.o.lines, term_config.hsplit.size_pct))
    return winid
  end

  if term_config.window == "float" then
    local width = pct_size(vim.o.columns, term_config.float.width_pct)
    local height = pct_size(vim.o.lines, term_config.float.height_pct)
    local row = math.max(0, math.floor((vim.o.lines - height) / 2))
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    return vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      border = term_config.float.border,
      title = term_config.float.title,
      title_pos = term_config.float.title_pos,
      style = "minimal",
    })
  end

  error("codex: unsupported terminal.window in native provider: " .. tostring(term_config.window))
end

---@param term_config codex.TerminalConfig
---@return integer bufnr
---@return integer winid
local function create_window(term_config)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = open_window_for_buf(term_config, bufnr)
  return bufnr, winid
end

---@param term_config codex.TerminalConfig
---@param bufnr integer
---@return integer winid
local function reshow_window(term_config, bufnr)
  return open_window_for_buf(term_config, bufnr)
end

---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.Config
---@param focus boolean
---@param on_exit? fun(handle: codex.ProviderHandle): nil
---@return codex.ProviderHandle handle
function M.open(cmd, args, env, config, focus, on_exit)
  local full_cmd = build_cmd(cmd, args)
  local cwd = config.cwd or vim.fn.getcwd()
  local term_config = config.terminal
  local prev_win = vim.api.nvim_get_current_win()
  local bufnr, winid = create_window(term_config)

  local handle = { bufnr = bufnr, winid = winid, jobid = nil }
  local termopen_opts = {
    cwd = cwd,
    on_exit = function(_, exit_code)
      handle.jobid = nil
      log.debug("terminal exited with code %d", exit_code)
      if on_exit then
        on_exit(handle)
      end
    end,
  }
  if next(env) ~= nil then
    termopen_opts.env = env
  end

  local jobid = vim.fn.termopen(full_cmd, termopen_opts)
  handle.jobid = jobid

  vim.bo[bufnr].buflisted = false

  if focus then
    vim.cmd("startinsert")
  elseif prev_win and prev_win ~= winid and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end

  log.debug("native: opened terminal (buf=%d, win=%d, job=%d)", bufnr, winid, jobid)
  return handle
end

---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.close(handle)
  if not handle then
    return true
  end

  if handle.winid and vim.api.nvim_win_is_valid(handle.winid) then
    vim.api.nvim_win_close(handle.winid, true)
  end

  if handle.jobid then
    pcall(vim.fn.jobstop, handle.jobid)
  end

  if handle.bufnr and vim.api.nvim_buf_is_valid(handle.bufnr) then
    pcall(vim.api.nvim_buf_delete, handle.bufnr, { force = true })
  end

  return true
end

---@param handle codex.ProviderHandle|nil
---@param text string
---@return boolean ok
---@return string|nil err
function M.send(handle, text)
  if not handle or not handle.jobid then
    return false, "no active terminal"
  end

  vim.fn.chansend(handle.jobid, text)
  return true
end

---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.focus(handle)
  if not handle or not handle.bufnr then
    return false, "no active terminal"
  end

  if not vim.api.nvim_buf_is_valid(handle.bufnr) then
    return false, "terminal buffer invalid"
  end

  local winid = handle.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    winid = find_win_for_buf(handle.bufnr)
  end

  if winid then
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
    return true
  end

  return false, "terminal window not found"
end

---@param handle codex.ProviderHandle|nil
---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.Config
---@return codex.ProviderHandle|nil handle
---@return string|nil err
function M.toggle(handle, cmd, args, env, config)
  if not handle or not M.is_alive(handle) then
    return M.open(cmd, args, env, config, true)
  end

  local winid = handle.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    winid = find_win_for_buf(handle.bufnr)
  end

  if winid then
    local current_win = vim.api.nvim_get_current_win()
    if current_win == winid then
      vim.api.nvim_win_close(winid, false)
      handle.winid = nil
      return handle
    else
      vim.api.nvim_set_current_win(winid)
      vim.cmd("startinsert")
      return handle
    end
  end

  -- Buffer exists but no window — re-show it
  handle.winid = reshow_window(config.terminal, handle.bufnr)
  vim.cmd("startinsert")
  return handle
end

---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_alive(handle)
  if not handle or not handle.bufnr then
    return false
  end
  return vim.api.nvim_buf_is_valid(handle.bufnr) and handle.jobid ~= nil
end

---@param handle codex.ProviderHandle|nil
---@return integer|nil bufnr
function M.get_bufnr(handle)
  if handle then
    return handle.bufnr
  end
  return nil
end

return M
