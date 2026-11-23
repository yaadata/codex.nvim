local M = {}
local outcome = require("codex.enums.outcome")
local hooks = require("codex.hooks")
local config_mod = require("codex.config")

---@param deps table
---@param config table
---@return string|nil executable
---@return string[] args
local function split_command(deps, config)
  local cfg_mod = (deps and deps.config) or config_mod
  return cfg_mod.split_command(config.launch.cmd)
end

---@param deps table
---@param config table
---@return table
local function snapshot_config(deps, config)
  if deps and deps.vim and type(deps.vim.deepcopy) == "function" then
    return deps.vim.deepcopy(config)
  end
  return vim.deepcopy(config)
end

---@param deps table
---@param session codex.SessionState
---@param fallback_config? table
---@param fallback_provider? codex.Provider
---@return codex.Provider|nil
local function resolve_session_provider(deps, session, fallback_config, fallback_provider)
  if
    session
    and session.provider_name
    and deps.providers
    and type(deps.providers.resolve) == "function"
  then
    local ok, resolved = pcall(deps.providers.resolve, session.provider_name)
    if ok and resolved then
      return resolved
    end
  end
  local cfg = (session and session.config) or fallback_config
  if cfg and deps.providers and type(deps.providers.resolve) == "function" then
    local ok, resolved = pcall(M.get_provider, deps, cfg)
    if ok and resolved then
      return resolved
    end
  end
  return fallback_provider
end

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
---@param session codex.SessionState|nil
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
  local api = deps.vim.api
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
---@param config table
---@return fun(handle: codex.ProviderHandle): nil
local function make_on_exit_callback(deps, owner_config)
  return function(exited_handle)
    M.mark_session_dead_by_handle(deps, exited_handle, owner_config)
  end
end

---Return provider-derived buffer/window fields for hook context when available.
---@param session codex.SessionState
---@param provider codex.Provider
---@return integer|nil bufnr
---@return integer|nil winid
local function get_session_terminal_fields(session, provider)
  local bufnr = nil
  if type(provider.get_bufnr) == "function" then
    bufnr = provider.get_bufnr(session.handle)
  end
  if type(bufnr) ~= "number" and type(session.handle) == "table" then
    bufnr = session.handle.bufnr
  end
  if
    type(bufnr) ~= "number"
    and type(session.handle) == "table"
    and type(session.handle.terminal) == "table"
  then
    bufnr = session.handle.terminal.buf
  end

  local winid = nil
  if type(session.handle) == "table" then
    winid = session.handle.winid
  end
  if
    type(winid) ~= "number"
    and type(session.handle) == "table"
    and type(session.handle.terminal) == "table"
  then
    winid = session.handle.terminal.win
  end
  return bufnr, winid
end

---Build the public lifecycle hook context for a session event.
---@param event string
---@param config table
---@param session codex.SessionState
---@param provider codex.Provider
---@return table
local function make_session_hook_context(event, config, session, provider)
  local bufnr, winid = get_session_terminal_fields(session, provider)
  return {
    event = event,
    profile_name = (session and session.profile_name)
      or (config and config.profile_name)
      or "default",
    provider = session.provider_name,
    bufnr = bufnr,
    winid = winid,
    cmd = session.cmd,
    cwd = session.cwd,
    config = config,
  }
end

---Emit a session lifecycle hook.
---@param deps table
---@param config table
---@param hook_name string
---@param session codex.SessionState
---@param provider codex.Provider
---@return nil
local function dispatch_session_hook(deps, config, hook_name, session, provider)
  hooks.dispatch(
    deps,
    config,
    hook_name,
    make_session_hook_context(hook_name, config, session, provider)
  )
end

---Mark a live session as closed and emit the close hook once.
---@param deps table
---@param config table
---@param session codex.SessionState
---@param provider codex.Provider
---@return nil
local function mark_session_closed(deps, config, session, provider)
  if not session or session.alive == false then
    return
  end
  local effective_config = session.config or config
  local ctx = make_session_hook_context("on_terminal_close", effective_config, session, provider)
  deps.session_store.mark_dead(session.id)
  hooks.dispatch(deps, effective_config, "on_terminal_close", ctx)
end

---Store a session spec as the active in-memory session.
---@param deps table
---@param provider_name string
---@param spec codex.SessionSpec
---@return codex.SessionState
local function create_active_session(deps, provider_name, spec)
  local id = deps.session_store.create({
    handle = spec.handle,
    cmd = spec.cmd,
    cwd = spec.cwd,
    provider_name = provider_name,
    profile_name = spec.profile_name or "default",
    config = spec.config,
  })
  return deps.session_store.get(id)
end

