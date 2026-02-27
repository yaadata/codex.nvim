local M = {}

---Emit a verbose-only debug log when supported.
---@param deps table
---@param msg string
---@param ... any
---@return nil
local function vdebug(deps, msg, ...)
  if type(deps.logger.vdebug) == "function" then
    deps.logger.vdebug(msg, ...)
  end
end

---Resolves the configured terminal provider implementation.
---@param deps table
---@param config table
---@return codex.Provider provider
---@return string provider_name
function M.get_provider(deps, config)
  return deps.providers.resolve(config.terminal.provider)
end

---Opens or reuses a terminal session with a pre-resolved provider.
---@param deps table
---@param config table
---@param args string[]
---@param focus boolean
---@param provider codex.Provider
---@param provider_name string
---@param session codex.Session|nil
---@return nil
local function open_or_reuse_session(deps, config, args, focus, provider, provider_name, session)
  local arg_count = type(args) == "table" and #args or 0
  vdebug(deps, "open_session requested focus=%s args=%d", tostring(focus), arg_count)

  if session and session.alive and provider.is_alive(session.handle) then
    vdebug(deps, "open_session reusing alive active session id=%s", session.id)
    if focus then
      provider.focus(session.handle)
    end
    return
  end

  -- Close stale session if any
  if session then
    vdebug(deps, "open_session closing stale session id=%s", session.id)
    provider.close(session.handle)
    deps.session_store.remove(session.id)
  end

  local handle = provider.open(
    config.launch.cmd,
    args,
    config.launch.env,
    config,
    focus,
    function(exited_handle)
      M.mark_session_dead_by_handle(deps, exited_handle)
    end
  )
  vdebug(deps, "open_session created new session provider=%s", provider_name)

  deps.session_store.create({
    handle = handle,
    cmd = config.launch.cmd,
    cwd = config.launch.cwd or deps.vim.fn.getcwd(),
    provider_name = provider_name,
  })
end

---Marks the session that owns `dead_handle` as no longer alive.
---@param deps table
---@param dead_handle codex.ProviderHandle|nil
---@return nil
function M.mark_session_dead_by_handle(deps, dead_handle)
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

---Checks whether a session exists and the provider still reports it alive.
---@param session codex.Session|nil
---@param provider codex.Provider
---@return boolean
function M.session_is_alive(session, provider)
  return session ~= nil and session.alive and provider.is_alive(session.handle)
end

---Checks whether a live session is also ready to receive input.
---@param session codex.Session|nil
---@param provider codex.Provider
---@return boolean
function M.session_is_ready(session, provider)
  if not M.session_is_alive(session, provider) then
    return false
  end
  return provider.is_ready(session.handle)
end

---Returns the active session and currently configured provider.
---@param deps table
---@param config table
---@return codex.Session|nil
---@return codex.Provider
function M.get_active_session_and_provider(deps, config)
  local session = deps.session_store.get_active()
  local provider = M.get_provider(deps, config)
  return session, provider
end

---Opens or reuses a terminal session, replacing stale sessions when needed.
---@param deps table
---@param config table
---@param args string[]
---@param focus boolean
---@return nil
function M.open_session(deps, config, args, focus)
  local session = deps.session_store.get_active()
  local provider, provider_name = M.get_provider(deps, config)
  open_or_reuse_session(deps, config, args, focus, provider, provider_name, session)
end

---Closes the active terminal session and resets the send queue.
---@param deps table
---@param config table
---@param send_queue codex.SendQueue|nil
---@return nil
function M.close_session(deps, config, send_queue)
  local session = deps.session_store.get_active()
  if not session then
    vdebug(deps, "close_session no active session")
    if send_queue then
      send_queue:reset()
    end
    return
  end

  local provider = M.get_provider(deps, config)
  vdebug(deps, "close_session closing session id=%s", session.id)
  provider.close(session.handle)
  deps.session_store.remove(session.id)
  if send_queue then
    send_queue:reset()
  end
end

---Toggles terminal visibility for active session or opens a new one.
---@param deps table
---@param config table
---@return nil
function M.toggle_session(deps, config)
  local session = deps.session_store.get_active()
  local provider, provider_name = M.get_provider(deps, config)

  if session and session.alive and provider.is_alive(session.handle) then
    vdebug(deps, "toggle_session toggling alive session id=%s", session.id)
    local new_handle = provider.toggle(
      session.handle,
      config.launch.cmd,
      config.launch.args,
      config.launch.env,
      config
    )
    if new_handle then
      vdebug(deps, "toggle_session provider returned replacement handle for id=%s", session.id)
      session.handle = new_handle
    end
    return
  end

  -- No active session — open one
  vdebug(deps, "toggle_session opening new session (no alive active session)")
  open_or_reuse_session(deps, config, config.launch.args, true, provider, provider_name, session)
end

---Focuses active session if alive.
---@param deps table
---@param config table
---@return boolean focused True when an active session was focused.
function M.focus_session(deps, config)
  local session = deps.session_store.get_active()
  local provider = M.get_provider(deps, config)

  if session and session.alive and provider.is_alive(session.handle) then
    vdebug(deps, "focus_session focusing session id=%s", session.id)
    provider.focus(session.handle)
    return true
  end

  vdebug(deps, "focus_session no alive active session")
  return false
end

---Returns whether an active Codex session is currently alive.
---@param deps table
---@param config table
---@return boolean
function M.is_running(deps, config)
  local session = deps.session_store.get_active()
  if not session or not session.alive then
    return false
  end

  local provider = M.get_provider(deps, config)
  return provider.is_alive(session.handle)
end

---Re-focuses the terminal after sends, reopening/toggling when focus is lost.
---@param deps table
---@param session codex.Session
---@param provider codex.Provider
---@param config table
---@return nil
function M.apply_post_send_focus(deps, session, provider, config)
  local focused = provider.focus(session.handle)
  if focused then
    vdebug(deps, "apply_post_send_focus focused active terminal")
    return
  end

  vdebug(deps, "apply_post_send_focus focus failed, toggling provider")
  local new_handle = provider.toggle(
    session.handle,
    config.launch.cmd,
    config.launch.args,
    config.launch.env,
    config
  )
  if new_handle then
    session.handle = new_handle
  end
  provider.focus(session.handle)
  vdebug(deps, "apply_post_send_focus re-focused after toggle")
end

return M
