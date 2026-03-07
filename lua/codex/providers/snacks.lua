local log = require("codex.logger")
local keymaps = require("codex.keymaps")

local M = {}

--- Return true if the snacks.nvim terminal module is loadable.
---@return boolean
function M.is_available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks ~= nil and snacks.terminal ~= nil
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

--- Resolve the job channel id from a snacks terminal object.
---@param term table
---@return integer|nil
local function resolve_jobid(term)
  if type(term.jobid) == "number" and term.jobid > 0 then
    return term.jobid
  end

  local bufnr = term.buf
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local ok_channel, channel = pcall(vim.api.nvim_get_option_value, "channel", { buf = bufnr })
  if ok_channel and type(channel) == "number" and channel > 0 then
    return channel
  end

  local ok, jobid = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if not ok then
    return nil
  end

  if type(jobid) == "number" and jobid > 0 then
    return jobid
  end

  return nil
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

--- Open a terminal via snacks.terminal and return its handle.
---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.Config
---@param focus boolean
---@param on_exit? fun(handle: codex.ProviderHandle): nil
---@return codex.ProviderHandle handle
function M.open(cmd, args, env, config, focus, on_exit)
  local snacks = require("snacks")
  local full_cmd = build_cmd(cmd, args)
  local launch = config.launch or {}
  local cwd = launch.cwd or vim.fn.getcwd()
  local provider_opts = config.terminal.provider_opts or {}
  local snacks_opts = provider_opts.snacks or {}
  local auto_close = config.terminal.auto_close == true

  local base_opts = {
    cmd = full_cmd,
    cwd = cwd,
    interactive = true,
    -- Keep Snacks auto_close disabled so codex controls TermClose behavior and
    -- avoids Snacks non-zero exit notifications for intentional closes.
    auto_close = false,
  }
  if next(env) ~= nil then
    base_opts.env = env
  end

  local opts = vim.tbl_deep_extend("force", base_opts, snacks_opts)

  local terminal = snacks.terminal(full_cmd, opts)

  if focus and terminal.show then
    terminal:show()
  end

  local startup = config.terminal.startup or {}
  local handle = {
    terminal = terminal,
    provider = "snacks",
    ready_at_ms = now_ms() + (startup.grace_ms or 0),
  }

  if type(terminal.buf) == "number" then
    keymaps.apply_terminal(terminal.buf, config.terminal.keymaps)
  end

  if terminal.buf and (on_exit or auto_close) then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = terminal.buf,
      once = true,
      callback = function()
        if on_exit then
          on_exit(handle)
        end

        if auto_close and handle.terminal and handle.terminal.close then
          vim.schedule(function()
            local ok, err = pcall(function()
              handle.terminal:close()
            end)
            if not ok then
              log.debug("snacks: failed to auto-close terminal on TermClose: %s", tostring(err))
            end
            pcall(vim.cmd, "checktime")
          end)
        end
      end,
    })
  end

  log.debug("snacks: opened terminal")
  return handle
end

--- Close the snacks terminal session.
---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.close(handle)
  if not handle or not handle.terminal then
    return true
  end

  if handle.terminal.close then
    handle.terminal:close()
  end

  return true
end

--- Send text to the snacks terminal job channel.
---@param handle codex.ProviderHandle|nil
---@param text string
---@return boolean ok
---@return string|nil err
function M.send(handle, text)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  local term = handle.terminal
  local jobid = resolve_jobid(term)
  if jobid then
    vim.fn.chansend(jobid, text)
    return true
  end

  return false, "terminal has no job"
end

--- Show the snacks terminal and enter insert mode.
---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.focus(handle)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  local term = handle.terminal
  if term.show then
    term:show()
  end

  if term.focus then
    term:focus()
  elseif not term.show then
    return false, "cannot focus terminal"
  end

  local term_buf = type(term.buf) == "number" and term.buf or nil
  if term_buf then
    local current_buf = vim.api.nvim_get_current_buf()
    if current_buf ~= term_buf then
      if
        type(term.win) == "number"
        and vim.api.nvim_win_is_valid(term.win)
        and pcall(vim.api.nvim_set_current_win, term.win)
      then
        current_buf = vim.api.nvim_get_current_buf()
      end
      if current_buf ~= term_buf then
        return false, "terminal window not focused"
      end
    end
  end

  local ok, err = pcall(vim.cmd, "startinsert")
  if not ok then
    return false, err
  end
  return true
end

--- Toggle the snacks terminal visibility, opening a new one if needed.
---@param handle codex.ProviderHandle|nil
---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.Config
---@return codex.ProviderHandle|nil new_handle
---@return string|nil err
function M.toggle(handle, cmd, args, env, config)
  if not handle or not M.is_alive(handle) then
    return M.open(cmd, args, env, config, true)
  end

  if handle.terminal.toggle then
    handle.terminal:toggle()
  end

  return handle
end

--- Return true if the snacks terminal has an active job channel.
---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_alive(handle)
  if not handle or not handle.terminal then
    return false
  end

  local term = handle.terminal
  return resolve_jobid(term) ~= nil
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

--- Return the buffer number from a snacks terminal handle, or nil.
---@param handle codex.ProviderHandle|nil
---@return integer|nil bufnr
function M.get_bufnr(handle)
  if handle and handle.terminal then
    return handle.terminal.buf
  end
  return nil
end

return M
