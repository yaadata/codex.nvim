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

---Clear the tracked non-Codex focus target.
---@param deps table
---@return nil
function M.clear_previous_focus(deps)
  local focus_state = get_focus_state(deps)
  focus_state.previous = nil
  focus_state.last_non_codex = nil
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

---Run a callback while temporarily suppressing autocmd-based focus tracking.
---@generic T1, T2
---@param deps table
---@param fn fun(): T1, T2
---@return T1
---@return T2
local function with_tracking_suspended(deps, fn)
  local focus_state = get_focus_state(deps)
  local previous = focus_state.suspend_tracking == true
  focus_state.suspend_tracking = true
  local ok, result1, result2 = pcall(fn)
  focus_state.suspend_tracking = previous
  if not ok then
    error(result1)
  end
  return result1, result2
end

---Resolves the configured terminal provider implementation.
---@param deps table
---@param config table
---@return codex.Provider provider
---@return string provider_name
function M.get_provider(deps, config)
  return deps.providers.resolve(config.terminal.provider)
end

---Build the on-exit callback used for newly opened or reattached sessions.
---@param deps table
---@return fun(handle: codex.ProviderHandle): nil
local function make_on_exit_callback(deps)
  return function(exited_handle)
    M.mark_session_dead_by_handle(deps, exited_handle)
  end
end

---Store a session spec as the active in-memory session.
---@param deps table
---@param provider_name string
---@param spec codex.SessionSpec
---@return codex.Session
local function create_active_session(deps, provider_name, spec)
  local id = deps.session_store.create({
    handle = spec.handle,
    cmd = spec.cmd,
    cwd = spec.cwd,
    provider_name = provider_name,
  })
  return deps.session_store.get(id)
end

---Return whether a restored candidate is currently visible in a valid window.
---@param deps table
---@param spec codex.RestoredSessionSpec
---@return boolean
local function restored_session_is_visible(deps, spec)
  local api = deps.vim.api or {}
  if type(api.nvim_win_is_valid) ~= "function" then
    return false
  end
  return type(spec.winid) == "number" and api.nvim_win_is_valid(spec.winid)
end

