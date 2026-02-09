local M = {}

---@alias codex.SendResult boolean

local default_deps = {
  config = require("codex.config"),
  logger = require("codex.logger"),
  providers = require("codex.providers"),
  session_store = require("codex.state.session_store"),
  commands = require("codex.nvim.commands"),
  keymaps = require("codex.nvim.keymaps"),
  formatter = require("codex.context.formatter"),
  selection = require("codex.context.selection"),
  vim = vim,
}

local state = {
  config = nil,
  initialized = false,
  deps = nil,
}

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
    return
  end

  local provider = get_provider()
  provider.close(session.handle)
  deps.session_store.remove(session.id)
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
---@return nil
function M.send(text)
  ensure_setup()
  local deps = get_deps()

  local session = deps.session_store.get_active()
  local provider = get_provider()
  if not session or not session.alive or not provider.is_alive(session.handle) then
    M.open(false)
    session = deps.session_store.get_active()
  end

  local ok, err = provider.send(session.handle, text)
  if not ok then
    deps.logger.error("failed to send text: %s", err or "unknown error")
    return
  end

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

---@param slash_cmd string Slash command name with or without a leading `/`.
---@return codex.SendResult ok True when command payload is sent.
---@return string|nil err
function M.send_command(slash_cmd)
  ensure_setup()
  local deps = get_deps()

  local normalized = slash_cmd:gsub("^/+", "")
  local command_path = "/" .. normalized
  local command_text = command_path .. "\n"

  local session = deps.session_store.get_active()
  local provider = get_provider()
  if session and session.alive and provider.is_alive(session.handle) then
    provider.focus(session.handle)
  else
    open_session(state.config.args, true)
    session = deps.session_store.get_active()
  end

  local ok, err = provider.send(session.handle, command_text)
  if not ok then
    deps.logger.error("failed to send command %s: %s", command_path, err or "unknown error")
  end
  return ok, err
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
  M.send(payload)
  return true
end

---@param path? string Explicit path to mention. When nil, uses `vim.fn.expand("%:p")`.
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

  local payload = deps.formatter.format_mention(resolved_path)
  M.send(payload)
  return true
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
