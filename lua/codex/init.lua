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
---@field on_sent fun()|nil
---@field created_at integer
---@field opened_in_dispatch boolean
---@field reopen_attempted boolean
---@field has_attempted boolean

local process_pending_send_item
local session_is_alive
local dispatch_mention
local BRACKETED_PASTE_START = "\27[200~"
local BRACKETED_PASTE_END = "\27[201~"
local SLASH_COMMAND_SUBMIT_SEQUENCE = "\n"
local CODEX_ENTER_SEQUENCE = "\r\n"
local SUBMIT_INPUT_DELAY_MS = 40
local PROMPT_CAPTURE_LOOKBACK_LINES = 8
-- Allow Codex CLI enough time to process submit and render a fresh prompt
-- before re-applying captured prompt input.
local RESTORE_INPUT_DELAY_MS = 200

---Returns runtime dependencies, preferring injected deps from setup.
---@return table
local function get_deps()
  return state.deps or default_deps
end

---Initializes codex.nvim state, commands, keymaps, queue, and lifecycle hooks.
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

---Aborts when setup has not been called yet.
---@return nil
local function ensure_setup()
  if not state.initialized then
    error("codex.nvim: call require('codex').setup() first")
  end
end

---Resolves the configured terminal provider implementation.
---@return codex.Provider provider
---@return string provider_name
local function get_provider()
  return get_deps().providers.resolve(state.config.terminal.provider)
end

---Marks the session that owns `dead_handle` as no longer alive.
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

---Opens or reuses a terminal session, replacing stale sessions when needed.
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

---Returns current monotonic time in milliseconds.
---@param deps table
---@return integer
local function now_ms(deps)
  return deps.vim.uv.now()
end

---Wraps text with bracketed-paste control sequences.
---@param text string
---@return string
local function encode_bracketed_paste(text)
  return BRACKETED_PASTE_START .. text .. BRACKETED_PASTE_END
end

---Expands a Vim key notation into terminal keycodes.
---@param key string
---@return string
local function encode_termcode(key)
  local deps = get_deps()
  return deps.vim.api.nvim_replace_termcodes(key, true, false, true)
end

---Builds key sequence that clears the active prompt line before `/mention`.
---@return string
local function encode_clear_line_for_mention()
  return table.concat({
    encode_termcode("<C-e>"),
    encode_termcode("<C-u>"),
  })
end

---Normalizes terminal buffer lines by stripping CR-tail artifacts and ANSI CSI codes.
---@param line string
---@return string
local function normalize_terminal_line(line)
  -- Keep only the visible tail when terminals use carriage-return updates.
  local normalized = line:match("[^\r]*$") or line
  -- Strip common ANSI CSI escapes that can leak into terminal buffer lines.
  normalized = normalized:gsub("\27%[[0-9;?]*[ -/]*[@-~]", "")
  return normalized
end

---Parses a prompt line and extracts typed input and its starting column.
---@param line string
---@return { input: string, input_start_col: integer }|nil
local function parse_prompt_input(line)
  if type(line) ~= "string" then
    return nil
  end

  local normalized = normalize_terminal_line(line)
  local leading_whitespace = #(normalized:match("^%s*") or "")
  local trimmed = normalized:gsub("^%s+", "")
  if trimmed == "" then
    return nil
  end

  local prompt_end = trimmed:find("%s")
  if prompt_end == nil or prompt_end <= 1 then
    return nil
  end

  local prompt_token = trimmed:sub(1, prompt_end - 1)
  if prompt_token:find("[%w/]") then
    return nil
  end

  local input = trimmed:sub(prompt_end + 1)
  if input == "" then
    return nil
  end

  return {
    input = input,
    input_start_col = leading_whitespace + prompt_end,
  }
end