---Attach to a provider-discovered restored session when no alive session is tracked.
---@param deps table
---@param config table
---@param provider codex.Provider
---@param provider_name string
---@return codex.Session|nil
local function restore_session_if_needed(deps, config, provider, provider_name)
  local session = deps.session_store.get_active()
  if M.session_is_alive(session, provider) then
    return session
  end

  if session then
    vdebug(deps, "restore_session_if_needed removing stale active session id=%s", session.id)
    provider.close(session.handle)
    deps.session_store.remove(session.id)
  end

  local discover = provider.discover_restorable
  if type(discover) ~= "function" then
    return nil
  end

  local ok, restored = pcall(discover, config, make_on_exit_callback(deps))
  if not ok then
    deps.logger.error("failed to discover restored Codex sessions: %s", restored)
    return nil
  end
  if type(restored) ~= "table" or #restored == 0 then
    return nil
  end

  table.sort(restored, function(left, right)
    local left_visible = restored_session_is_visible(deps, left)
    local right_visible = restored_session_is_visible(deps, right)
    if left_visible ~= right_visible then
      return left_visible
    end
    return (left.bufnr or 0) > (right.bufnr or 0)
  end)

  local selected = restored[1]
  for idx = 2, #restored do
    local extra = restored[idx]
    provider.close(extra.handle)
  end

  if #restored > 1 then
    deps.logger.warn(
      "multiple restored Codex sessions found; reattached buffer %d and closed %d extras",
      selected.bufnr,
      #restored - 1
    )
  else
    deps.logger.info(
      "reattached restored Codex session (provider=%s, bufnr=%d)",
      provider_name,
      selected.bufnr
    )
  end

  return create_active_session(deps, provider_name, {
    handle = selected.handle,
    cmd = selected.cmd,
    cwd = selected.cwd,
    provider_name = provider_name,
  })
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
      M.record_non_codex_focus(deps, config, session, provider)
      with_tracking_suspended(deps, function()
        return provider.focus(session.handle)
      end)
    end
    return
  end

  -- Close stale session if any
  if session then
    vdebug(deps, "open_session closing stale session id=%s", session.id)
    provider.close(session.handle)
    deps.session_store.remove(session.id)
  end

  if focus then
    M.record_non_codex_focus(deps, config, session, provider)
  end

  local handle = with_tracking_suspended(deps, function()
    return provider.open(
      config.launch.cmd,
      args,
      config.launch.env,
      config,
      focus,
      make_on_exit_callback(deps)
    )
  end)
  vdebug(deps, "open_session created new session provider=%s", provider_name)

  create_active_session(deps, provider_name, {
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
---@return string provider_name
function M.get_active_session_and_provider(deps, config)
  local provider, provider_name = M.get_provider(deps, config)
  local session = deps.session_store.get_active()
  return session, provider, provider_name
end

---Attempt to attach to a restored session for the configured provider.
---@param deps table
---@param config table
---@return codex.Session|nil
function M.restore_session_if_needed(deps, config)
  local provider, provider_name = M.get_provider(deps, config)
  return restore_session_if_needed(deps, config, provider, provider_name)
end

---Return the active session and provider, restoring when needed for command flows.
---@param deps table
---@param config table
---@return codex.Session|nil
---@return codex.Provider
---@return string provider_name
function M.get_or_restore_active_session_and_provider(deps, config)
  local provider, provider_name = M.get_provider(deps, config)
  local session = restore_session_if_needed(deps, config, provider, provider_name)
    or deps.session_store.get_active()
  return session, provider, provider_name
end

---Return whether the current editor focus is on the active Codex buffer.
---@param deps table
---@param config table
---@param session? codex.Session|nil
---@param provider? codex.Provider
---@return boolean
function M.is_session_focused(deps, config, session, provider)
  if not session or not provider then
    session, provider = M.get_active_session_and_provider(deps, config)
  end
  if not session then
    return false
  end
  local term_bufnr = get_session_bufnr(session, provider)
  if type(term_bufnr) ~= "number" then
    return false
  end

  local _, current_buf = get_current_focus(deps)
  return current_buf == term_bufnr
end

---Track the latest non-Codex editor location.
---@param deps table
---@param config table
---@param session? codex.Session|nil
---@param provider? codex.Provider
---@return nil
function M.record_non_codex_focus(deps, config, session, provider, winid, bufnr)
  if get_focus_state(deps).suspend_tracking == true then
    return
  end

  if type(winid) ~= "number" or type(bufnr) ~= "number" then
    winid, bufnr = get_current_focus(deps)
  end
  if type(winid) ~= "number" or type(bufnr) ~= "number" then
    return
  end

  session = session or deps.session_store.get_active()
  provider = provider or M.get_provider(deps, config)
  local term_bufnr = get_session_bufnr(session, provider)
  if type(term_bufnr) == "number" and bufnr == term_bufnr then
    return
  end

  local tracked = {
    winid = winid,
    bufnr = bufnr,
  }
  local focus_state = get_focus_state(deps)
  focus_state.last_non_codex = tracked
  focus_state.previous = tracked
  vdebug(deps, "record_non_codex_focus winid=%d bufnr=%d", winid, bufnr)
end

---Backwards-compatible alias for existing focus-capture call sites.
---@param deps table
---@param config table
---@param session? codex.Session|nil
---@param provider? codex.Provider
---@return nil
function M.remember_previous_focus(deps, config, session, provider)
  M.record_non_codex_focus(deps, config, session, provider)
end

---Opens or reuses a terminal session, replacing stale sessions when needed.
---@param deps table
---@param config table
---@param args string[]
---@param focus boolean
---@return nil
function M.open_session(deps, config, args, focus)
  local session, provider, provider_name =
    M.get_or_restore_active_session_and_provider(deps, config)
  open_or_reuse_session(deps, config, args, focus, provider, provider_name, session)
end

---Closes the active terminal session and resets the send queue.
---@param deps table
---@param config table
---@param send_queue codex.SendQueue|nil
---@return nil
function M.close_session(deps, config, send_queue)
  local session, provider = M.get_or_restore_active_session_and_provider(deps, config)
  if not session then
    vdebug(deps, "close_session no active session")
    if send_queue then
      send_queue:reset()
    end
    return
  end

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
  local session, provider, provider_name =
    M.get_or_restore_active_session_and_provider(deps, config)

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
  local session, provider = M.get_or_restore_active_session_and_provider(deps, config)

  if session and session.alive and provider.is_alive(session.handle) then
    M.record_non_codex_focus(deps, config, session, provider)
    vdebug(deps, "focus_session focusing session id=%s", session.id)
    with_tracking_suspended(deps, function()
      return provider.focus(session.handle)
    end)
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
  local session, provider = M.get_active_session_and_provider(deps, config)
  if not session or not session.alive then
    return false
  end
  return provider.is_alive(session.handle)
end

---Re-focuses the terminal after sends, reopening/toggling when focus is lost.
---@param deps table
---@param session codex.Session
---@param provider codex.Provider
---@param config table
---@return nil
function M.apply_post_send_focus(deps, session, provider, config)
  M.record_non_codex_focus(deps, config, session, provider)
  local focused = with_tracking_suspended(deps, function()
    return provider.focus(session.handle)
  end)
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
  with_tracking_suspended(deps, function()
    return provider.focus(session.handle)
  end)
  vdebug(deps, "apply_post_send_focus re-focused after toggle")
end

---Return to the last tracked non-Codex location when Codex currently has focus.
---@param deps table
---@param config table
---@return boolean ok
---@return string|nil err
function M.unfocus_session(deps, config)
  local session, provider = M.get_active_session_and_provider(deps, config)
  if not M.is_session_focused(deps, config, session, provider) then
    return false, "Codex is not focused"
  end

  local previous = get_focus_state(deps).last_non_codex or get_focus_state(deps).previous
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

  return false, "tracked non-Codex location is no longer available"
end

return M
