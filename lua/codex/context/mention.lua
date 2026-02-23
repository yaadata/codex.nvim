local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")

---@class codex.MentionOpts
---@field get_deps fun(): table
---@field get_config fun(): table
---@field dispatch_send fun(text: string, opts?: codex.DispatchSendOpts): codex.SendResult, string|nil

local M = {}

---Creates a mention orchestration instance with the given accessors.
---@param opts codex.MentionOpts
---@return { mention_file: fun(path?: string): codex.SendResult, string|nil, mention_directory: fun(path?: string): codex.SendResult, string|nil, dispatch: fun(resolved_path: string): codex.SendResult, string|nil }
function M.create(opts)
  local get_deps = opts.get_deps
  local get_config = opts.get_config
  local dispatch_send = opts.dispatch_send

  ---Best-effort capture of current terminal prompt input for post-mention restore.
  ---@return string|nil
  local function capture_terminal_prompt_input()
    local deps = get_deps()
    local config = get_config()
    local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
    if
      not session_lifecycle.session_is_alive(session, provider)
      or type(provider.get_bufnr) ~= "function"
    then
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
        terminal_io.add_candidate_line(candidates, seen, cursor_line)
      end
    end

    for offset = 0, terminal_io.PROMPT_CAPTURE_LOOKBACK_LINES do
      terminal_io.add_candidate_line(candidates, seen, line_count - offset)
    end

    for _, line_number in ipairs(candidates) do
      local ok_lines, lines =
        pcall(api.nvim_buf_get_lines, bufnr, line_number - 1, line_number, false)
      if ok_lines and type(lines) == "table" then
        local line = lines[1]
        local parsed = terminal_io.parse_prompt_input(line)
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
    local config = get_config()
    local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
    if not session_lifecycle.session_is_alive(session, provider) then
      return false, "no active Codex session"
    end

    provider.focus(session.handle)
    local enter_termcode = terminal_io.encode_termcode(deps, "<CR>")
    local feedkeys = deps.vim.api.nvim_feedkeys
    if type(feedkeys) == "function" then
      terminal_io.append_send_debug_entry(
        deps,
        string.format("%s[feedkeys_submit]", target),
        enter_termcode
      )
      local ok, feedkeys_err = pcall(feedkeys, enter_termcode, "nt", false)
      if ok then
        return true
      end
      deps.logger.warn("feedkeys submit failed, falling back to channel send: %s", feedkeys_err)
    end

    terminal_io.append_send_debug_entry(
      deps,
      string.format("%s[channel_submit]", target),
      terminal_io.CODEX_ENTER_SEQUENCE
    )
    return provider.send(session.handle, terminal_io.CODEX_ENTER_SEQUENCE)
  end

  ---Sends `/mention` for an already-resolved relative path, auto-submits, and restores prompt input.
  ---@param resolved_path string Relative path to mention.
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function dispatch_mention(resolved_path)
    local deps = get_deps()
    local config = get_config()
    local mention = deps.formatter.format_mention(resolved_path)

    local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
    if session_lifecycle.session_is_alive(session, provider) then
      -- Capture depends on terminal buffer/window state; focus first to ensure buffer visibility.
      provider.focus(session.handle)
    end

    local existing_input = capture_terminal_prompt_input()
    local mention_payload = terminal_io.encode_clear_line_for_mention(deps) .. mention
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
          end, terminal_io.RESTORE_INPUT_DELAY_MS)
        end, terminal_io.SUBMIT_INPUT_DELAY_MS)
      end,
    })
  end

  ---Sends `/mention` for a file, auto-submits it, then restores previously captured prompt input.
  ---@param path? string Explicit file path to mention. When nil, uses current buffer path.
  ---@return codex.SendResult ok True when mention payload is sent.
  ---@return string|nil err
  local function mention_file(path)
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
  local function mention_directory(path)
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

  return {
    mention_file = mention_file,
    mention_directory = mention_directory,
    dispatch = dispatch_mention,
  }
end

return M
