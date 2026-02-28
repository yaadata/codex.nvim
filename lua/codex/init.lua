local M = {}

---@alias codex.SendResult boolean

local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")
local send_dispatch_mod = require("codex.runtime.send_dispatch")
local mention_mod = require("codex.context.mention")
local wrapper_command_mod = require("codex.context.wrapper_command")
local prompt_submit = require("codex.context.prompt_submit")

local default_deps = {
  config = require("codex.config"),
  logger = require("codex.logger"),
  providers = require("codex.providers"),
  session_store = require("codex.state.session_store"),
  send_queue = require("codex.runtime.send_queue"),
  commands = require("codex.nvim.commands"),
  nvim_visual = require("codex.nvim.visual"),
  formatter = require("codex.context.formatter"),
  selection = require("codex.context.selection"),
  selection_send = require("codex.context.selection_send"),
  path = require("codex.context.path"),
  vim = vim,
}

local state = {
  config = nil,
  initialized = false,
  deps = nil,
  send_queue = nil,
  send_dispatch = nil,
  mention = nil,
  wrapper_command = nil,
}

---Returns runtime dependencies, preferring injected deps from setup.
---@return table
local function get_deps()
  return state.deps or default_deps
end

---Initializes codex.nvim state, commands, queue, and lifecycle hooks.
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

  state.send_dispatch = send_dispatch_mod.create({
    get_deps = get_deps,
    get_config = function()
      return state.config
    end,
    get_send_queue = function()
      return state.send_queue
    end,
    open_session = function(args, focus)
      session_lifecycle.open_session(get_deps(), state.config, args, focus)
    end,
  })

  state.send_queue = deps.send_queue.new({
    vim = deps.vim,
    retry_interval_ms = state.config.terminal.startup.retry_interval_ms,
    process = function(item)
      return state.send_dispatch.process_pending_send_item(item)
    end,
  })

  state.mention = mention_mod.create({
    get_deps = get_deps,
    get_config = function()
      return state.config
    end,
    dispatch_send = function(text, send_opts)
      return state.send_dispatch.dispatch_send(text, send_opts)
    end,
  })

  state.wrapper_command = wrapper_command_mod.create({
    get_deps = get_deps,
    get_config = function()
      return state.config
    end,
    dispatch_send = function(text, send_opts)
      return state.send_dispatch.dispatch_send(text, send_opts)
    end,
  })

  deps.logger.set_level(state.config.log.level)
  if type(deps.logger.set_verbose) == "function" then
    deps.logger.set_verbose(state.config.log.verbose)
  end

  deps.commands.register()

  deps.vim.api.nvim_create_autocmd("VimLeavePre", {
    group = deps.vim.api.nvim_create_augroup("codex_cleanup", { clear = true }),
    callback = function()
      M.close()
    end,
  })

  state.initialized = true
  deps.logger.debug("codex.nvim initialized")

  if state.config.launch.auto_start then
    deps.vim.schedule(function()
      M.open(false)
    end)
  end
end

---Aborts when setup has not been called yet.
---@return nil
local function ensure_setup()
  if not state.initialized then
    error("codex.nvim: call require('codex').setup() first")
  end
end

---Opens Codex terminal, optionally focused (defaults to true).
---@param focus? boolean
---@return nil
function M.open(focus)
  ensure_setup()
  if focus == nil then
    focus = true
  end
  session_lifecycle.open_session(get_deps(), state.config, state.config.launch.args, focus)
end

---Closes the active terminal session and resets the send queue.
---@return nil
function M.close()
  session_lifecycle.close_session(get_deps(), state.config, state.send_queue)
end

---Toggles terminal visibility for active session or opens a new one.
---@return nil
function M.toggle()
  ensure_setup()
  session_lifecycle.toggle_session(get_deps(), state.config)
end

---Focuses active session; opens one if none is running.
---@return nil
function M.focus()
  ensure_setup()
  if not session_lifecycle.focus_session(get_deps(), state.config) then
    M.open(true)
  end
