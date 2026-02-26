local M = {}

M.BRACKETED_PASTE_START = "\27[200~"
M.BRACKETED_PASTE_END = "\27[201~"
M.CODEX_ENTER_SEQUENCE = "\r"
M.SUBMIT_INPUT_DELAY_MS = 40
M.PROMPT_CAPTURE_LOOKBACK_LINES = 8
-- Allow Codex CLI enough time to process submit and render a fresh prompt
-- before re-applying captured prompt input.
M.RESTORE_INPUT_DELAY_MS = 200

---Returns current monotonic time in milliseconds.
---@param deps table
---@return integer
function M.now_ms(deps)
  return deps.vim.uv.now()
end

---Wraps text with bracketed-paste control sequences.
---@param text string
---@return string
function M.encode_bracketed_paste(text)
  return M.BRACKETED_PASTE_START .. text .. M.BRACKETED_PASTE_END
end

---Expands a Vim key notation into terminal keycodes.
---@param deps table
---@param key string
---@return string
function M.encode_termcode(deps, key)
  return deps.vim.api.nvim_replace_termcodes(key, true, false, true)
end

---Builds key sequence that clears the active prompt line before `/mention`.
---@param deps table
---@return string
function M.encode_clear_line_for_mention(deps)
  return table.concat({
    M.encode_termcode(deps, "<C-e>"),
    M.encode_termcode(deps, "<C-u>"),
  })
end

---Normalizes terminal buffer lines by stripping CR-tail artifacts and ANSI CSI codes.
---@param line string
---@return string
function M.normalize_terminal_line(line)
  -- Keep only the visible tail when terminals use carriage-return updates.
  local normalized = line:match("[^\r]*$") or line
  -- Strip common ANSI CSI escapes that can leak into terminal buffer lines.
  normalized = normalized:gsub("\27%[[0-9;?]*[ -/]*[@-~]", "")
  return normalized
end

---Parses a prompt line and extracts typed input and its starting column.
---@param line string
---@return { input: string, input_start_col: integer }|nil
function M.parse_prompt_input(line)
  if type(line) ~= "string" then
    return nil
  end

  local normalized = M.normalize_terminal_line(line)
  local leading_whitespace = #(normalized:match("^%s*") or "")
  local trimmed = normalized:gsub("^%s+", "")
  if trimmed == "" then
    return nil
  end

  local first_char = trimmed:sub(1, 1)
  if first_char == "" or first_char:find("[%w/]") then
    return nil
  end

  -- Support compact prompt forms like `>draft` where no delimiter space exists.
  if not trimmed:find("%s") then
    local compact_input = trimmed:sub(2)
    if compact_input ~= "" then
      return {
        input = compact_input,
        input_start_col = leading_whitespace + 1,
      }
    end
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

---Reports whether a terminal line has visible non-whitespace text.
---@param line string
---@return boolean
function M.has_visible_text(line)
  if type(line) ~= "string" then
    return false
  end
  local normalized = M.normalize_terminal_line(line)
  return normalized:match("%S") ~= nil
end

---Best-effort signal that line may contain prompt input but could not be parsed.
---@param line string
---@return boolean
function M.has_unparsed_prompt_like_input(line)
  if type(line) ~= "string" then
    return false
  end
  local normalized = M.normalize_terminal_line(line)
  local trimmed = normalized:gsub("^%s+", "")
  if trimmed == "" then
    return false
  end
  if M.parse_prompt_input(trimmed) ~= nil then
    return false
  end
  local first_char = trimmed:sub(1, 1)
  if first_char == "" or first_char:find("[%w/]") then
    return false
  end
  -- Treat symbol-only prompt markers (e.g. "> " or ">> ") as empty input.
  if trimmed:match("^[^%w/%s]+%s*$") then
    return false
  end
  return trimmed:sub(2):match("%S") ~= nil
end

---Adds a line number candidate once, if valid.
---@param values integer[]
---@param seen table<integer, boolean>
---@param line integer|nil
---@return nil
function M.add_candidate_line(values, seen, line)
  if type(line) ~= "number" or line < 1 or seen[line] then
    return
  end
  table.insert(values, line)
  seen[line] = true
end

---Emits payload debug logging for outbound terminal sends.
---@param deps table
---@param target string
---@param text string
---@return nil
function M.append_send_debug_entry(deps, target, text)
  deps.logger.debug("send payload target=%s len=%d", target, #text)
end

return M
