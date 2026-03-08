local prompt_ops = require("codex.context.prompt_ops")
local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")

local M = {}

local SAVED_PROMPT_NOTIFY_MSG = "Saved current prompt to unnamed register"
local COULD_NOT_SAVE_PROMPT_NOTIFY_MSG = "Could not save existing prompt before clearing"

---@class codex.WrapperCommandCreateOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field dispatch_send fun(text: string, opts: codex.DispatchSendOpts): codex.SendResult, string|nil

---Creates a wrapper-command dispatcher.
---@param opts codex.WrapperCommandCreateOpts
---@return { execute_slash_command: fun(command_opts: codex.ExecuteSlashCommandOpts): codex.SendResult, string|nil }
function M.create(opts)
  local get_deps = opts.get_deps
  local get_config = opts.get_config
  local dispatch_send = opts.dispatch_send

  ---@param deps table
  ---@param value string
  ---@return string
  local function trim_string(deps, value)
    if deps.vim and type(deps.vim.trim) == "function" then
      return deps.vim.trim(value)
    end
    return value:match("^%s*(.-)%s*$")
  end

  ---@param command_opts codex.ExecuteSlashCommandOpts
  ---@return string|nil command_name
  ---@return string|nil command_text
  ---@return string|nil err
  local function normalize_command(command_opts)
    if type(command_opts) ~= "table" then
      return nil, nil, "execute_slash_command requires an opts table"
    end

    local deps = get_deps()

    if type(command_opts.command) ~= "string" then
      return nil, nil, "execute_slash_command requires opts.command"
    end

    local command_name = trim_string(deps, command_opts.command:gsub("^/+", ""))
    if command_name == "" then
      return nil, nil, "execute_slash_command requires a non-empty opts.command"
    end

    local args = command_opts.args
    if args == nil then
      return command_name, command_name, nil
    end

    if type(args) ~= "string" then
      return nil, nil, "execute_slash_command expects opts.args to be a string"
    end

    local trimmed_args = trim_string(deps, args)
    if trimmed_args == "" then
      return command_name, command_name, nil
    end

    return command_name, command_name .. " " .. trimmed_args, nil
  end

  ---Captures prompt input and builds wrapper command payload.
  ---@param command_name string
  ---@param command_text string
  ---@return string payload
  ---@return string command_path
  ---@return boolean submit_via_channel
  local function build_wrapper_command_payload(command_name, command_text)
    local deps = get_deps()
    local command_path = "/" .. command_name
    local payload_text = "/" .. command_text

    local existing_input, capture_status, clear_line_count =
      prompt_ops.capture_active_prompt_input(get_deps, get_config)

    if existing_input and existing_input ~= "" then
      local save_ok = pcall(deps.vim.fn.setreg, '"', existing_input)
      if save_ok then
        deps.logger.warn(SAVED_PROMPT_NOTIFY_MSG)
      else
        deps.logger.warn(COULD_NOT_SAVE_PROMPT_NOTIFY_MSG)
      end
    elseif capture_status == "unavailable_buffer" then
      -- Alive session but no confident capture/save path; clearing may drop typed prompt text.
      deps.logger.warn(COULD_NOT_SAVE_PROMPT_NOTIFY_MSG)
    end

    local submit_via_channel = clear_line_count > 1
    local payload = terminal_io.encode_clear_line_for_mention(deps, clear_line_count)
      .. payload_text
    return payload, command_path, submit_via_channel
  end

  ---Dispatches wrapper slash commands with prompt capture/copy/clear before submit.
  ---@param command_opts codex.ExecuteSlashCommandOpts
  ---@return codex.SendResult ok True when command payload is sent.
  ---@return string|nil err
  local function execute_slash_command(command_opts)
    local command_name, command_text, err = normalize_command(command_opts)
    if not command_name then
      return false, err
    end

    local payload, command_path, submit_via_channel =
      build_wrapper_command_payload(command_name, command_text)
    return dispatch_send(payload, {
      open_focus = true,
      pre_focus = true,
      command_path = command_path,
      on_sent = function()
        local submit_ok, submit_err
        if submit_via_channel then
          local deps = get_deps()
          local config = get_config()
          local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
          if not session_lifecycle.session_is_alive(session, provider) then
            submit_ok, submit_err = false, "no active Codex session"
          else
            terminal_io.append_send_debug_entry(
              deps,
              string.format("%s[channel_submit_multiline]", command_path),
              terminal_io.CODEX_ENTER_SEQUENCE
            )
            submit_ok, submit_err = provider.send(session.handle, terminal_io.CODEX_ENTER_SEQUENCE)
          end
        else
          submit_ok, submit_err =
            prompt_ops.submit_with_enter_key(get_deps, get_config, command_path)
        end
        if not submit_ok then
          error(submit_err or ("failed to submit " .. command_path))
        end
      end,
    })
  end

  return {
    execute_slash_command = execute_slash_command,
  }
end

return M
