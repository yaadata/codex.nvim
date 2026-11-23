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
local Profile = require("codex.state.profile")
local config_mod = require("codex.config")
local config_validation = require("codex.config.validation")
local profile_config = require("codex.config.profiles")
local AUGROUP_NAMES = { "codex_focus_tracking", "codex_session_restore" }

local default_deps = {
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
  ---@type codex.ProfileConfig|nil
  config = nil,
  ---@type table<string, codex.Profile>|nil
  profiles = nil,
  ---@type codex.Profile|nil
  profile = nil,
  activation = 0,
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
  ---@type codex.Mention|nil
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

---@type codex.SessionCommands
local session

---@param expected_activation integer
---@param config codex.ProfileConfig|nil
---@return nil
local function schedule_auto_start(expected_activation, config)
  if not config or not config.auto_start then
    return
  end

  local deps = get_deps()
  deps.vim.schedule(function()
    if not state.initialized or not state.config or state.activation ~= expected_activation then
      return
    end
    if session_lifecycle.is_running(get_deps(), state.config) then
      return
    end
    session.open(false)
  end)
end

---@param retry_interval_ms integer
---@return nil
local function reset_and_replace_send_queue(retry_interval_ms)
  local deps = get_deps()
  if state.send_queue then
    if type(state.send_queue.pending_count) == "function" then
      local discarded = state.send_queue:pending_count()
      if discarded > 0 then
        deps.logger.warn("discarded %d pending send(s) on profile switch", discarded)
      end
    end
    state.send_queue:reset()
  end

  state.send_queue = deps.send_queue.new({
    vim = deps.vim,
    retry_interval_ms = retry_interval_ms,
    process = function(item)
      return state.send_dispatch.process_pending_send_item(item)
    end,
  })
end

---@param old_profile codex.Profile|nil
---@param new_profile codex.Profile
---@return boolean ok
---@return string|nil err
local function switch_keymaps(old_profile, new_profile)
  if old_profile == new_profile then
    return true, nil
  end
  local rollback = old_profile and old_profile:stop_keymaps()
  local ok, err = new_profile:start_keymaps()
  if not ok and rollback then
    rollback()
  end
  return ok, err
end

local function activate_profile(profile, config)
  local ok, err = switch_keymaps(state.profile, profile)
  if not ok then
    return false, err
  end
  state.activation = state.activation + 1
  state.profile = profile
  state.config = config
  reset_and_replace_send_queue(config.terminal.startup.retry_interval_ms)
  return true
end

local function restore_profiles()
  local deps = get_deps()
  if deps.session_store.get_active(state.config.profile_name) then
    local ok, running = pcall(session_lifecycle.is_running, deps, state.config)
    if ok and running then
      return true
    end
  end

  local names = {}
  for name in pairs(state.profiles) do
    if name ~= "default" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  names[#names + 1] = "default"
  for _, name in ipairs(names) do
    local profile = state.profiles[name]
    local config = profile == state.profile and state.config or profile:resolve()
    local _, matched = session_lifecycle.restore_session_if_needed(deps, config, function()
      if profile ~= state.profile then
        local activated, err = activate_profile(profile, config)
        if not activated then
          deps.logger.error("failed to activate restored profile %s: %s", name, err)
        end
      end
    end)
    if matched then
      return true
    end
  end
  return false
end

---Schedule recovery after Neovim has recreated any saved terminal buffers.
---@param startup? boolean Allow auto-start only during setup, after recovery.
local function schedule_restore_attempt(startup)
  if not state.initialized or not state.config then
    return
  end

  local expected_activation = state.activation
  get_deps().vim.schedule(function()
    if not state.initialized or not state.config or state.activation ~= expected_activation then
      return
    end
    if
      not restore_profiles()
      and startup
      and state.activation == expected_activation
      and state.config.auto_start
    then
      session.open(false)
    end
  end)
end

---Initializes codex.nvim state, commands, queue, and lifecycle hooks.
---@param opts? codex.SetupOpts|table
---@return nil
local function setup(opts)
  config_validation.validate_setup_type(opts)
  opts = opts or {}

  local deps = {}
  for key, value in pairs(default_deps) do
    deps[key] = value
  end
  for key, value in pairs(opts._deps or {}) do
    deps[key] = value
  end

  local config_opts = deps.vim.deepcopy(opts)
  config_opts._deps = nil

  local profile_opts, base = config_mod.prepare_setup(config_opts)
  local resolved = profile_config.resolve_profiles(profile_opts, base)
  local next_profiles = {}
  for name, entry in pairs(resolved) do
    next_profiles[name] = Profile.new(name, entry.config, entry.keymaps)
  end
  local next_profile = next_profiles.default
  local next_config = next_profile:resolve()

  local prev_profile = state.profile
  local ok_maps, map_err = switch_keymaps(prev_profile, next_profile)
  if not ok_maps then
    error(map_err or "codex: failed to install default profile global keymaps")
  end

  if state.initialized then
    if state.send_queue then
      state.send_queue:reset()
    end
    if state.prompt_buffer then
      state.prompt_buffer:reset()
    end
    session_lifecycle.close_all_sessions(state.deps or deps)
  end

  state.focus_state.previous = nil
  state.focus_state.last_non_codex = nil
  deps.focus_state = state.focus_state
  state.deps = deps

  state.activation = state.activation + 1
  state.profiles = next_profiles
  state.profile = next_profile
  state.config = next_config

  state.send_dispatch = send_dispatch_mod.create({
    get_deps = get_deps,
    get_config = function()
      return state.config
    end,
    get_activation = function()
      return state.activation
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
    get_activation = function()
      return state.activation
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

  local setup_activation = state.activation
  deps.vim.api.nvim_create_autocmd({ "VimEnter", "SessionLoadPost" }, {
    group = deps.vim.api.nvim_create_augroup("codex_session_restore", { clear = true }),
    callback = function(event)
      if event and event.event == "VimEnter" and state.activation ~= setup_activation then
        return
      end
      schedule_restore_attempt()
    end,
  })

  state.initialized = true
  deps.logger.debug("codex.nvim initialized")
  hooks.dispatch(deps, state.config, "on_setup", {
    event = "on_setup",
    profile_name = state.config.profile_name,
    config = state.config,
  })
  if
    state.activation == setup_activation
    and not restore_profiles()
    and state.config.auto_start
  then
    schedule_restore_attempt(true)
  end
end

---Selects a configured launch profile with optional per-activation launch overrides.
---@param name string
---@param launch_overrides? codex.ProfileLaunch
---@return boolean ok
---@return string|nil err
local function set_profile(name, launch_overrides)
  state:ensure_ready()

  if type(name) ~= "string" or name == "" then
    return false, "codex: profile name must be a non-empty string"
  end

  local next_profile = state.profiles and state.profiles[name]
  if not next_profile then
    return false, string.format("codex: unknown profile %q", name)
  end

  local next_config, err = next_profile:resolve(launch_overrides)
  if not next_config then
    return false, err
  end

  local ok_maps, map_err = activate_profile(next_profile, next_config)
  if not ok_maps then
    return false, map_err
  end

  local activation = state.activation
  local restored, matched = session_lifecycle.restore_session_if_needed(get_deps(), next_config)
  if not restored and not matched then
    schedule_auto_start(activation, next_config)
  end
  return true, nil
end

---Returns the currently selected profile name, or nil when uninitialized.
---@return string|nil
local function get_profile()
  if not state.initialized or not state.profile then
    return nil
  end
  return state.profile.name
end

---Deactivate codex.nvim before lazy.nvim unloads its Lua modules.
---@return nil
local function deactivate()
  local deps = state.deps

  state.initialized = false
  state.activation = state.activation + 1

  if state.profile then
    state.profile:stop_keymaps()
  end

  if state.send_queue then
    state.send_queue:reset()
  end

  if state.prompt_buffer then
    state.prompt_buffer:reset()
  end

  if deps then
    session_lifecycle.close_all_sessions(deps)

    if deps.commands and type(deps.commands.unregister) == "function" then
      deps.commands.unregister()
    end

    local api = deps.vim.api
    for _, name in ipairs(AUGROUP_NAMES) do
      pcall(api.nvim_del_augroup_by_name, name)
    end
  end

  state.config = nil
  state.profiles = nil
  state.profile = nil
  state.deps = nil
  state.send_queue = nil
  state.send_dispatch = nil
  state.agent_skill = nil
  state.mention = nil
  state.wrapper_command = nil
  state.focus_state.previous = nil
  state.focus_state.last_non_codex = nil
end

---@param on_sent? fun(session?: codex.SessionState)
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
    local function press_enter(is_submit_still_valid)
      return prompt_ops.submit_with_enter_key(get_deps, function()
        return state.config
      end, "submit_prompt", is_submit_still_valid)
    end
    if state.prompt_buffer:is_empty() then
      return press_enter()
    end
    local deps = get_deps()
    local delay = terminal_io.get_submit_input_delay_ms()
    return deliver_prompt(function(sent_session)
      local expected_activation = state.activation
      local function is_submit_still_valid()
        if not state.initialized or not state.config or state.activation ~= expected_activation then
          return false
        end
        local current_session = deps.session_store.get_active(state.config.profile_name)
        return current_session ~= nil and current_session.alive and current_session == sent_session
      end
      deps.vim.defer_fn(function()
        if not is_submit_still_valid() then
          return
        end
        local ok, err = press_enter(is_submit_still_valid)
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
    session_lifecycle.open_session(get_deps(), state.config, args, focus)
  end,

  ---Closes the active terminal session and resets the send queue.
  ---@return nil
  teardown = function()
    if not state.config then
      return
    end
    session_lifecycle.close_session(get_deps(), state.config, state.send_queue)
  end,

  ---Closes all tracked sessions without changing the selected profile.
  teardown_all = function()
    if not state.initialized then
      return
    end
    state.activation = state.activation + 1
    if state.send_queue then
      state.send_queue:reset()
    end
    session_lifecycle.close_all_sessions(get_deps())
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
    if not state.config then
      return false
    end
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
---@return codex.ProfileConfig|nil
local function get_config()
  local deps = get_deps()
  return state.config and deps.vim.deepcopy(state.config) or nil
end

---@type codex.Api
return {
  get_config = get_config,
  get_profile = get_profile,
  set_profile = set_profile,
  setup = setup,
  deactivate = deactivate,
  prompt_builder = prompt_builder,
  input = input,
  session = session,
  logs = logs,
}