---Emits payload debug logging for outbound terminal sends.
---@param target string
---@param text string
---@return nil
local function append_send_debug_entry(target, text)
  local deps = get_deps()
  deps.logger.debug("send payload target=%s len=%d", target, #text)
end

---Returns the active session and currently configured provider.
---@return codex.Session|nil
---@return codex.Provider
local function get_active_session_and_provider()
  local deps = get_deps()
  local session = deps.session_store.get_active()
  local provider = get_provider()
  return session, provider
end

---Adds a line number candidate once, if valid.
---@param values integer[]
---@param seen table<integer, boolean>
---@param line integer|nil
---@return nil
local function add_candidate_line(values, seen, line)
  if type(line) ~= "number" or line < 1 or seen[line] then
    return
  end
  table.insert(values, line)
  seen[line] = true
end

---Best-effort capture of current terminal prompt input for post-mention restore.
---@return string|nil
local function capture_terminal_prompt_input()
  local deps = get_deps()
  local session, provider = get_active_session_and_provider()
  if not session_is_alive(session, provider) or type(provider.get_bufnr) ~= "function" then
    return nil
  end

  local bufnr = provider.get_bufnr(session.handle)
  local api = deps.vim.api
  if type(bufnr) ~= "number" then
    return nil
  end
  local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
  if not ok_valid or not is_valid then
    return nil
  end

  local ok_count, line_count = pcall(api.nvim_buf_line_count, bufnr)
  if not ok_count or type(line_count) ~= "number" or line_count < 1 then
    return nil
  end

  local candidates = {}
  local seen = {}
  local cursor_line = nil
  local cursor_col = nil

  local ok_winid, winid = pcall(deps.vim.fn.bufwinid, bufnr)
  if ok_winid and type(winid) == "number" and winid > 0 then
    local ok_cursor, cursor = pcall(api.nvim_win_get_cursor, winid)
    if ok_cursor and type(cursor) == "table" then
      cursor_line = cursor[1]
      cursor_col = cursor[2]
      add_candidate_line(candidates, seen, cursor_line)
    end
  end

  for offset = 0, PROMPT_CAPTURE_LOOKBACK_LINES do
    add_candidate_line(candidates, seen, line_count - offset)
  end

  for _, line_number in ipairs(candidates) do
    local ok_lines, lines =
      pcall(api.nvim_buf_get_lines, bufnr, line_number - 1, line_number, false)
    if ok_lines and type(lines) == "table" then
      local line = lines[1]
      local parsed = parse_prompt_input(line)
      if parsed ~= nil then
        if
          line_number == cursor_line
          and type(cursor_col) == "number"
          and cursor_col <= parsed.input_start_col
        then
          -- Cursor is parked at input start; treat trailing ghost text as not-yet-accepted.
          return nil
        end
        if parsed.input ~= "" then
          return parsed.input
        end
      end
    end
  end

  return nil
end

---Submits the current prompt using Enter, with provider-send fallback.
---@param target string
---@return boolean ok
---@return string|nil err
local function submit_with_enter_key(target)
  local deps = get_deps()
  local session, provider = get_active_session_and_provider()
  if not session_is_alive(session, provider) then
    return false, "no active Codex session"
  end

  provider.focus(session.handle)
  local enter_termcode = encode_termcode("<CR>")
  local feedkeys = deps.vim.api.nvim_feedkeys
  if type(feedkeys) == "function" then
    append_send_debug_entry(string.format("%s[feedkeys_submit]", target), enter_termcode)
    local ok, feedkeys_err = pcall(feedkeys, enter_termcode, "nt", false)
    if ok then
      return true
    end
    deps.logger.warn("feedkeys submit failed, falling back to channel send: %s", feedkeys_err)
  end

  append_send_debug_entry(string.format("%s[channel_submit]", target), CODEX_ENTER_SEQUENCE)
  return provider.send(session.handle, CODEX_ENTER_SEQUENCE)
end

---Checks whether a session exists and the provider still reports it alive.
---@param session codex.Session|nil
---@param provider codex.Provider
---@return boolean
session_is_alive = function(session, provider)
  return session ~= nil and session.alive and provider.is_alive(session.handle)
end

---Checks whether a live session is also ready to receive input.
---@param session codex.Session|nil
---@param provider codex.Provider
---@return boolean
local function session_is_ready(session, provider)
  if not session_is_alive(session, provider) then
    return false
  end
  return provider.is_ready(session.handle)
end

---Re-focuses the terminal after sends, reopening/toggling when focus is lost.
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
  if item.pre_focus then
    provider.focus(session.handle)
  end

  local target = item.command_path or "<text>"
  append_send_debug_entry(target, item.text)

  local ok, err = provider.send(session.handle, item.text)
  if not ok then
    return false, err
  end

  if item.on_sent then
    local callback_ok, callback_err = pcall(item.on_sent)
    if not callback_ok then
      return false, callback_err
    end
  end

  if item.post_focus then
    apply_post_send_focus(session, provider)
  end
  return true
end

---Queue processor: ensures session readiness, retries, or drops timed-out/failed sends.
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
---@field on_sent? fun()

---Queues a payload for robust send with startup/retry semantics.
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
    on_sent = opts.on_sent,
    created_at = now_ms(deps),
    opened_in_dispatch = false,
    reopen_attempted = false,
    has_attempted = false,
  }
  return state.send_queue:submit(item)
end

---Opens Codex terminal, optionally focused (defaults to true).
---@param focus? boolean
---@return nil
function M.open(focus)
  ensure_setup()
  if focus == nil then
    focus = true
  end
  open_session(state.config.args, focus)
end

---Closes the active terminal session and resets the send queue.
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

---Toggles terminal visibility for active session or opens a new one.
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

---Focuses active session; opens one if none is running.
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

---Sends plain text to Codex terminal through the resilient send path.
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

