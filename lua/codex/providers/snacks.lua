local log = require("codex.logger")

local M = {}

---@return boolean
function M.is_available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks ~= nil and snacks.terminal ~= nil
end

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
---@return nil
local function set_terminal_keymaps(bufnr)
  vim.keymap.set("t", "<C-c>", function()
    require("codex").toggle()
  end, {
    buffer = bufnr,
    silent = true,
    nowait = true,
    desc = "Codex: Toggle terminal",
  })
end

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
  local cwd = config.cwd or vim.fn.getcwd()
  local snacks_opts = config.terminal.provider_opts.snacks or {}

  local base_opts = {
    cmd = full_cmd,
    cwd = cwd,
    interactive = true,
  }
  if config.terminal.window == "float" then
    base_opts.win = {
      position = "float",
      border = config.terminal.float.border,
    }
  end
  if next(env) ~= nil then
    base_opts.env = env
  end

  local opts = vim.tbl_deep_extend("force", base_opts, snacks_opts)

  local terminal = snacks.terminal(full_cmd, opts)

  if focus and terminal.show then
    terminal:show()
  end

  local handle = { terminal = terminal, provider = "snacks" }

  if type(terminal.buf) == "number" then
    set_terminal_keymaps(terminal.buf)
  end

  if on_exit and terminal.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = terminal.buf,
      once = true,
      callback = function()
        on_exit(handle)
      end,
    })
  end

  log.debug("snacks: opened terminal")
  return handle
end

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

---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.focus(handle)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  if handle.terminal.show then
    handle.terminal:show()
    vim.cmd("startinsert")
    return true
  end

  return false, "cannot focus terminal"
end

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

---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_alive(handle)
  if not handle or not handle.terminal then
    return false
  end

  local term = handle.terminal
  return resolve_jobid(term) ~= nil
end

---@param handle codex.ProviderHandle|nil
---@return integer|nil bufnr
function M.get_bufnr(handle)
  if handle and handle.terminal then
    return handle.terminal.buf
  end
  return nil
end

return M