end

---Sends plain text to Codex terminal through the resilient send path.
---@param text string
---@return codex.SendResult ok True when payload is sent immediately or queued.
---@return string|nil err
function M.send(text)
  ensure_setup()
  return state.send_dispatch.dispatch_send(text, {
    open_focus = false,
    post_focus = true,
  })
end

---Sends Ctrl-C to clear the current terminal input.
---@return boolean ok
---@return string|nil err
function M.clear_input()
  ensure_setup()
  local deps = get_deps()
  local session, provider = session_lifecycle.get_active_session_and_provider(deps, state.config)

  if not session_lifecycle.session_is_alive(session, provider) then
    return false, "no active Codex session"
  end

  local clear_sequence = terminal_io.encode_termcode(deps, "<C-c>")
  return provider.send(session.handle, clear_sequence)
end

---Normalizes and dispatches a slash command payload.
---@param slash_cmd string Slash command name with or without a leading `/`.
---@return codex.SendResult ok True when command payload is sent.
---@return string|nil err
function M.send_command(slash_cmd)
  ensure_setup()
  local normalized = slash_cmd:gsub("^/+", "")
  local command_path = "/" .. normalized
  local payload = command_path
  return state.send_dispatch.dispatch_send(payload, {
    open_focus = true,
    pre_focus = true,
    command_path = command_path,
    on_sent = function()
      local submit_ok, submit_err = prompt_submit.submit_with_enter_key(get_deps, function()
        return state.config
      end, command_path)
      if not submit_ok then
        error(submit_err or ("failed to submit " .. command_path))
      end
    end,
  })
end

---Requests model selection in Codex CLI.
---@return codex.SendResult ok True when `/model` is sent.
---@return string|nil err
function M.set_model()
  ensure_setup()
  return state.wrapper_command.dispatch_wrapper_command("model")
end

---Requests current session status in Codex CLI.
---@return codex.SendResult ok True when `/status` is sent.
---@return string|nil err
function M.show_status()
  ensure_setup()
  return state.wrapper_command.dispatch_wrapper_command("status")
end

---Requests permission status in Codex CLI.
---@return codex.SendResult ok True when `/permissions` is sent.
---@return string|nil err
function M.show_permissions()
  ensure_setup()
  return state.wrapper_command.dispatch_wrapper_command("permissions")
end

---Requests context compaction in Codex CLI.
---@return codex.SendResult ok True when `/compact` is sent.
---@return string|nil err
function M.compact()
  ensure_setup()
  return state.wrapper_command.dispatch_wrapper_command("compact")
end

---Starts a review command, with optional inline instructions.
---@param instructions? string Optional inline review instructions.
---@return codex.SendResult ok True when `/review` is sent.
---@return string|nil err
function M.review(instructions)
  ensure_setup()
  if instructions == nil or instructions == "" then
    return state.wrapper_command.dispatch_wrapper_command("review")
  end
  return state.wrapper_command.dispatch_wrapper_command("review " .. instructions)
end

---Requests a diff summary in Codex CLI.
---@return codex.SendResult ok True when `/diff` is sent.
---@return string|nil err
function M.show_diff()
  ensure_setup()
  return state.wrapper_command.dispatch_wrapper_command("diff")
end

---@class codex.ResumeOpts
---@field last? boolean Use `codex resume --last` only when launching a new process.

---Resumes context in-process when possible, otherwise launches `codex resume`.
---@param opts? codex.ResumeOpts
---@return codex.SendResult ok True when `/resume` is sent or resume process is opened.
---@return string|nil err
function M.resume(opts)
  ensure_setup()
  opts = opts or {}

  local deps = get_deps()
  local session, provider = session_lifecycle.get_active_session_and_provider(deps, state.config)

  if session and session.alive and provider.is_alive(session.handle) then
    return state.wrapper_command.dispatch_wrapper_command("resume")
  end

  local args = { "resume" }
  if opts.last then
    table.insert(args, "--last")
  end

  session_lifecycle.open_session(deps, state.config, args, true)
  return true
