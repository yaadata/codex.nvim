local terminal_io = require("codex.runtime.terminal_io")
local outcome = require("codex.enums.outcome")
local capture_input_prompt = require("codex.enums.input_prompt")
local prompt_buffer_mod = require("codex.runtime.prompt_buffer")
local session_lifecycle = require("codex.state.session_lifecycle")
local send_dispatch_mod = require("codex.runtime.send_dispatch")
local agent_skill_mod = require("codex.context.agent_skill")
local mention_mod = require("codex.context.mention")
local wrapper_command_mod = require("codex.context.wrapper_command")
local prompt_ops = require("codex.context.prompt_ops")
local hooks = require("codex.hooks")
local AUGROUP_NAMES = { "codex_focus_tracking", "codex_session_restore" }

local default_deps = {
  config = require("codex.config"),
  logger = require("codex.logger"),
  providers = require("codex.providers"),
  commands = require("codex.nvim.commands"),
  session_store = require("codex.state.session_store"),
  send_queue = require("codex.runtime.send_queue"),
  nvim_visual = require("codex.nvim.visual"),
  formatter = require("codex.context.formatter"),
  selection = require("codex.context.selection"),
  selection_add = require("codex.context.selection_add"),
  path = require("codex.context.path"),
  vim = vim,
}

local state = {
  ---@type codex.Config|nil
  config = nil,
  initialized = false,
  deps = nil,
  ---@type codex.AgentSkill|nil
  agent_skill = nil,
  prompt_buffer = nil,
  ---@type codex.SendQueue|nil
  send_queue = nil,
  ---@type codex.SendDispatch|nil
  send_dispatch = nil,
  ---@type codex.SelectionAdd|nil
  selection_add = nil,
  ---@type codex.MentionOpts|nil
  mention = nil,
  wrapper_command = nil,
  focus_state = {
    previous = nil,
    last_non_codex = nil,
  },
}

---Aborts when setup has not been called yet.
---@return nil
function state:ensure_ready()
  if not self.initialized then
    error("codex.nvim: call require('codex').setup() first")
  end
end

---Returns runtime dependencies, preferring injected deps from setup.
---@return table
local function get_deps()
  return state.deps or default_deps
end

---Schedule a restore attempt after startup/session restore work has finished.
---@return nil
local function schedule_restore_attempt()
  if not state.initialized or not state.config then
    return
  end

  local deps = get_deps()
  deps.vim.schedule(function()
    if not state.initialized or not state.config then
      return
    end
    session_lifecycle.restore_session_if_needed(get_deps(), state.config)
  end)
end

---@type codex.Session
local session

---Initializes codex.nvim state, commands, queue, and lifecycle hooks.
---@param opts? table
---@return nil
local function setup(opts)
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

  state.prompt_buffer = prompt_buffer_mod.new()
  state.selection_add = deps.selection_add.create({
    get_deps = get_deps,
    get_prompt_buffer = function()
      return state.prompt_buffer
    end,
  })
  state.send_queue = deps.send_queue.new({
    vim = deps.vim,
    retry_interval_ms = state.config.terminal.startup.retry_interval_ms,
    process = function(item)
      return state.send_dispatch.process_pending_send_item(item)
    end,
  })

  state.agent_skill = agent_skill_mod.create({
    dispatch_send = function(text)
      return state.send_dispatch.dispatch_send(text)
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

  deps.commands.register(require("codex"))

  local focus_tracking_group = deps.vim.api.nvim_create_augroup("codex_focus_tracking", {
    clear = true,
  })
  deps.vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = focus_tracking_group,
    callback = function()
      session_lifecycle.record_non_codex_focus(get_deps(), state.config)
    end,
  })

  deps.vim.api.nvim_create_autocmd({ "VimEnter", "SessionLoadPost" }, {
    group = deps.vim.api.nvim_create_augroup("codex_session_restore", { clear = true }),
    callback = function()
      schedule_restore_attempt()
    end,
  })

  state.initialized = true
  deps.logger.debug("codex.nvim initialized")
  hooks.dispatch(deps, state.config, "on_setup", {
    event = "on_setup",
    config = state.config,
  })
  session_lifecycle.restore_session_if_needed(get_deps(), state.config)

  if state.config.launch.auto_start then
    deps.vim.schedule(function()
      if not state.initialized then
        return
      end
      session.open(false)
    end)
  end
end

