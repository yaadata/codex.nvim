local log = require("codex.logger")

local M = {}

function M.is_available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks ~= nil and snacks.terminal ~= nil
end

local function build_cmd(cmd, args)
  local parts = { cmd }
  for _, arg in ipairs(args) do
    table.insert(parts, arg)
  end
  return table.concat(parts, " ")
end

function M.open(cmd, args, env, config, focus)
  local snacks = require("snacks")
  local full_cmd = build_cmd(cmd, args)
  local cwd = config.cwd or vim.fn.getcwd()
  local snacks_opts = config.terminal.provider_opts.snacks or {}

  local opts = vim.tbl_deep_extend("force", {
    cmd = full_cmd,
    env = env,
    cwd = cwd,
    interactive = true,
  }, snacks_opts)

  local terminal = snacks.terminal(opts)

  if focus and terminal.show then
    terminal:show()
  end

  local handle = { terminal = terminal, provider = "snacks" }
  log.debug("snacks: opened terminal")
  return handle
end

function M.close(handle)
  if not handle or not handle.terminal then
    return true
  end

  if handle.terminal.close then
    handle.terminal:close()
  end

  return true
end

function M.send(handle, text)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  local term = handle.terminal
  if term.jobid then
    vim.fn.chansend(term.jobid, text)
    return true
  end

  return false, "terminal has no job"
end

function M.focus(handle)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  if handle.terminal.show then
    handle.terminal:show()
    return true
  end

  return false, "cannot focus terminal"
end

function M.toggle(handle, cmd, args, env, config)
  if not handle or not handle.terminal then
    return M.open(cmd, args, env, config, true)
  end

  if handle.terminal.toggle then
    handle.terminal:toggle()
  end

  return handle
end

function M.is_alive(handle)
  if not handle or not handle.terminal then
    return false
  end

  local term = handle.terminal
  if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    return true
  end

  return false
end

function M.get_bufnr(handle)
  if handle and handle.terminal then
    return handle.terminal.buf
  end
  return nil
end

return M