end

---Formats current buffer reference and sends it as bracketed paste.
---@param opts? codex.SelectionOpts Buffer override via `opts.bufnr`.
---@return codex.SendResult ok True when buffer payload is sent.
---@return string|nil err
function M.send_buffer(opts)
  ensure_setup()
  local deps = get_deps()
  local filepath, err = deps.selection.get_current_buffer_filepath(deps.vim, opts)
  if not filepath then
    deps.selection_send.log_selection_failure(deps, "buffer", err)
    return false, err
  end

  local payload = deps.formatter.format_buffer_ref(filepath)
  return state.send_dispatch.dispatch_send(terminal_io.encode_bracketed_paste(payload), {
    open_focus = true,
    post_focus = true,
  })
end

---Formats visual selection and sends it as bracketed paste.
---@param opts? codex.SelectionOpts Selection range override; falls back to visual marks when omitted.
---@return codex.SendResult ok True when selection payload is sent.
---@return string|nil err
function M.send_selection(opts)
  ensure_setup()
  local deps = get_deps()
  local selection_opts = deps.selection_send.resolve_selection_opts(deps, opts)
  local spec, err = deps.selection.get_visual_selection(deps.vim, selection_opts)
  if not spec then
    deps.selection_send.log_selection_failure(deps, "selection", err)
    return false, err
  end

  if deps.nvim_visual and type(deps.nvim_visual.exit_visual_mode_if_active) == "function" then
    deps.nvim_visual.exit_visual_mode_if_active(deps.vim)
  end

  local payload = deps.formatter.format_selection(spec)
  return state.send_dispatch.dispatch_send(terminal_io.encode_bracketed_paste(payload), {
    open_focus = true,
    post_focus = true,
    on_sent = function()
      local schedule = deps.vim.schedule
      if type(schedule) == "function" then
        local scheduled = pcall(schedule, function()
          local callback_deps = get_deps()
          local session, provider =
            session_lifecycle.get_active_session_and_provider(callback_deps, state.config)
          if not session_lifecycle.session_is_alive(session, provider) then
            return
          end
          pcall(
            session_lifecycle.apply_post_send_focus,
            callback_deps,
            session,
            provider,
            state.config
          )
        end)
        if scheduled then
          return
        end
      end

      local callback_deps = get_deps()
      local session, provider =
        session_lifecycle.get_active_session_and_provider(callback_deps, state.config)
      if not session_lifecycle.session_is_alive(session, provider) then
        return
      end
      pcall(session_lifecycle.apply_post_send_focus, callback_deps, session, provider, state.config)
    end,
  })
end

---Sends `/mention` for a file, auto-submits it, then restores previously captured prompt input.
---@param path? string Explicit file path to mention. When nil, uses current buffer path.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
function M.mention_file(path)
  ensure_setup()
  return state.mention.mention_file(path)
end

---Sends `/mention` for a directory, auto-submits it, then restores previously captured prompt input.
---@param path? string Explicit directory path to mention. When nil, uses current buffer's directory.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
function M.mention_directory(path)
  ensure_setup()
  return state.mention.mention_directory(path)
end

---Returns whether an active Codex session is currently alive.
---@return boolean
function M.is_running()
  local deps = get_deps()
  return session_lifecycle.is_running(deps, state.config)
end

---Returns a deep-copied resolved config for inspection.
---@return table|nil
function M.get_config()
  local deps = get_deps()
  return state.config and deps.vim.deepcopy(state.config) or nil
end

---Returns a snapshot of captured in-memory log entries.
---@return codex.LogEntry[]
function M.get_logs()
  ensure_setup()
  return get_deps().logger.get_logs()
end

---Clears captured in-memory log entries.
---@return nil
function M.clear_logs()
  ensure_setup()
  get_deps().logger.clear_logs()
end

return M