---Sends Ctrl-C to clear the current terminal input.
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

  local clear_sequence = encode_termcode("<C-c>")
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
  local payload = command_path .. SLASH_COMMAND_SUBMIT_SEQUENCE
  return dispatch_send(payload, {
    open_focus = true,
    pre_focus = true,
    command_path = command_path,
  })
end

---Requests model selection in Codex CLI.
---@return codex.SendResult ok True when `/model` is sent.
---@return string|nil err
function M.set_model()
  return M.send_command("model")
end

---Requests current session status in Codex CLI.
---@return codex.SendResult ok True when `/status` is sent.
---@return string|nil err
function M.show_status()
  return M.send_command("status")
end

---Requests permission status in Codex CLI.
---@return codex.SendResult ok True when `/permissions` is sent.
---@return string|nil err
function M.show_permissions()
  return M.send_command("permissions")
end

---Requests context compaction in Codex CLI.
---@return codex.SendResult ok True when `/compact` is sent.
---@return string|nil err
function M.compact()
  return M.send_command("compact")
end

---Starts a review command, with optional inline instructions.
---@param instructions? string Optional inline review instructions.
---@return codex.SendResult ok True when `/review` is sent.
---@return string|nil err
function M.review(instructions)
  if instructions == nil or instructions == "" then
    return M.send_command("review")
  end
  return M.send_command("review " .. instructions)
end

---Requests a diff summary in Codex CLI.
---@return codex.SendResult ok True when `/diff` is sent.
---@return string|nil err
function M.show_diff()
  return M.send_command("diff")
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

---Formats visual selection and sends it as bracketed paste.
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

---Sends `/mention` for an already-resolved relative path, auto-submits, and restores prompt input.
---@param resolved_path string Relative path to mention.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
dispatch_mention = function(resolved_path)
  local deps = get_deps()
  local mention = deps.formatter.format_mention(resolved_path)

  local session, provider = get_active_session_and_provider()
  if session_is_alive(session, provider) then
    -- Capture depends on terminal buffer/window state; focus first to ensure buffer visibility.
    provider.focus(session.handle)
  end

  local existing_input = capture_terminal_prompt_input()
  local mention_payload = encode_clear_line_for_mention() .. mention
  return dispatch_send(mention_payload, {
    open_focus = true,
    pre_focus = true,
    command_path = "/mention",
    on_sent = function()
      deps.vim.defer_fn(function()
        local submit_ok, submit_err = submit_with_enter_key("/mention")
        if not submit_ok then
          deps.logger.error("failed to submit /mention: %s", submit_err)
          return
        end

        if not existing_input or existing_input == "" then
          return
        end

        deps.vim.defer_fn(function()
          local restore_ok, restore_err = dispatch_send(existing_input, {
            open_focus = true,
            post_focus = true,
          })
          if not restore_ok then
            deps.logger.error("failed to restore terminal input after /mention: %s", restore_err)
          end
        end, RESTORE_INPUT_DELAY_MS)
      end, SUBMIT_INPUT_DELAY_MS)
    end,
  })
end

---Sends `/mention` for a file, auto-submits it, then restores previously captured prompt input.
---@param path? string Explicit file path to mention. When nil, uses current buffer path.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
function M.mention_file(path)
  ensure_setup()
  local deps = get_deps()
  local resolved_path = path
  if resolved_path == nil then
    resolved_path = deps.vim.fn.expand("%:p")
  end

  if not resolved_path or resolved_path == "" then
    local err = "current buffer has no file path"
    deps.logger.error("failed to mention file: %s", err)
    return false, err
  end

  resolved_path = deps.path.to_relative(deps.vim, resolved_path)
  return dispatch_mention(resolved_path)
end

---Sends `/mention` for a directory, auto-submits it, then restores previously captured prompt input.
---@param path? string Explicit directory path to mention. When nil, uses current buffer's directory.
---@return codex.SendResult ok True when mention payload is sent.
---@return string|nil err
function M.mention_directory(path)
  ensure_setup()
  local deps = get_deps()
  local resolved_path = path
  if resolved_path == nil then
    local buf_path = deps.vim.fn.expand("%:p")
    if not buf_path or buf_path == "" then
      local err = "current buffer has no directory path"
      deps.logger.error("failed to mention directory: %s", err)
      return false, err
    end
    resolved_path = deps.vim.fn.expand("%:p:h")
  end

  if not resolved_path or resolved_path == "" then
    local err = "current buffer has no directory path"
    deps.logger.error("failed to mention directory: %s", err)
    return false, err
  end

  resolved_path = deps.path.to_relative(deps.vim, resolved_path)
  return dispatch_mention(resolved_path)
end

---Returns whether an active Codex session is currently alive.
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

---Returns a deep-copied resolved config for inspection.
---@return table|nil
function M.get_config()
  local deps = get_deps()
  return state.config and deps.vim.deepcopy(state.config) or nil
end

return M
