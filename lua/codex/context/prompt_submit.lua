local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")

local M = {}

---Best-effort capture of current terminal prompt input.
---@param get_deps fun(): table
---@param get_config fun(): table
---@return string|nil input
---@return "captured"|"no_input"|"uncertain"|"unavailable_session"|"unavailable_buffer" status
function M.capture_prompt_input(get_deps, get_config)
  local deps = get_deps()
  local config = get_config()
  local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
  if not session_lifecycle.session_is_alive(session, provider) then
    return nil, "unavailable_session"
  end
  if type(provider.get_bufnr) ~= "function" then
    return nil, "unavailable_buffer"
  end

  local bufnr = provider.get_bufnr(session.handle)
  local api = deps.vim.api
  if type(bufnr) ~= "number" then
    return nil, "unavailable_buffer"
  end
  local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
  if not ok_valid or not is_valid then
    return nil, "unavailable_buffer"
  end

  local ok_count, line_count = pcall(api.nvim_buf_line_count, bufnr)
  if not ok_count or type(line_count) ~= "number" or line_count < 1 then
    return nil, "unavailable_buffer"
  end

  local candidates = {}
  local seen = {}
  local cursor_line = nil
  local cursor_col = nil
  local uncertain = false

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
          -- Cursor is parked at input start; this may be ghost text, but could also be
          -- real input in some terminal states.
          uncertain = true
        elseif parsed.input ~= "" then
          return parsed.input, "captured"
        end
      elseif
        (line_number == cursor_line or line_number == line_count)
        and terminal_io.has_unparsed_prompt_like_input(line)
      then
        uncertain = true
      elseif
        line_number == cursor_line
        and type(cursor_col) == "number"
        and terminal_io.has_visible_text(line)
      then
        local normalized = terminal_io.normalize_terminal_line(line):gsub("^%s+", "")
        local tail_has_visible = normalized:sub(2):match("%S") ~= nil
        local marker_only = normalized:match("^[^%w/%s]+%s*$") ~= nil
        if
          normalized ~= ""
          and normalized:sub(1, 1):find("[%w/]") == nil
          and tail_has_visible
          and not marker_only
        then
          uncertain = true
        end
      end
    end
  end

  if uncertain then
    return nil, "uncertain"
  end
  return nil, "no_input"
end

---Submits the current prompt using Enter, with provider-send fallback.
---@param get_deps fun(): table
---@param get_config fun(): table
---@param target string
---@return boolean ok
---@return string|nil err
function M.submit_with_enter_key(get_deps, get_config, target)
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

return M
