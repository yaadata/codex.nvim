local M = {}

local default_deps = {
  config = require("codex.config"),
  logger = require("codex.logger"),
  providers = require("codex.providers"),
  session_store = require("codex.state.session_store"),
  commands = require("codex.nvim.commands"),
  vim = vim,
}

local state = {
  config = nil,
  initialized = false,
  deps = nil,
}

local function get_deps()
  return state.deps or default_deps
end

function M.setup(opts)
  opts = opts or {}

  local deps = {}
  for key, value in pairs(default_deps) do
    deps[key] = value
  end
  for key, value in pairs(opts._deps or {}) do
    deps[key] = value
  end
  state.deps = deps

  local config_opts = deps.vim.deepcopy(opts)
  config_opts._deps = nil

  state.config = deps.config.apply(config_opts)
  deps.logger.set_level(state.config.log_level)

  deps.commands.register()

  deps.vim.api.nvim_create_autocmd("VimLeavePre", {
    group = deps.vim.api.nvim_create_augroup("codex_cleanup", { clear = true }),
    callback = function()
      M.close()
    end,
  })

  state.initialized = true
  deps.logger.debug("codex.nvim initialized")

  if state.config.auto_start then
    deps.vim.schedule(function()
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
  return get_deps().providers.resolve(state.config.terminal.provider)
end

local function mark_session_dead_by_handle(deps, dead_handle)
  if not dead_handle then
    return
  end

  for _, session in ipairs(deps.session_store.list()) do
    if session.handle == dead_handle then
      deps.session_store.mark_dead(session.id)
      return
    end
  end
end

function M.open(focus)
  ensure_setup()
  local deps = get_deps()
  if focus == nil then
    focus = true
  end

  local session = deps.session_store.get_active()
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
    deps.session_store.remove(session.id)
  end

  local handle = provider.open(
    state.config.cmd,
    state.config.args,
    state.config.env,
    state.config,
    focus,
    function(exited_handle)
      mark_session_dead_by_handle(deps, exited_handle)
    end
  )

  deps.session_store.create({
    handle = handle,
    cmd = state.config.cmd,
    cwd = state.config.cwd or deps.vim.fn.getcwd(),
    provider_name = provider_name,
  })
end

function M.close()
  local deps = get_deps()
  local session = deps.session_store.get_active()
  if not session then
    return
  end

  local provider = get_provider()
  provider.close(session.handle)
  deps.session_store.remove(session.id)
end

function M.toggle()
  ensure_setup()
  local deps = get_deps()

  local session = deps.session_store.get_active()
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

  deps.session_store.create({
    handle = handle,
    cmd = state.config.cmd,
    cwd = state.config.cwd or deps.vim.fn.getcwd(),
    provider_name = provider_name,
  })
end

function M.focus()
  ensure_setup()
  local deps = get_deps()

  local session = deps.session_store.get_active()
  local provider = get_provider()

  if session and session.alive and provider.is_alive(session.handle) then
    provider.focus(session.handle)
    return
  end

  M.open(true)
end

function M.send(text)
  ensure_setup()
  local deps = get_deps()

  local session = deps.session_store.get_active()
  if not session or not session.alive then
    M.open(false)
    session = deps.session_store.get_active()
  end

  local provider = get_provider()
  local ok, err = provider.send(session.handle, text)
  if not ok then
    deps.logger.error("failed to send text: %s", err or "unknown error")
  end
end

function M.is_running()
  local deps = get_deps()
  local session = deps.session_store.get_active()
  if not session or not session.alive then
    return false
  end

  local provider = get_provider()
  return provider.is_alive(session.handle)
end

function M.get_config()
  local deps = get_deps()
  return state.config and deps.vim.deepcopy(state.config) or nil
end

return M
