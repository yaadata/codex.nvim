local config_mod = require("codex.config")
local log = require("codex.logger")
local providers = require("codex.providers")
local session_store = require("codex.state.session_store")

local M = {}

local state = {
  config = nil,
  initialized = false,
}

function M.setup(opts)
  state.config = config_mod.apply(opts)
  log.set_level(state.config.log_level)

  require("codex.nvim.commands").register()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("codex_cleanup", { clear = true }),
    callback = function()
      M.close()
    end,
  })

  state.initialized = true
  log.debug("codex.nvim initialized")

  if state.config.auto_start then
    vim.schedule(function()
      M.open(false)
    end)
  end
end

local function ensure_setup()
  if not state.initialized then
    error("codex.nvim: call require('codex').setup() first")
  end
end

local function get_provider()
  return providers.resolve(state.config.terminal.provider)
end

function M.open(focus)
  ensure_setup()
  if focus == nil then
    focus = true
  end

  local session = session_store.get_active()
  local provider, provider_name = get_provider()

  if session and session.alive and provider.is_alive(session.handle) then
    if focus then
      provider.focus(session.handle)
    end
    return
  end

  -- Close stale session if any
  if session then
    provider.close(session.handle)
    session_store.remove(session.id)
  end

  local handle =
    provider.open(state.config.cmd, state.config.args, state.config.env, state.config, focus)

  session_store.create({
    handle = handle,
    cmd = state.config.cmd,
    cwd = state.config.cwd or vim.fn.getcwd(),
    provider_name = provider_name,
  })
end

function M.close()
  local session = session_store.get_active()
  if not session then
    return
  end

  local provider = get_provider()
  provider.close(session.handle)
  session_store.remove(session.id)
end

function M.toggle()
  ensure_setup()

  local session = session_store.get_active()
  local provider, provider_name = get_provider()

  if session and session.alive then
    local new_handle = provider.toggle(
      session.handle,
      state.config.cmd,
      state.config.args,
      state.config.env,
      state.config
    )
    if new_handle then
      session.handle = new_handle
    end
    return
  end

  -- No active session — open one
  local handle =
    provider.open(state.config.cmd, state.config.args, state.config.env, state.config, true)

  session_store.create({
    handle = handle,
    cmd = state.config.cmd,
    cwd = state.config.cwd or vim.fn.getcwd(),
    provider_name = provider_name,
  })
end

function M.focus()
  ensure_setup()

  local session = session_store.get_active()
  local provider = get_provider()

  if session and session.alive and provider.is_alive(session.handle) then
    provider.focus(session.handle)
    return
  end

  M.open(true)
end

function M.send(text)
  ensure_setup()

  local session = session_store.get_active()
  if not session or not session.alive then
    M.open(false)
    session = session_store.get_active()
  end

  local provider = get_provider()
  local ok, err = provider.send(session.handle, text)
  if not ok then
    log.error("failed to send text: %s", err or "unknown error")
  end
end

function M.is_running()
  local session = session_store.get_active()
  if not session or not session.alive then
    return false
  end

  local provider = get_provider()
  return provider.is_alive(session.handle)
end

function M.get_config()
  return state.config and vim.deepcopy(state.config) or nil
end

return M
