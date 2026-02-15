local M = {}

---@alias codex.SendResult boolean

local default_deps = {
  config = require("codex.config"),
  logger = require("codex.logger"),
  providers = require("codex.providers"),
  session_store = require("codex.state.session_store"),
  send_queue = require("codex.runtime.send_queue"),
  commands = require("codex.nvim.commands"),
  keymaps = require("codex.nvim.keymaps"),
  formatter = require("codex.context.formatter"),
  selection = require("codex.context.selection"),
  path = require("codex.context.path"),
  vim = vim,
}

local state = {
  config = nil,
  initialized = false,
  deps = nil,
  send_queue = nil,
}

---@class codex.PendingSend
---@field text string
---@field open_focus boolean
---@field pre_focus boolean
---@field post_focus boolean
---@field command_path string|nil
---@field created_at integer
---@field opened_in_dispatch boolean
---@field reopen_attempted boolean
---@field has_attempted boolean

local process_pending_send_item
local BRACKETED_PASTE_START = "\27[200~"
local BRACKETED_PASTE_END = "\27[201~"

---@return table
local function get_deps()
  return state.deps or default_deps
end

---@param opts? table
---@return nil
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
  state.send_queue = deps.send_queue.new({
    vim = deps.vim,
    retry_interval_ms = state.config.terminal.startup.retry_interval_ms,
    process = function(item)
      return process_pending_send_item(item)
    end,
  })
  deps.logger.set_level(state.config.log_level)

  deps.commands.register()
  deps.keymaps.register(state.config)

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

---@return nil
local function ensure_setup()
  if not state.initialized then
    error("codex.nvim: call require('codex').setup() first")
  end
end

---@return codex.Provider provider
---@return string provider_name
local function get_provider()
  return get_deps().providers.resolve(state.config.terminal.provider)
end

---@param deps table
---@param dead_handle codex.ProviderHandle|nil
---@return nil
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

---@param args string[]
---@param focus boolean
---@return nil
local function open_session(args, focus)
  local deps = get_deps()
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
    args,
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

---@param deps table
---@return integer
local function now_ms(deps)
  return deps.vim.uv.now()
end

---@param text string
---@return string
local function encode_bracketed_paste(text)
  return BRACKETED_PASTE_START .. text .. BRACKETED_PASTE_END
end

---@param session codex.Session|nil
---@param provider codex.Provider
---@return boolean
local function session_is_alive(session, provider)
  return session ~= nil and session.alive and provider.is_alive(session.handle)
end

---@param session codex.Session|nil
---@param provider codex.Provider
---@return boolean
local function session_is_ready(session, provider)
  if not session_is_alive(session, provider) then
    return false
  end
  return provider.is_ready(session.handle)
end

---@param session codex.Session
---@param provider codex.Provider
---@return nil
local function apply_post_send_focus(session, provider)
  local focused = provider.focus(session.handle)
  if focused then
    return
  end

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
  provider.focus(session.handle)
end

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

---@param item codex.PendingSend
---@return nil
local function log_send_timeout(item)
  log_send_failure(item, "timed out waiting for terminal readiness")
end

---@param item codex.PendingSend
---@param session codex.Session
---@param provider codex.Provider
---@return boolean ok
---@return string|nil err
local function send_item_now(item, session, provider)
  if item.pre_focus then
    provider.focus(session.handle)
  end

  local ok, err = provider.send(session.handle, item.text)
  if not ok then
    return false, err
  end

  if item.post_focus then
    apply_post_send_focus(session, provider)
  end
  return true
end

---@param item codex.PendingSend
---@return "sent"|"retry"|"drop" outcome
---@return string|nil err
process_pending_send_item = function(item)
  local deps = get_deps()
  local first_attempt = not item.has_attempted
  item.has_attempted = true

  local session = deps.session_store.get_active()
  local provider = get_provider()

  if not session or not session.alive then
    open_session(state.config.args, item.open_focus)
    session = deps.session_store.get_active()
    provider = get_provider()
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
    open_session(state.config.args, item.open_focus)
    session = deps.session_store.get_active()
    provider = get_provider()
    item.reopen_attempted = true
  end

  if not session_is_alive(session, provider) or not session_is_ready(session, provider) then
    local elapsed_ms = now_ms(deps) - item.created_at
    if elapsed_ms >= state.config.terminal.startup.timeout_ms then
      log_send_timeout(item)
      return "drop"
    end
    return "retry"
  end

  local ok, err = send_item_now(item, session, provider)
  if not ok then
    log_send_failure(item, err)
    return "drop", err
  end
  return "sent"
end

---@class codex.DispatchSendOpts
---@field open_focus? boolean
---@field pre_focus? boolean
---@field post_focus? boolean
---@field command_path? string

---@param text string
---@param opts? codex.DispatchSendOpts
---@return codex.SendResult ok True when payload is sent immediately or queued for retry.
---@return string|nil err
local function dispatch_send(text, opts)
  opts = opts or {}
  local deps = get_deps()
  local item = {
    text = text,
    open_focus = opts.open_focus == true,
    pre_focus = opts.pre_focus == true,
    post_focus = opts.post_focus == true,
    command_path = opts.command_path,
    created_at = now_ms(deps),
    opened_in_dispatch = false,
    reopen_attempted = false,
    has_attempted = false,
  }
  return state.send_queue:submit(item)
