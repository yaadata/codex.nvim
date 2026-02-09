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

  local split_cmd
  if term_config.split_side == "left" then
    split_cmd = "topleft vsplit"
  else
    split_cmd = "botright vsplit"
  end

  local width = math.floor(vim.o.columns * term_config.split_width_pct / 100)
  vim.cmd(width .. split_cmd)

  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(winid, bufnr)

  local handle = { bufnr = bufnr, winid = winid, jobid = nil }
  local jobid = vim.fn.termopen(full_cmd, {
    cwd = cwd,
    env = env,
    on_exit = function(_, exit_code)
      handle.jobid = nil
      log.debug("terminal exited with code %d", exit_code)
      if on_exit then
        on_exit(handle)
      end
    end,
  })
  handle.jobid = jobid

  vim.bo[bufnr].buflisted = false

  if focus then
    vim.cmd("startinsert")
  else
    vim.cmd("wincmd p")
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
  local term_config = config.terminal
  local split_cmd
  if term_config.split_side == "left" then
    split_cmd = "topleft vsplit"
  else
    split_cmd = "botright vsplit"
  end

  local width = math.floor(vim.o.columns * term_config.split_width_pct / 100)
  vim.cmd(width .. split_cmd)
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, handle.bufnr)
  handle.winid = new_win
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
