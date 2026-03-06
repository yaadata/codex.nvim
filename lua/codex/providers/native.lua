local log = require("codex.logger")
local keymaps = require("codex.keymaps")

local M = {}

--- Return true; the native provider is always available.
---@return boolean
function M.is_available()
  return true
end

--- Return the current monotonic time in milliseconds.
---@return integer
local function now_ms()
  local uv = vim.uv or vim.loop
  if not uv or type(uv.now) ~= "function" then
    return 0
  end
  return uv.now()
end

--- Join the command and its arguments into a single shell string.
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

--- Find the first window displaying a given buffer.
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

--- Ensure a size value is at least 1.
---@param size number
---@return integer
local function clamp_size(size)
  return math.max(1, size)
end

--- Compute a pixel size from a percentage of a total, clamped to at least 1.
---@param total number
---@param pct number
---@return integer
local function pct_size(total, pct)
  return clamp_size(math.floor(total * pct / 100))
end

--- Open a vertical split on the specified side and return the new window id.
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

--- Open a horizontal split on the specified side and return the new window id.
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

--- Open a vsplit, hsplit, or float window and place the buffer inside it.
---@param native_opts codex.NativeProviderOpts|table
---@param bufnr integer
---@return integer winid
local function open_window_for_buf(native_opts, bufnr)
  local window = native_opts.window or "vsplit"

  if window == "vsplit" then
    local vsplit = native_opts.vsplit or {}
    local winid = open_vsplit(vsplit.side or "right")
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.api.nvim_win_set_width(winid, pct_size(vim.o.columns, vsplit.size_pct or 40))
    return winid
  end

  if window == "hsplit" then
    local hsplit = native_opts.hsplit or {}
    local winid = open_hsplit(hsplit.side or "bottom")
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.api.nvim_win_set_height(winid, pct_size(vim.o.lines, hsplit.size_pct or 30))
    return winid
  end

  if window == "float" then
    local float = native_opts.float or {}
    local width = pct_size(vim.o.columns, float.width_pct or 80)
    local height = pct_size(vim.o.lines, float.height_pct or 80)
    local row = math.max(0, math.floor((vim.o.lines - height) / 2))
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    return vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      border = float.border or "rounded",
      title = float.title or " Codex ",
      title_pos = float.title_pos or "center",
      style = "minimal",
    })
  end

  error(
    "codex: unsupported terminal.provider_opts.native.window in native provider: "
      .. tostring(window)
  )
end

--- Create a new scratch buffer and open a window for it.
---@param native_opts codex.NativeProviderOpts|table
---@return integer bufnr
---@return integer winid
local function create_window(native_opts)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = open_window_for_buf(native_opts, bufnr)
  return bufnr, winid
end

--- Re-open a window for an existing terminal buffer that has no visible window.
---@param native_opts codex.NativeProviderOpts|table
---@param bufnr integer
---@return integer winid
local function reshow_window(native_opts, bufnr)
  return open_window_for_buf(native_opts, bufnr)
end

--- Close the window and delete the buffer attached to a handle.
---@param handle codex.ProviderHandle
---@return nil
local function cleanup_window_and_buffer(handle)
  if handle.winid and vim.api.nvim_win_is_valid(handle.winid) then
    pcall(vim.api.nvim_win_close, handle.winid, true)
  end
  handle.winid = nil

  if handle.bufnr and vim.api.nvim_buf_is_valid(handle.bufnr) then
    pcall(vim.api.nvim_buf_delete, handle.bufnr, { force = true })
  end
  handle.bufnr = nil
end

--- Spawn a terminal process in a new window and return its handle.
---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.Config
---@param focus boolean
---@param on_exit? fun(handle: codex.ProviderHandle): nil
---@return codex.ProviderHandle handle
function M.open(cmd, args, env, config, focus, on_exit)
  local full_cmd = build_cmd(cmd, args)
  local launch = config.launch or {}
  local cwd = launch.cwd or vim.fn.getcwd()
  local term_config = config.terminal
  local provider_opts = term_config.provider_opts or {}
  local native_opts = provider_opts.native or {}
  local prev_win = vim.api.nvim_get_current_win()
  local bufnr, winid = create_window(native_opts)

  local startup = term_config.startup or {}
  local handle = {
    bufnr = bufnr,
    winid = winid,
    jobid = nil,
    ready_at_ms = now_ms() + (startup.grace_ms or 0),
  }
  local termopen_opts = {
    cwd = cwd,
    on_exit = function(_, exit_code)
      handle.jobid = nil
      if term_config.auto_close == true then
        cleanup_window_and_buffer(handle)
      end
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
  keymaps.apply_terminal(bufnr, term_config.keymaps)

  if focus then
    vim.cmd("startinsert")
  elseif prev_win and prev_win ~= winid and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end

  log.debug("native: opened terminal (buf=%d, win=%d, job=%d)", bufnr, winid, jobid)
  return handle
end

--- Stop the terminal job and clean up its window and buffer.
---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.close(handle)
  if not handle then
    return true
  end

  if handle.jobid then
    pcall(vim.fn.jobstop, handle.jobid)
    handle.jobid = nil
  end

  cleanup_window_and_buffer(handle)

  return true
end

--- Send text to the terminal job channel.
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

--- Focus the terminal window and enter insert mode.
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

  if not winid then
    return false, "terminal window not found"
  end

  handle.winid = winid
  local ok_focus, focus_err = pcall(vim.api.nvim_set_current_win, winid)
  if not ok_focus then
    return false, string.format("failed to focus terminal window: %s", tostring(focus_err))
  end
  if vim.api.nvim_get_current_buf() ~= handle.bufnr then
    return false, "terminal window mismatch"
  end

  local ok_insert, insert_err = pcall(vim.cmd, "startinsert")
  if not ok_insert then
    return false, tostring(insert_err)
  end
  return true
end

--- Toggle the terminal: hide, focus, re-show, or open a new one.
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
  local term_config = config.terminal or {}
  local provider_opts = term_config.provider_opts or {}
  local native_opts = provider_opts.native or {}
  handle.winid = reshow_window(native_opts, handle.bufnr)
  vim.cmd("startinsert")
  return handle
end

--- Return true if the terminal buffer is valid and the job is running.
---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_alive(handle)
  if not handle or not handle.bufnr then
    return false
  end
  return vim.api.nvim_buf_is_valid(handle.bufnr) and handle.jobid ~= nil
end

--- Return true if the terminal is alive and the startup grace period has elapsed.
---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_ready(handle)
  if not M.is_alive(handle) then
    return false
  end

  if type(handle.ready_at_ms) ~= "number" then
    return true
  end

  return now_ms() >= handle.ready_at_ms
end

--- Return the buffer number from a handle, or nil.
---@param handle codex.ProviderHandle|nil
---@return integer|nil bufnr
function M.get_bufnr(handle)
  if handle then
    return handle.bufnr
  end
  return nil
end

return M