---Deactivate codex.nvim before lazy.nvim unloads its Lua modules.
---@return nil
local function deactivate()
  local deps = state.deps
  local config = state.config

  state.initialized = false

  if state.send_queue then
    state.send_queue:reset()
  end

  if state.prompt_buffer then
    state.prompt_buffer:reset()
  end

  if deps and config then
    session_lifecycle.close_session(deps, config, nil)
  end

  if deps then
    if deps.commands and type(deps.commands.unregister) == "function" then
      deps.commands.unregister()
    end

    local api = deps.vim.api
    for _, name in ipairs(AUGROUP_NAMES) do
      pcall(api.nvim_del_augroup_by_name, name)
    end

    if deps.session_store and type(deps.session_store.reset) == "function" then
      deps.session_store.reset()
    end
  end

  state.config = nil
  state.deps = nil
  state.send_queue = nil
  state.send_dispatch = nil
  state.agent_skill = nil
  state.mention = nil
  state.wrapper_command = nil
  state.focus_state.previous = nil
  state.focus_state.last_non_codex = nil
end

session = {
  ---Opens Codex terminal, optionally focused (defaults to true).
  ---@param focus? boolean
  ---@param args? string[] Overrides configured launch arguments
  ---@return nil
  open = function(focus, args)
    state:ensure_ready()
    if focus == nil then
      focus = true
    end
    session_lifecycle.open_session(
      get_deps(),
      state.config,
      args or state.config.launch.args,
      focus
    )
  end,

  ---Resumes context in-process when possible, otherwise launches `codex resume`.
  ---@param opts? codex.ResumeOpts
  ---@return codex.Outcome ok True when `/resume` is sent or resume process is opened.
  ---@return string|nil err
  resume = function(opts)
    state:ensure_ready()
    opts = opts or {}

    local deps = get_deps()
    if session.is_running() then
      return require("codex").execute_slash_command({ command = "resume" })
    end

    local args = { "resume" }
    if opts.last then
      table.insert(args, "--last")
    end

    session_lifecycle.open_session(deps, state.config, args, true)
    return true
  end,

  ---Closes the active terminal session and resets the send queue.
  ---@return nil
  close = function()
    session_lifecycle.close_session(get_deps(), state.config, state.send_queue)
  end,

  ---Toggles terminal visibility for active session or opens a new one.
  ---@return nil
  toggle = function()
    state:ensure_ready()
    session_lifecycle.toggle_session(get_deps(), state.config)
  end,

  ---Focuses active session; opens one if none is running.
  ---@return nil
  focus = function()
    state:ensure_ready()
    if not session_lifecycle.focus_session(get_deps(), state.config) then
      session.open(true)
    end
  end,

  ---Returns focus to the remembered non-Codex editor location.
  ---@return boolean ok
  ---@return string|nil err
  unfocus = function()
    state:ensure_ready()
    return session_lifecycle.unfocus_session(get_deps(), state.config)
  end,

  ---Returns whether an active Codex session is currently alive.
  ---@return boolean
  is_running = function()
    local deps = get_deps()
    return session_lifecycle.is_running(deps, state.config)
  end,

  ---Returns whether the current editor focus is on the active Codex session.
  ---@return boolean
  is_focused = function()
    state:ensure_ready()
    return session_lifecycle.is_session_focused(get_deps(), state.config)
  end,
}

---@param on_sent? fun()
---@return codex.Outcome ok True when payload is sent immediately or queued
---@return codex.Error err
local function deliver_prompt(on_sent)
  state:ensure_ready()
  if state.prompt_buffer:is_empty() then
    return outcome.FAILURE, "no queued message"
  end
  local text = state.prompt_buffer:take()
  text = terminal_io.encode_bracketed_paste(text)
  return state.send_dispatch.dispatch_send(text, {
    open_focus = false,
    post_focus = true,
    on_sent = on_sent,
  })
end