---Attach to a provider-discovered restored session when no alive session is tracked.
---@param deps table
---@param config table
---@param provider codex.Provider
---@param provider_name string
---@param on_attached? fun()
---@return codex.SessionState|nil
---@return boolean? matched
local function restore_session_if_needed(deps, config, provider, provider_name, on_attached)
  local profile_name = config.profile_name or "default"
  local session = deps.session_store.get_active(profile_name)
  if M.session_is_alive(session, provider) then
    return session
  end

  if session then
    vdebug(deps, "restore_session_if_needed removing stale active session id=%s", session.id)
    mark_session_closed(deps, config, session, provider)
    provider.close(session.handle)
    deps.session_store.remove(session.id)
  end

  local discover = provider.discover_restorable
  if type(discover) ~= "function" then
    return nil
  end

  local ok, restored = pcall(discover, config)
  if not ok then
    deps.logger.error("failed to discover restored agent sessions: %s", restored)
    return nil
  end
  if type(restored) ~= "table" or #restored == 0 then
    return nil
  end

  local selected = restored[1]
  local attach = provider.attach_restored
  if type(attach) ~= "function" then
    deps.logger.error("provider %s does not support restored-session attachment", provider_name)
    return nil, true
  end

  local owner_config = snapshot_config(deps, config)
  local attached, attach_err =
    attach(selected.handle, config, make_on_exit_callback(deps, owner_config))
  if not attached then
    deps.logger.error(
      "failed to attach restored agent session (profile=%s, provider=%s, bufnr=%d): %s",
      profile_name,
      provider_name,
      selected.bufnr,
      tostring(attach_err)
    )
    return nil, true
  end

  local restored_session = create_active_session(deps, provider_name, {
    handle = selected.handle,
    cmd = selected.cmd,
    cwd = selected.cwd,
    provider_name = provider_name,
    profile_name = profile_name,
    config = owner_config,
  })
  local ctx =
    make_session_hook_context("on_terminal_restore", owner_config, restored_session, provider)
  ctx.bufnr = ctx.bufnr or selected.bufnr
  ctx.winid = ctx.winid or selected.winid
  deps.logger.info(
    "reattached restored agent session (profile=%s, provider=%s, bufnr=%d)",
    profile_name,
    provider_name,
    selected.bufnr
  )
  if on_attached then
    on_attached()
  end
  hooks.dispatch(deps, owner_config, "on_terminal_restore", ctx)
  return restored_session, true
end

---Opens or reuses a terminal session with a pre-resolved provider.
---@param deps table
---@param config table
---@param args string[]|nil
---@param focus boolean
---@param provider codex.Provider
---@param provider_name string
---@param session codex.SessionState|nil
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
    mark_session_closed(deps, config, session, provider)
    provider.close(session.handle)
    deps.session_store.remove(session.id)
  end

  if focus then
    M.record_non_codex_focus(deps, config, session, provider)
  end

  local executable, configured_args = split_command(deps, config)
  local owner_config = snapshot_config(deps, config)
  local handle = with_tracking_suspended(deps, function()
    return provider.open(
      executable,
      args or configured_args,
      config.launch.env,
      config,
      focus,
      make_on_exit_callback(deps, owner_config)
    )
  end)
  if not handle then
    vdebug(deps, "open_session provider.open returned nil provider=%s", provider_name)
    return
  end
  vdebug(deps, "open_session created new session provider=%s", provider_name)

  local new_session = create_active_session(deps, provider_name, {
    handle = handle,
    cmd = executable,
    cwd = config.launch.cwd or deps.vim.fn.getcwd(),
    provider_name = provider_name,
    profile_name = config.profile_name or "default",
    config = owner_config,
  })
  dispatch_session_hook(deps, owner_config, "on_terminal_open", new_session, provider)
end

---Marks the session that owns `dead_handle` as no longer alive.
---@param deps table
---@param dead_handle codex.ProviderHandle|nil
---@return nil
function M.mark_session_dead_by_handle(deps, dead_handle, config)
  if not dead_handle then
    return
  end

  for _, session in ipairs(deps.session_store.list()) do
    if session.handle == dead_handle then
      local effective_config = session.config or config
      if effective_config then
        local provider = resolve_session_provider(deps, session, effective_config, nil)
        if provider then
          mark_session_closed(deps, effective_config, session, provider)
        else
          deps.session_store.mark_dead(session.id)
        end
      else
        deps.session_store.mark_dead(session.id)
      end
      return
    end
  end
end

---Checks whether a session exists and the provider still reports it alive.
---@param session codex.SessionState|nil
---@param provider codex.Provider
---@return boolean
function M.session_is_alive(session, provider)
  return session ~= nil and session.alive and provider.is_alive(session.handle)
end

---Checks whether a live session is also ready to receive input.
---@param session codex.SessionState|nil
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
---@return codex.SessionState|nil
---@return codex.Provider
---@return string provider_name
function M.get_active_session_and_provider(deps, config)
  local provider, provider_name = M.get_provider(deps, config)
  local session = deps.session_store.get_active(config.profile_name)
  return session, provider, provider_name
end

