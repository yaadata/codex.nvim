local terminal_io = require("codex.runtime.terminal_io")
local session_lifecycle = require("codex.state.session_lifecycle")

local M = {}

local SAFE_CONTINUATION_MARKERS = {
  ["."] = true,
}

---Strip visual continuation padding that terminals often add to multiline prompt lines.
---@param line string
---@param input_start_col integer
---@param prompt_marker string
---@return string
local function trim_continuation_prompt_padding(line, input_start_col, prompt_marker)
  local padding = math.max(0, tonumber(input_start_col) or 0)
  local trimmed = line
  if padding > 0 then
    local leading_spaces = #(trimmed:match("^ *") or "")
    local trim_count = math.min(leading_spaces, padding)
    trimmed = trimmed:sub(trim_count + 1)
  end

  local marker, _, rest = trimmed:match("^([^%s]+)(%s+)(.*)$")
  if marker ~= nil then
    if marker == prompt_marker or SAFE_CONTINUATION_MARKERS[marker] then
      return rest
    end
  end

  return trimmed
end

---Best-effort capture of current terminal prompt input.
---@param get_deps fun(): table
---@param get_config fun(): table
---@return string|nil input
---@return "captured"|"no_input"|"uncertain"|"unavailable_session"|"unavailable_buffer" status
---@return integer clear_line_count
function M.capture_prompt_input(get_deps, get_config)
  local deps = get_deps()
  local config = get_config()
  local function vdebug(msg, ...)
    if type(deps.logger.vdebug) == "function" then
      deps.logger.vdebug(msg, ...)
    end
  end
  local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
  if not session_lifecycle.session_is_alive(session, provider) then
    vdebug("capture_prompt_input unavailable session")
    return nil, "unavailable_session", 1
  end
  if type(provider.get_bufnr) ~= "function" then
    vdebug("capture_prompt_input provider missing get_bufnr")
    return nil, "unavailable_buffer", 1
  end

  local bufnr = provider.get_bufnr(session.handle)
  local api = deps.vim.api
  if type(bufnr) ~= "number" then
    vdebug("capture_prompt_input unavailable buffer (bufnr missing)")
    return nil, "unavailable_buffer", 1
  end
  local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
  if not ok_valid or not is_valid then
    vdebug("capture_prompt_input unavailable buffer (invalid bufnr=%s)", tostring(bufnr))
    return nil, "unavailable_buffer", 1
  end

  local ok_count, line_count = pcall(api.nvim_buf_line_count, bufnr)
  if not ok_count or type(line_count) ~= "number" or line_count < 1 then
    vdebug("capture_prompt_input unavailable buffer (line_count invalid)")
    return nil, "unavailable_buffer", 1
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
          break
        elseif parsed.input ~= "" then
          if uncertain then
            break
          end
          local captured_input = parsed.input
          local clear_line_count = 1
          if
            type(cursor_line) == "number"
            and cursor_line > line_number
            and type(cursor_col) == "number"
          then
            local continuation_lines = {}
            local continuation_ok = true
            local continuation_end_line = cursor_line
            if cursor_col == 0 then
              -- Cursor can sit at column 0 on the next physical line while input
              -- still belongs to preceding continuation lines.
              continuation_end_line = cursor_line - 1
            end

            for continuation_line = line_number + 1, continuation_end_line do
              local ok_continuation, continuation = pcall(
                api.nvim_buf_get_lines,
                bufnr,
                continuation_line - 1,
                continuation_line,
                false
              )
              if not ok_continuation or type(continuation) ~= "table" then
                continuation_ok = false
                break
              end
              local continuation_text = terminal_io.normalize_terminal_line(continuation[1] or "")
              -- A new parsed prompt head below the captured line marks the next prompt
              -- boundary; do not treat it as continuation content.
              if terminal_io.parse_prompt_input(continuation_text) ~= nil then
                break
              end
              table.insert(
                continuation_lines,
                trim_continuation_prompt_padding(
                  continuation_text,
                  parsed.input_start_col,
                  parsed.prompt_marker
                )
              )
            end
            if continuation_ok then
              if #continuation_lines > 0 then
                captured_input = captured_input .. "\n" .. table.concat(continuation_lines, "\n")
                clear_line_count = #continuation_lines + 1
              end
            else
              uncertain = true
              break
            end
          end
          vdebug("capture_prompt_input captured len=%d line=%d", #captured_input, line_number)
          return captured_input, "captured", clear_line_count
        end
      elseif
        (line_number == cursor_line or line_number == line_count)
        and terminal_io.has_unparsed_prompt_like_input(line)
      then
        uncertain = true
        break
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
          break
        end
      end
    end
  end

  if uncertain then
    vdebug("capture_prompt_input uncertain")
    return nil, "uncertain", 1
  end
  vdebug("capture_prompt_input no_input")
  return nil, "no_input", 1
end

---Focuses the active session when available, then captures prompt input.
---@param get_deps fun(): table
---@param get_config fun(): table
---@return string|nil input
---@return "captured"|"no_input"|"uncertain"|"unavailable_session"|"unavailable_buffer" status
---@return integer clear_line_count
function M.capture_active_prompt_input(get_deps, get_config)
  local deps = get_deps()
  local config = get_config()
  local function vdebug(msg, ...)
    if type(deps.logger.vdebug) == "function" then
      deps.logger.vdebug(msg, ...)
    end
  end
  local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
  if session_lifecycle.session_is_alive(session, provider) then
    -- Capture depends on terminal buffer/window state; focus first to ensure buffer visibility.
    vdebug("capture_active_prompt_input focusing active session before prompt capture")
    session_lifecycle.remember_previous_focus(deps, config, session, provider)
    provider.focus(session.handle)
  end

  return M.capture_prompt_input(get_deps, get_config)
end

---Captures current prompt input and copies it to the unnamed register.
---@param get_deps fun(): table
---@param get_config fun(): table
---@return boolean ok
---@return string|nil err
function M.copy_prompt_input(get_deps, get_config)
  local deps = get_deps()
  local function vdebug(msg, ...)
    if type(deps.logger.vdebug) == "function" then
      deps.logger.vdebug(msg, ...)
    end
  end
  local existing_input, capture_status = M.capture_active_prompt_input(get_deps, get_config)
  if existing_input and existing_input ~= "" then
    local save_ok = pcall(deps.vim.fn.setreg, '"', existing_input)
    if not save_ok then
      vdebug("copy_prompt_input setreg failed")
      return false, "failed to copy prompt input"
    end
    vdebug("copy_prompt_input copied len=%d", #existing_input)
    return true
  end

  if capture_status == "no_input" then
    vdebug("copy_prompt_input no input")
    return false, "no prompt input to copy"
  end

  if capture_status == "unavailable_session" then
    vdebug("copy_prompt_input no active session")
    return false, "no active Codex session"
  end

  vdebug("copy_prompt_input capture unavailable status=%s", capture_status or "unknown")
  return false, "could not capture prompt input"
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
  local function vdebug(msg, ...)
    if type(deps.logger.vdebug) == "function" then
      deps.logger.vdebug(msg, ...)
    end
  end
  local session, provider = session_lifecycle.get_active_session_and_provider(deps, config)
  if not session_lifecycle.session_is_alive(session, provider) then
    vdebug("submit_with_enter_key no active session target=%s", target)
    return false, "no active Codex session"
  end

  session_lifecycle.remember_previous_focus(deps, config, session, provider)
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
      vdebug("submit_with_enter_key feedkeys success target=%s", target)
      return true
    end
    vdebug("submit_with_enter_key feedkeys failed target=%s err=%s", target, feedkeys_err)
    deps.logger.warn("feedkeys submit failed, falling back to channel send: %s", feedkeys_err)
  end

  terminal_io.append_send_debug_entry(
    deps,
    string.format("%s[channel_submit]", target),
    terminal_io.CODEX_ENTER_SEQUENCE
  )
  local ok, err = provider.send(session.handle, terminal_io.CODEX_ENTER_SEQUENCE)
  if ok then
    vdebug("submit_with_enter_key channel send success target=%s", target)
  else
    vdebug("submit_with_enter_key channel send failed target=%s err=%s", target, err or "unknown")
  end
  return ok, err
end

return M