---@type codex.PromptBuilder
local prompt_builder = {
  ---Adds to a message buffer to be sent to the codex agent.
  ---To send the buffer, use [send] or [submit] lua commands
  ---@param text string
  add = function(text)
    state:ensure_ready()
    state.prompt_buffer:add(text)
    return outcome.SUCCESS
  end,

  ---Formats current buffer or explicit path reference and adds it a buffer to be sent by either .
  ---@param opts? codex.AddFileOpts File override via `opts.bufnr` or explicit `opts.path`; set `opts.focus=false` to keep editor focus.
  ---@return codex.Outcome ok
  ---@return string|nil err
  add_file = function(opts)
    state:ensure_ready()
    opts = opts or {}
    local deps = get_deps()
    local filepath, err = deps.selection.get_current_buffer_filepath(deps.vim, {
      bufnr = opts.bufnr,
      path = opts.path,
    })
    if not filepath then
      state.selection_add.log_collection_failure("buffer", err)
      return false, err
    end

    local payload = deps.formatter.format_buffer_ref(filepath)
    state.prompt_buffer:add(payload)
    return true, nil
  end,

  ---Formats and adds a skill to the prompt buffer. The buffer can be sent by either
  --- [send] or [submit] apis.
  ---@param opts codex.AgentSkillOptions
  ---@return codex.Outcome ok
  ---@return codex.Error err
  add_skill = function(opts)
    state:ensure_ready()
    local payload, err = state.agent_skill.prompt_payload(opts)
    if err ~= nil then
      return outcome.FAILURE, err
    end
    state.prompt_buffer:add(payload)
    return outcome.SUCCESS
  end,

  ---Formats visual selection and buffers the text to be sent by either
  --- [send] or [submit] apis.
  ---@param opts? codex.SelectionOpts Selection range override; falls back to visual marks when omitted.
  ---@return codex.Outcome ok True when selection payload is buffered.
  ---@return codex.Error err
  add_selection = function(opts)
    state:ensure_ready()
    return state.selection_add.buffer(opts)
  end,

  clear = function()
    state:ensure_ready()
    state.prompt_buffer:reset()
    return outcome.SUCCESS
  end,

  ---@return codex.PromptBufferArray
  peak = function()
    state:ensure_ready()
    return state.prompt_buffer:peak()
  end,

  ---Sends the built up message in the send buffer. This message is built from codex.add_text.
  ---@return codex.Outcome ok True when payload is sent immediately or queued.
  ---@return codex.Error err
  --TODO: On send failure, we should restore the prompt builder to its pre-send state
  send = function()
    return deliver_prompt()
  end,

  ---Sends Enter to submit the current prompt buffer.
  ---@return codex.Outcome ok
  ---@return codex.Error err
  submit = function()
    state:ensure_ready()
    local function press_enter()
      return prompt_ops.submit_with_enter_key(get_deps, function()
        return state.config
      end, "submit_prompt")
    end
    if state.prompt_buffer:is_empty() then
      return press_enter()
    end
    local deps = get_deps()
    local delay = terminal_io.get_submit_input_delay_ms()
    return deliver_prompt(function()
      deps.vim.defer_fn(function()
        local ok, err = press_enter()
        if not ok then
          deps.logger.error("failed to submit prompt: %s", err or "unknown error")
        end
      end, delay)
    end)
  end,

  ---Combines the prompt builder buffer with the input
  ---@param current_buffer codex.PromptBufferArray
  ---@return nil
  join = function(current_buffer)
    state:ensure_ready()
    state.prompt_buffer:join(current_buffer)
  end,
}

---@type codex.Input
local input = {
  ---Sends Ctrl-C to clear the current terminal input.
  ---@return codex.Outcome ok
  ---@return codex.Error err
  clear = function()
    state:ensure_ready()
    local deps = get_deps()
    local active_session, provider =
      session_lifecycle.get_or_restore_active_session_and_provider(deps, state.config)

    if not session_lifecycle.session_is_alive(active_session, provider) then
      return false, "no active Codex session"
    end

    local clear_sequence = terminal_io.encode_termcode(deps, "<C-c>")
    return provider.send(active_session.handle, clear_sequence)
  end,

  ---Copies the current terminal input to the unnamed register.
  ---@return codex.Outcome ok
  ---@return codex.Error err
  copy = function()
    state:ensure_ready()
    return prompt_ops.copy_prompt_input(get_deps, function()
      return state.config
    end)
  end,

  ---Get the current terminal input
  ---@return codex.Outcome ok
  ---@return string? input
  get = function()
    state:ensure_ready()
    local captured_input, result, _ = prompt_ops.capture_active_prompt_input(get_deps, function()
      return state.config
    end)
    if result == capture_input_prompt.CAPTURED or result == capture_input_prompt.NO_INPUT then
      return outcome.SUCCESS, captured_input
    end
    return outcome.FAILURE
  end,

  ---Send keystrokes directly to the terminal buffer
  ---Example:
  ---
  ---```lua
  ---local api = require('codex')
  ---api.input.feedkey('<A-m>')
  ---```
  ---@param key string
  ---@return codex.Outcome ok
  ---@return codex.Error err
  feedkey = function(key)
    state:ensure_ready()
    local deps = get_deps()
    local toggle = false
    if not session.is_focused() then
      toggle = true
      session.focus()
    end
    local feed = terminal_io.encode_termcode(deps, key)
    deps.vim.api.nvim_feedkeys(feed, "n", true)
    if toggle then
      session.unfocus()
    end
    return true
  end,
}

---@type codex.Logs
local logs = {
  ---Returns a snapshot of captured in-memory log entries.
  ---@return codex.LogEntry[]
  get = function()
    state:ensure_ready()
    return get_deps().logger.get_logs()
  end,

  ---Clears captured in-memory log entries.
  ---@return nil
  clear = function()
    state:ensure_ready()
    get_deps().logger.clear_logs()
  end,
}

---Returns a deep-copied resolved config for inspection.
---@return table|nil
local function get_config()
  local deps = get_deps()
  return state.config and deps.vim.deepcopy(state.config) or nil
end

---@type codex.Api
return {
  get_config = get_config,
  setup = setup,
  deactivate = deactivate,
  prompt_builder = prompt_builder,
  input = input,
  session = session,
  logs = logs,
}