---Attempt to attach to a restored session for the configured provider.
---@param deps table
---@param config table
---@param on_attached? fun()
---@return codex.SessionState|nil
---@return boolean? matched
function M.restore_session_if_needed(deps, config, on_attached)
  local ok, provider, provider_name = pcall(M.get_provider, deps, config)
  if not ok then
    return nil
  end
  return restore_session_if_needed(deps, config, provider, provider_name, on_attached)
end

---Return the active session and provider, restoring when needed for command flows.
---@param deps table
---@param config table
---@return codex.SessionState|nil
---@return codex.Provider
---@return string provider_name
function M.get_or_restore_active_session_and_provider(deps, config)
  local provider, provider_name = M.get_provider(deps, config)
  local session = restore_session_if_needed(deps, config, provider, provider_name)
    or deps.session_store.get_active(config.profile_name)
  return session, provider, provider_name
end

---Return whether the current editor focus is on the active Codex buffer.
---@param deps table
---@param config table
---@param session? codex.SessionState|nil
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
---@param session? codex.SessionState|nil
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

  session = session or deps.session_store.get_active(config.profile_name)
  provider = provider or M.get_provider(deps, config)
  local term_bufnr = get_session_bufnr(session, provider)
  if type(term_bufnr) == "number" and bufnr == term_bufnr then
    return
  end

  for _, tracked_session in ipairs(deps.session_store.list()) do
    if tracked_session.alive then
      local tracked_provider = resolve_session_provider(deps, tracked_session, config, provider)
      local tracked_bufnr = get_session_bufnr(tracked_session, tracked_provider)
      if type(tracked_bufnr) == "number" and bufnr == tracked_bufnr then
        return
      end
    end
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
---@param session? codex.SessionState|nil
---@param provider? codex.Provider
---@return nil
function M.remember_previous_focus(deps, config, session, provider)
  M.record_non_codex_focus(deps, config, session, provider)
end

---Opens or reuses a terminal session, replacing stale sessions when needed.
---@param deps table
---@param config table
---@param args string[]|nil
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
  mark_session_closed(deps, config, session, provider)
  provider.close(session.handle)
  deps.session_store.remove(session.id)
  if send_queue then
    send_queue:reset()
  end
end

---Closes all tracked sessions across all profiles without selecting other profiles.
---@param deps table
---@return nil
function M.close_all_sessions(deps)
  if not deps or not deps.session_store then
    return
  end

  local snapshot = deps.session_store.list()
  for _, session in ipairs(snapshot) do
    local session_config = session.config
    local provider = resolve_session_provider(deps, session, session_config, nil)
    if provider then
      mark_session_closed(deps, session_config, session, provider)
      provider.close(session.handle)
    else
      deps.session_store.mark_dead(session.id)
    end
    deps.session_store.remove(session.id)
  end

  if type(deps.session_store.reset) == "function" then
    deps.session_store.reset()
  end
end

---Toggles terminal visibility for active session or opens a new one.
---@param deps table
---@param config table
---@return nil
function M.toggle_session(deps, config)
  local session, provider, provider_name =
    M.get_or_restore_active_session_and_provider(deps, config)
  local executable, configured_args = split_command(deps, config)

  if session and session.alive and provider.is_alive(session.handle) then
    vdebug(deps, "toggle_session toggling alive session id=%s", session.id)
    local new_handle =
      provider.toggle(session.handle, executable, configured_args, config.launch.env, config)
    if new_handle then
      vdebug(deps, "toggle_session provider returned replacement handle for id=%s", session.id)
      session.handle = new_handle
    end
    return
  end

  -- No active session — open one
  vdebug(deps, "toggle_session opening new session (no alive active session)")
  open_or_reuse_session(deps, config, configured_args, true, provider, provider_name, session)
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

---Returns whether an active session is currently alive.
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
---@param session codex.SessionState
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
  local executable, configured_args = split_command(deps, config)
  local new_handle =
    provider.toggle(session.handle, executable, configured_args, config.launch.env, config)
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
---@return codex.Outcome ok
---@return codex.Error err
function M.unfocus_session(deps, config)
  local session, provider = M.get_active_session_and_provider(deps, config)
  if not M.is_session_focused(deps, config, session, provider) then
    return outcome.FAILURE, "Codex is not focused"
  end

  local previous = get_focus_state(deps).last_non_codex or get_focus_state(deps).previous
  if type(previous) ~= "table" then
    return outcome.FAILURE, "no previous non-Codex location"
  end

  local api = deps.vim.api

  local term_bufnr = get_session_bufnr(session, provider)

  local function focus_window(winid)
    local ok_focus, focus_err = pcall(api.nvim_set_current_win, winid)
    if not ok_focus then
      return outcome.FAILURE, tostring(focus_err)
    end
    return outcome.SUCCESS
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

  return outcome.FAILURE, "tracked non-Codex location is no longer available"
end

return M