end

---@param focus? boolean
---@return nil
function M.open(focus)
  ensure_setup()
  if focus == nil then
    focus = true
  end
  open_session(state.config.args, focus)
end

---@return nil
function M.close()
  local deps = get_deps()
  local session = deps.session_store.get_active()
  if not session then
    if state.send_queue then
      state.send_queue:reset()
    end
    return
  end

  local provider = get_provider()
  provider.close(session.handle)
  deps.session_store.remove(session.id)
  if state.send_queue then
    state.send_queue:reset()
  end
end

---@return nil
function M.toggle()
  ensure_setup()
  local deps = get_deps()

  local session = deps.session_store.get_active()
  local provider = get_provider()

  if session and session.alive and provider.is_alive(session.handle) then
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
  open_session(state.config.args, true)
end

---@return nil
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

---@param text string
---@return codex.SendResult ok True when payload is sent immediately or queued.
---@return string|nil err
function M.send(text)
  ensure_setup()
  return dispatch_send(text, {
    open_focus = false,
    post_focus = true,
  })
end

---@return boolean ok
---@return string|nil err
function M.clear_input()
  ensure_setup()
  local deps = get_deps()
  local session = deps.session_store.get_active()
  local provider = get_provider()

  if not session_is_alive(session, provider) then
    return false, "no active Codex session"
  end

  local clear_sequence = deps.vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
  return provider.send(session.handle, clear_sequence)
end

---@param slash_cmd string Slash command name with or without a leading `/`.
---@return codex.SendResult ok True when command payload is sent.
---@return string|nil err
function M.send_command(slash_cmd)
  ensure_setup()
  local normalized = slash_cmd:gsub("^/+", "")
  local command_path = "/" .. normalized
  local command_text = command_path .. "\n"
  return dispatch_send(command_text, {
    open_focus = true,
    pre_focus = true,
    command_path = command_path,
  })
end

---@return codex.SendResult ok True when `/model` is sent.
---@return string|nil err
function M.set_model()
  return M.send_command("model")
end

---@return codex.SendResult ok True when `/status` is sent.
---@return string|nil err
function M.show_status()
  return M.send_command("status")
end

---@return codex.SendResult ok True when `/permissions` is sent.
---@return string|nil err
function M.show_permissions()
  return M.send_command("permissions")
end

---@return codex.SendResult ok True when `/compact` is sent.
---@return string|nil err
function M.compact()
  return M.send_command("compact")
end

---@param instructions? string Optional inline review instructions.
---@return codex.SendResult ok True when `/review` is sent.
---@return string|nil err
function M.review(instructions)
  if instructions == nil or instructions == "" then
    return M.send_command("review")
  end
  return M.send_command("review " .. instructions)
end

---@return codex.SendResult ok True when `/diff` is sent.
---@return string|nil err
function M.show_diff()
  return M.send_command("diff")
end

---@class codex.ResumeOpts
---@field last? boolean Use `codex resume --last` only when launching a new process.

---@param opts? codex.ResumeOpts
---@return codex.SendResult ok True when `/resume` is sent or resume process is opened.
---@return string|nil err
function M.resume(opts)
  ensure_setup()
  opts = opts or {}

  local deps = get_deps()
  local session = deps.session_store.get_active()
  local provider = get_provider()

  if session and session.alive and provider.is_alive(session.handle) then
    return M.send_command("resume")
  end

  local args = { "resume" }
  if opts.last then
    table.insert(args, "--last")
  end

  open_session(args, true)
  return true
end

---@param opts? codex.SelectionOpts Selection range override; falls back to visual marks when omitted.
---@return codex.SendResult ok True when selection payload is sent.
---@return string|nil err
function M.send_selection(opts)
  ensure_setup()
  local deps = get_deps()
  local spec, err = deps.selection.get_visual_selection(deps.vim, opts)
  if not spec then
    deps.logger.error("failed to collect selection: %s", err or "unknown error")
    return false, err
  end

  local payload = deps.formatter.format_selection(spec)
  return dispatch_send(encode_bracketed_paste(payload), {
    open_focus = true,
    post_focus = true,
  })
end

---@param path? string Explicit path to mention. When nil, uses current buffer path.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
function M.add_file(path)
  ensure_setup()
  local deps = get_deps()
  local resolved_path = path
  if resolved_path == nil then
    resolved_path = deps.vim.fn.expand("%:p")
  end

  if not resolved_path or resolved_path == "" then
    local err = "current buffer has no file path"
    deps.logger.error("failed to add file context: %s", err)
    return false, err
  end

  resolved_path = deps.path.to_relative(deps.vim, resolved_path)
  local payload = deps.formatter.format_mention(resolved_path)
  return dispatch_send(encode_bracketed_paste(payload), {
    open_focus = true,
    post_focus = true,
  })
end

---@return boolean
function M.is_running()
  local deps = get_deps()
  local session = deps.session_store.get_active()
  if not session or not session.alive then
    return false
  end

  local provider = get_provider()
  return provider.is_alive(session.handle)
end

---@return table|nil
function M.get_config()
  local deps = get_deps()
  return state.config and deps.vim.deepcopy(state.config) or nil
end

return M
