local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")

---@class codex.PendingSend
---@field text string
---@field open_focus boolean
---@field pre_focus boolean
---@field post_focus boolean
---@field command_path string|nil
---@field on_sent fun()|nil
---@field created_at integer
---@field opened_in_dispatch boolean
---@field reopen_attempted boolean
---@field has_attempted boolean

---@class codex.DispatchSendOpts
---@field open_focus? boolean
---@field pre_focus? boolean
---@field post_focus? boolean
---@field command_path? string
---@field on_sent? fun()

---@class codex.SendDispatchOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field get_send_queue fun(): codex.SendQueue
---@field open_session fun(args: string[], focus: boolean)

local M = {}

---Creates a send dispatch instance with the given accessors.
---@param opts codex.SendDispatchOpts
---@return { dispatch_send: fun(text: string, opts?: codex.DispatchSendOpts): codex.SendResult, string|nil, process_pending_send_item: fun(item: codex.PendingSend): "sent"|"retry"|"drop", string|nil }
function M.create(opts)
  local get_deps = opts.get_deps
  local get_config = opts.get_config
  local get_send_queue = opts.get_send_queue
  local open_session = opts.open_session

  ---Emit a verbose-only debug log when supported.
  ---@param msg string
  ---@param ... any
  ---@return nil
  local function vdebug(msg, ...)
    local deps = get_deps()
    if type(deps.logger.vdebug) == "function" then
      deps.logger.vdebug(msg, ...)
    end
  end

  ---Logs send failures with command-specific context when available.
  ---@param item codex.PendingSend
  ---@param err string|nil
  ---@return nil
  local function log_send_failure(item, err)
    local deps = get_deps()
    local failure = err or "unknown error"
    if item.command_path then
      deps.logger.error("failed to send command %s: %s", item.command_path, failure)
      return
    end
    deps.logger.error("failed to send text: %s", failure)
  end

  ---Logs a startup/readiness timeout for queued sends.
  ---@param item codex.PendingSend
  ---@return nil
  local function log_send_timeout(item)
    log_send_failure(item, "timed out waiting for terminal readiness")
  end

  ---Sends a queued item immediately, including optional focus and callbacks.
  ---@param item codex.PendingSend
  ---@param session codex.Session
  ---@param provider codex.Provider
  ---@return boolean ok
  ---@return string|nil err
  local function send_item_now(item, session, provider)
    local deps = get_deps()
    local config = get_config()

    if item.pre_focus then
      vdebug("send_item_now pre_focus command_path=%s", item.command_path or "<text>")
      provider.focus(session.handle)
    end

    local target = item.command_path or "<text>"
    terminal_io.append_send_debug_entry(deps, target, item.text)

    local ok, err = provider.send(session.handle, item.text)
    if not ok then
      vdebug("send_item_now provider.send failed command_path=%s err=%s", target, err or "unknown")
      return false, err
    end

    if item.on_sent then
      vdebug("send_item_now running on_sent callback command_path=%s", target)
      local callback_ok, callback_err = pcall(item.on_sent)
      if not callback_ok then
        vdebug(
          "send_item_now on_sent callback failed command_path=%s err=%s",
          target,
          callback_err or "unknown"
        )
        return false, callback_err
      end
    end

    if item.post_focus then
      vdebug("send_item_now post_focus command_path=%s", target)
      session_lifecycle.apply_post_send_focus(deps, session, provider, config)
    end
    vdebug("send_item_now sent command_path=%s", target)
    return true
  end

  ---Queue processor: ensures session readiness, retries, or drops timed-out/failed sends.
  ---@param item codex.PendingSend
  ---@return "sent"|"retry"|"drop" outcome
  ---@return string|nil err
  local function process_pending_send_item(item)
    local deps = get_deps()
    local config = get_config()
    local first_attempt = not item.has_attempted
    item.has_attempted = true
    vdebug(
      "process_pending_send_item attempt command_path=%s first_attempt=%s",
      item.command_path or "<text>",
      tostring(first_attempt)
    )

    local session = deps.session_store.get_active()
    local provider = session_lifecycle.get_provider(deps, config)

    if not session or not session.alive then
      vdebug("process_pending_send_item opening session (missing or dead)")
      open_session(config.launch.args, item.open_focus)
      session = deps.session_store.get_active()
      provider = session_lifecycle.get_provider(deps, config)
      if first_attempt then
        item.opened_in_dispatch = true
      end
    end

    if
      session
      and session.alive
      and not provider.is_alive(session.handle)
      and not item.opened_in_dispatch
      and not item.reopen_attempted
    then
      vdebug("process_pending_send_item reopening stale active session")
      open_session(config.launch.args, item.open_focus)
      session = deps.session_store.get_active()
      provider = session_lifecycle.get_provider(deps, config)
      item.reopen_attempted = true
    end

    if
      not session_lifecycle.session_is_alive(session, provider)
      or not session_lifecycle.session_is_ready(session, provider)
    then
      local elapsed_ms = terminal_io.now_ms(deps) - item.created_at
      if elapsed_ms >= config.terminal.startup.timeout_ms then
        vdebug(
          "process_pending_send_item drop timeout command_path=%s elapsed_ms=%d",
          item.command_path or "<text>",
          elapsed_ms
        )
        log_send_timeout(item)
        return "drop"
      end
      vdebug(
        "process_pending_send_item retry waiting for readiness command_path=%s elapsed_ms=%d",
        item.command_path or "<text>",
        elapsed_ms
      )
      return "retry"
    end

    local ok, err = send_item_now(item, session, provider)
    if not ok then
      vdebug(
        "process_pending_send_item drop after send failure command_path=%s err=%s",
        item.command_path or "<text>",
        err or "unknown"
      )
      log_send_failure(item, err)
      return "drop", err
    end
    vdebug("process_pending_send_item sent command_path=%s", item.command_path or "<text>")
    return "sent"
  end

  ---Queues a payload for robust send with startup/retry semantics.
  ---@param text string
  ---@param send_opts? codex.DispatchSendOpts
  ---@return codex.SendResult ok True when payload is sent immediately or queued for retry.
  ---@return string|nil err
  local function dispatch_send(text, send_opts)
    send_opts = send_opts or {}
    local deps = get_deps()
    local item = {
      text = text,
      open_focus = send_opts.open_focus == true,
      pre_focus = send_opts.pre_focus == true,
      post_focus = send_opts.post_focus == true,
      command_path = send_opts.command_path,
      on_sent = send_opts.on_sent,
      created_at = terminal_io.now_ms(deps),
      opened_in_dispatch = false,
      reopen_attempted = false,
      has_attempted = false,
    }
    vdebug(
      "dispatch_send queued command_path=%s open_focus=%s pre_focus=%s post_focus=%s len=%d",
      item.command_path or "<text>",
      tostring(item.open_focus),
      tostring(item.pre_focus),
      tostring(item.post_focus),
      #text
    )
    return get_send_queue():submit(item)
  end

  return {
    dispatch_send = dispatch_send,
    process_pending_send_item = process_pending_send_item,
  }
end

return M
