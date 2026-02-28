local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")
local prompt_submit = require("codex.context.prompt_submit")

---@class codex.MentionOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field dispatch_send fun(text: string, opts?: codex.DispatchSendOpts): codex.SendResult, string|nil

local M = {}
local MENTION_COMMAND_PATH = "/mention"

---Creates a mention orchestration instance with the given accessors.
---@param opts codex.MentionOpts
---@return { mention_file: fun(path?: string, opts?: codex.MentionCommandOpts): codex.SendResult, string|nil, mention_directory: fun(path?: string, opts?: codex.MentionCommandOpts): codex.SendResult, string|nil, dispatch: fun(resolved_path: string, opts?: codex.MentionCommandOpts): codex.SendResult, string|nil }
function M.create(opts)
  local get_deps = opts.get_deps
  local get_config = opts.get_config
  local dispatch_send = opts.dispatch_send

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

  ---Resolve optional post-execution callback from mention options.
  ---@param mention_opts? codex.MentionCommandOpts
  ---@return fun(ok: boolean, err: string|nil)|nil
  local function get_post_execute(mention_opts)
    if type(mention_opts) ~= "table" then
      return nil
    end
    local post_execute = mention_opts.post_execute
    if type(post_execute) == "function" then
      return post_execute
    end
    return nil
  end

  ---Run post-execution callback and swallow callback failures.
  ---@param post_execute fun(ok: boolean, err: string|nil)|nil
  ---@param ok boolean
  ---@param err string|nil
  ---@return nil
  local function run_post_execute(post_execute, ok, err)
    if type(post_execute) ~= "function" then
      return
    end
    local deps = get_deps()
    local callback_ok, callback_err = pcall(post_execute, ok, err)
    if callback_ok then
      return
    end
    deps.logger.error(
      "failed to run %s post_execute callback: %s",
      MENTION_COMMAND_PATH,
      callback_err or "unknown error"
    )
  end

  ---Sends `/mention` for an already-resolved relative path, auto-submits, and restores prompt input.
  ---@param resolved_path string Relative path to mention.
  ---@param mention_opts? codex.MentionCommandOpts
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function dispatch_mention(resolved_path, mention_opts)
    local post_execute = get_post_execute(mention_opts)
    local has_post_execute = post_execute ~= nil
    local finalized = false

    ---Call post_execute once with final outcome.
    ---@param ok boolean
    ---@param err string|nil
    ---@return nil
    local function finalize(ok, err)
      if finalized then
        return
      end
      finalized = true
      run_post_execute(post_execute, ok, err)
    end

    local deps = get_deps()
    local config = get_config()
    local mention = deps.formatter.format_mention(resolved_path)
    vdebug("dispatch_mention path=%s", resolved_path)

    local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
    if session_lifecycle.session_is_alive(session, provider) then
      -- Capture depends on terminal buffer/window state; focus first to ensure buffer visibility.
      vdebug("dispatch_mention focusing active session before prompt capture")
      provider.focus(session.handle)
    end

    local existing_input, _, clear_line_count =
      prompt_submit.capture_prompt_input(get_deps, get_config)
    if existing_input and existing_input ~= "" then
      vdebug("dispatch_mention captured existing prompt input len=%d", #existing_input)
    else
      vdebug("dispatch_mention no existing prompt input captured")
    end
    local mention_payload = terminal_io.encode_clear_line_for_mention(deps, clear_line_count)
      .. mention
    local ok, err = dispatch_send(mention_payload, {
      open_focus = true,
      pre_focus = true,
      command_path = MENTION_COMMAND_PATH,
      on_sent = function()
        deps.vim.defer_fn(function()
          local submit_ok, submit_err
          if existing_input and existing_input:find("\n", 1, true) then
            local submit_session, submit_provider =
              session_lifecycle.get_active_session_and_provider(deps, config)
            if not session_lifecycle.session_is_alive(submit_session, submit_provider) then
              submit_ok, submit_err = false, "no active Codex session"
            else
              terminal_io.append_send_debug_entry(
                deps,
                "/mention[channel_submit_multiline]",
                terminal_io.CODEX_ENTER_SEQUENCE
              )
              submit_ok, submit_err =
                submit_provider.send(submit_session.handle, terminal_io.CODEX_ENTER_SEQUENCE)
            end
          elseif has_post_execute then
            local submit_session, submit_provider =
              session_lifecycle.get_active_session_and_provider(deps, config)
            if not session_lifecycle.session_is_alive(submit_session, submit_provider) then
              submit_ok, submit_err = false, "no active Codex session"
            else
              terminal_io.append_send_debug_entry(
                deps,
                "/mention[channel_submit_post_execute]",
                terminal_io.CODEX_ENTER_SEQUENCE
              )
              submit_ok, submit_err =
                submit_provider.send(submit_session.handle, terminal_io.CODEX_ENTER_SEQUENCE)
            end
          else
            submit_ok, submit_err =
              prompt_submit.submit_with_enter_key(get_deps, get_config, MENTION_COMMAND_PATH)
          end
          if not submit_ok then
            vdebug("dispatch_mention submit failed err=%s", submit_err or "unknown")
            deps.logger.error("failed to submit %s: %s", MENTION_COMMAND_PATH, submit_err)
            finalize(false, submit_err)
            return
          end
          vdebug("dispatch_mention submit succeeded")

          if not existing_input or existing_input == "" then
            finalize(true, nil)
            return
          end

          deps.vim.defer_fn(function()
            vdebug("dispatch_mention restoring previous prompt input len=%d", #existing_input)
            local restore_payload = existing_input
            if existing_input:find("\n", 1, true) then
              restore_payload = terminal_io.encode_bracketed_paste(existing_input)
            end
            local restore_ok, restore_err = dispatch_send(restore_payload, {
              open_focus = true,
              post_focus = true,
            })
            if not restore_ok then
              vdebug("dispatch_mention restore failed err=%s", restore_err or "unknown")
              deps.logger.error(
                "failed to restore terminal input after %s: %s",
                MENTION_COMMAND_PATH,
                restore_err
              )
              finalize(false, restore_err)
              return
            end
            vdebug("dispatch_mention restore succeeded")
            finalize(true, nil)
          end, terminal_io.RESTORE_INPUT_DELAY_MS)
        end, terminal_io.SUBMIT_INPUT_DELAY_MS)
      end,
    })
    if not ok then
      finalize(false, err)
      return false, err
    end
    return true
  end

  ---Sends `/mention` for a file, auto-submits it, then restores previously captured prompt input.
  ---@param path? string Explicit file path to mention. When nil, uses current buffer path.
  ---@param mention_opts? codex.MentionCommandOpts
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function mention_file(path, mention_opts)
    local post_execute = get_post_execute(mention_opts)
    local deps = get_deps()
    local resolved_path = path
    if resolved_path == nil then
      resolved_path = deps.vim.fn.expand("%:p")
    end

    if not resolved_path or resolved_path == "" then
      local err = "current buffer has no file path"
      deps.logger.error("failed to mention file: %s", err)
      run_post_execute(post_execute, false, err)
      return false, err
    end

    resolved_path = deps.path.to_relative(deps.vim, resolved_path)
    vdebug("mention_file resolved_path=%s", resolved_path)
    return dispatch_mention(resolved_path, mention_opts)
  end

  ---Sends `/mention` for a directory, auto-submits it, then restores previously captured prompt input.
  ---@param path? string Explicit directory path to mention. When nil, uses current buffer's directory.
  ---@param mention_opts? codex.MentionCommandOpts
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function mention_directory(path, mention_opts)
    local post_execute = get_post_execute(mention_opts)
    local deps = get_deps()
    local resolved_path = path
    if resolved_path == nil then
      local buf_path = deps.vim.fn.expand("%:p")
      if not buf_path or buf_path == "" then
        local err = "current buffer has no directory path"
        deps.logger.error("failed to mention directory: %s", err)
        run_post_execute(post_execute, false, err)
        return false, err
      end
      resolved_path = deps.vim.fn.expand("%:p:h")
    end

    if not resolved_path or resolved_path == "" then
      local err = "current buffer has no directory path"
      deps.logger.error("failed to mention directory: %s", err)
      run_post_execute(post_execute, false, err)
      return false, err
    end

    resolved_path = deps.path.to_relative(deps.vim, resolved_path)
    resolved_path = deps.path.ensure_dir_trailing_separator(deps.vim, resolved_path)
    vdebug("mention_directory resolved_path=%s", resolved_path)
    return dispatch_mention(resolved_path, mention_opts)
  end

  return {
    mention_file = mention_file,
    mention_directory = mention_directory,
    dispatch = dispatch_mention,
  }
end

return M
