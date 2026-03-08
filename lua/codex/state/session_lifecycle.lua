local M = {}

---Return the shared focus-state table, creating one when missing.
---@param deps table
---@return table
local function get_focus_state(deps)
  if type(deps.focus_state) ~= "table" then
    deps.focus_state = {}
  end
  return deps.focus_state
end

---Clear the remembered non-Codex focus target.
---@param deps table
---@return nil
function M.clear_previous_focus(deps)
  get_focus_state(deps).previous = nil
end

---Return the active Codex terminal buffer number when available.
---@param session codex.Session|nil
---@param provider codex.Provider
---@return integer|nil
local function get_session_bufnr(session, provider)
  if not M.session_is_alive(session, provider) or type(provider.get_bufnr) ~= "function" then
    return nil
  end
  return provider.get_bufnr(session.handle)
end

---Return the current editor window and buffer when available.
---@param deps table
---@return integer|nil
---@return integer|nil
local function get_current_focus(deps)
  local api = deps.vim.api or {}
  if
    type(api.nvim_get_current_win) ~= "function" or type(api.nvim_get_current_buf) ~= "function"
  then
    return nil, nil
  end

  local ok_win, winid = pcall(api.nvim_get_current_win)
  local ok_buf, bufnr = pcall(api.nvim_get_current_buf)
  if not ok_win or not ok_buf then
    return nil, nil
  end

  if type(winid) ~= "number" or type(bufnr) ~= "number" then
    return nil, nil
  end
  return winid, bufnr
end

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
      M.remember_previous_focus(deps, config, session, provider)
      provider.focus(session.handle)
    end
    return
  end

  -- Close stale session if any
  if session then
    vdebug(deps, "open_session closing stale session id=%s", session.id)
    provider.close(session.handle)
    deps.session_store.remove(session.id)
    M.clear_previous_focus(deps)
  end

  if focus then
    M.remember_previous_focus(deps, config, session, provider)
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

---Return whether the current editor focus is on the active Codex buffer.
---@param deps table
---@param config table
---@param session? codex.Session|nil
---@param provider? codex.Provider
---@return boolean
function M.is_session_focused(deps, config, session, provider)
  session = session or deps.session_store.get_active()
  if not session then
    return false
  end
  provider = provider or M.get_provider(deps, config)
  local term_bufnr = get_session_bufnr(session, provider)
  if type(term_bufnr) ~= "number" then
    return false
  end

  local _, current_buf = get_current_focus(deps)
  return current_buf == term_bufnr
end

---Remember the current non-Codex focus target before Codex steals focus.
---@param deps table
---@param config table
---@param session? codex.Session|nil
---@param provider? codex.Provider
---@return nil
function M.remember_previous_focus(deps, config, session, provider)
  if M.is_session_focused(deps, config, session, provider) then
    return
  end

  local winid, bufnr = get_current_focus(deps)
  if type(winid) ~= "number" or type(bufnr) ~= "number" then
    return
  end

  get_focus_state(deps).previous = {
    winid = winid,
    bufnr = bufnr,
  }
  vdebug(deps, "remember_previous_focus winid=%d bufnr=%d", winid, bufnr)
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
    M.clear_previous_focus(deps)
    if send_queue then
      send_queue:reset()
    end
    return
  end

  local provider = M.get_provider(deps, config)
  vdebug(deps, "close_session closing session id=%s", session.id)
  provider.close(session.handle)
  deps.session_store.remove(session.id)
  M.clear_previous_focus(deps)
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
    M.remember_previous_focus(deps, config, session, provider)
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
  M.remember_previous_focus(deps, config, session, provider)
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

---Return to the remembered non-Codex location when Codex currently has focus.
---@param deps table
---@param config table
---@return boolean ok
---@return string|nil err
function M.unfocus_session(deps, config)
  local session, provider = M.get_active_session_and_provider(deps, config)
  if not M.is_session_focused(deps, config, session, provider) then
    return false, "Codex is not focused"
  end

  local previous = get_focus_state(deps).previous
  if type(previous) ~= "table" then
    return false, "no previous non-Codex location"
  end

  local api = deps.vim.api or {}
  if
    type(api.nvim_win_is_valid) ~= "function"
    or type(api.nvim_set_current_win) ~= "function"
    or type(api.nvim_win_get_buf) ~= "function"
    or type(api.nvim_list_wins) ~= "function"
  then
    return false, "editor focus restoration is unavailable"
  end

  local term_bufnr = get_session_bufnr(session, provider)

  local function focus_window(winid)
    local ok_focus, focus_err = pcall(api.nvim_set_current_win, winid)
    if not ok_focus then
      return false, tostring(focus_err)
    end
    M.clear_previous_focus(deps)
    return true
  end

  local ok_valid, is_valid = pcall(api.nvim_win_is_valid, previous.winid)
  if ok_valid and is_valid then
    local ok_buf, win_bufnr = pcall(api.nvim_win_get_buf, previous.winid)
    if ok_buf and win_bufnr == previous.bufnr and win_bufnr ~= term_bufnr then
      return focus_window(previous.winid)
    end
  end

  local ok_wins, wins = pcall(api.nvim_list_wins)
  if ok_wins and type(wins) == "table" then
    for _, winid in ipairs(wins) do
      local ok_win_valid, win_valid = pcall(api.nvim_win_is_valid, winid)
      if ok_win_valid and win_valid then
        local ok_buf, win_bufnr = pcall(api.nvim_win_get_buf, winid)
        if ok_buf and win_bufnr == previous.bufnr and win_bufnr ~= term_bufnr then
          return focus_window(winid)
        end
      end
    end
  end

  return false, "remembered buffer is no longer visible"
end

return M
