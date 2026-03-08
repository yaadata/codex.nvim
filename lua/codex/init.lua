local M = {}

---@alias codex.SendResult boolean

local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")
local send_dispatch_mod = require("codex.runtime.send_dispatch")
local mention_mod = require("codex.context.mention")
local wrapper_command_mod = require("codex.context.wrapper_command")
local prompt_ops = require("codex.context.prompt_ops")

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
  selection_send = nil,
  mention = nil,
  wrapper_command = nil,
  focus_state = {
    previous = nil,
    last_non_codex = nil,
  },
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
  state.focus_state.previous = nil
  state.focus_state.last_non_codex = nil
  deps.focus_state = state.focus_state
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

  state.selection_send = deps.selection_send.create({
    get_deps = get_deps,
    get_config = function()
      return state.config
    end,
    dispatch_send = function(text, send_opts)
      return state.send_dispatch.dispatch_send(text, send_opts)
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

  local focus_tracking_group = deps.vim.api.nvim_create_augroup("codex_focus_tracking", {
    clear = true,
  })
  deps.vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = focus_tracking_group,
    callback = function()
      session_lifecycle.record_non_codex_focus(get_deps(), state.config)
    end,
  })

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

---Returns focus to the remembered non-Codex editor location.
---@return boolean ok
---@return string|nil err
function M.unfocus()
  ensure_setup()
  return session_lifecycle.unfocus_session(get_deps(), state.config)
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

---Copies the current terminal input to the unnamed register.
---@return boolean ok
---@return string|nil err
function M.copy_input()
  ensure_setup()
  return prompt_ops.copy_prompt_input(get_deps, function()
    return state.config
  end)
end

---Sends Enter to submit the current terminal input.
---@return boolean ok
---@return string|nil err
function M.submit_input()
  ensure_setup()
  return prompt_ops.submit_with_enter_key(get_deps, function()
    return state.config
  end, "submit_input")
end

---Dispatches a slash command using the wrapper-command flow.
---@param opts codex.ExecuteSlashCommandOpts
---@return codex.SendResult ok True when command payload is sent.
---@return string|nil err
function M.execute_slash_command(opts)
  ensure_setup()
  return state.wrapper_command.execute_slash_command(opts)
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
    return M.execute_slash_command({ command = "resume" })
  end

  local args = { "resume" }
  if opts.last then
    table.insert(args, "--last")
  end

  session_lifecycle.open_session(deps, state.config, args, true)
  return true
end

---Formats current buffer or explicit path reference and sends it as bracketed paste.
---@param opts? codex.SendFileOpts File override via `opts.bufnr` or explicit `opts.path`; set `opts.focus=false` to keep editor focus.
---@return codex.SendResult ok True when file payload is sent.
---@return string|nil err
function M.send_file(opts)
  ensure_setup()
  opts = opts or {}
  local deps = get_deps()
  local should_focus = opts.focus ~= false
  local source_win = nil
  if not should_focus then
    local api = deps.vim.api or {}
    if type(api.nvim_get_current_win) == "function" then
      local ok_win, winid = pcall(api.nvim_get_current_win)
      if ok_win and type(winid) == "number" then
        source_win = winid
      end
    end
  end

  local filepath, err = deps.selection.get_current_buffer_filepath(deps.vim, {
    bufnr = opts.bufnr,
    path = opts.path,
  })
  if not filepath then
    state.selection_send.log_collection_failure("buffer", err)
    return false, err
  end

  local payload = deps.formatter.format_buffer_ref(filepath)
  local ok, send_err =
    state.send_dispatch.dispatch_send(terminal_io.encode_bracketed_paste(payload), {
      open_focus = should_focus,
      post_focus = should_focus,
    })
  if not should_focus and source_win ~= nil then
    local api = deps.vim.api or {}
    if
      type(api.nvim_win_is_valid) == "function" and type(api.nvim_set_current_win) == "function"
    then
      local ok_valid, is_valid = pcall(api.nvim_win_is_valid, source_win)
      if ok_valid and is_valid then
        pcall(api.nvim_set_current_win, source_win)
      end
    end
  end
  return ok, send_err
end

---Formats visual selection and sends it as bracketed paste.
---@param opts? codex.SelectionOpts Selection range override; falls back to visual marks when omitted.
---@return codex.SendResult ok True when selection payload is sent.
---@return string|nil err
function M.send_selection(opts)
  ensure_setup()
  return state.selection_send.send_selection(opts)
end

---Sends `/mention` for a file, auto-submits it, then restores previously captured prompt input.
---@param path? string Explicit file path to mention. When nil, uses current buffer path.
---@param opts? codex.MentionCommandOpts Optional hook(s) for mention flow completion.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
function M.mention_file(path, opts)
  ensure_setup()
  return state.mention.mention_file(path, opts)
end

---Sends `/mention` for a directory, auto-submits it, then restores previously captured prompt input.
---@param path? string Explicit directory path to mention. When nil, uses current buffer's directory.
---@param opts? codex.MentionCommandOpts Optional hook(s) for mention flow completion.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
function M.mention_directory(path, opts)
  ensure_setup()
  return state.mention.mention_directory(path, opts)
end

---Returns whether an active Codex session is currently alive.
---@return boolean
function M.is_running()
  local deps = get_deps()
  return session_lifecycle.is_running(deps, state.config)
end

---Returns whether the current editor focus is on the active Codex session.
---@return boolean
function M.is_focused()
  ensure_setup()
  return session_lifecycle.is_session_focused(get_deps(), state.config)
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
