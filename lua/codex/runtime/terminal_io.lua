local M = {}

M.BRACKETED_PASTE_START = "\27[200~"
M.BRACKETED_PASTE_END = "\27[201~"
M.CODEX_ENTER_SEQUENCE = "\r"
M.SUBMIT_INPUT_DELAY_MS = 40
M.PROMPT_CAPTURE_LOOKBACK_LINES = 900
-- Allow Codex CLI enough time to process submit and render a fresh prompt
-- before re-applying captured prompt input.
M.RESTORE_INPUT_DELAY_MS = 200

local COMPACT_PROMPT_MARKERS = {
  [">"] = true,
  ["›"] = true,
  ["❯"] = true,
  ["»"] = true,
}

local DISALLOWED_SPACED_PROMPT_MARKERS = {
  ["."] = true,
  ["-"] = true,
  ["*"] = true,
  ["+"] = true,
}

---Checks whether a token can represent a supported prompt marker.
---@param token string
---@return boolean
function M.is_supported_prompt_marker(token)
  if type(token) ~= "string" or token == "" then
    return false
  end
  if COMPACT_PROMPT_MARKERS[token] then
    return true
  end
  -- Some shells repeat `>` for nested prompt contexts.
  return token:match("^>+$") ~= nil
end

---Checks whether a token can represent a spaced prompt marker (`<marker><space><input>`).
---@param token string
---@return boolean
function M.is_supported_spaced_prompt_marker(token)
  if M.is_supported_prompt_marker(token) then
    return true
  end
  if type(token) ~= "string" or token == "" then
    return false
  end
  if DISALLOWED_SPACED_PROMPT_MARKERS[token] then
    return false
  end
  if #token > 6 then
    return false
  end
  if token:find("[%w/]") then
    return false
  end
  if token:find("[`%.]") then
    return false
  end
  return token:match("^[^%s]+$") ~= nil
end

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
---@param clear_line_count? integer
---@return string
function M.encode_clear_line_for_mention(deps, clear_line_count)
  local line_count = tonumber(clear_line_count) or 1
  if line_count < 1 then
    line_count = 1
  end

  local keys = {
    M.encode_termcode(deps, "<C-e>"),
    M.encode_termcode(deps, "<C-u>"),
  }

  -- For multiline prompt input, delete the newline join and clear each previous line.
  for _ = 2, line_count do
    table.insert(keys, M.encode_termcode(deps, "<C-h>"))
    table.insert(keys, M.encode_termcode(deps, "<C-u>"))
  end

  return table.concat(keys)
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
---@return { input: string, input_start_col: integer, prompt_marker: string }|nil
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
    local compact_marker = trimmed:sub(1, 1)
    if not M.is_supported_prompt_marker(compact_marker) then
      return nil
    end

    local compact_input = trimmed:sub(2)
    if compact_input ~= "" then
      return {
        input = compact_input,
        input_start_col = leading_whitespace + 1,
        prompt_marker = compact_marker,
      }
    end
    return nil
  end

  local prompt_end = trimmed:find("%s")
  if prompt_end == nil or prompt_end <= 1 then
    return nil
  end

  local prompt_token = trimmed:sub(1, prompt_end - 1)
  if prompt_token:find("[%w/]") or not M.is_supported_spaced_prompt_marker(prompt_token) then
    return nil
  end

  local input = trimmed:sub(prompt_end + 1)
  if input == "" then
    return nil
  end

  return {
    input = input,
    input_start_col = leading_whitespace + prompt_end,
    prompt_marker = prompt_token,
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
  local prompt_token = trimmed:match("^(%S+)%s")
  if prompt_token ~= nil and not M.is_supported_spaced_prompt_marker(prompt_token) then
    return false
  end
  if prompt_token == nil and not M.is_supported_prompt_marker(first_char) then
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
  if type(deps.logger.vdebug) == "function" then
    deps.logger.vdebug("send payload target=%s len=%d", target, #text)
    return
  end
  deps.logger.debug("send payload target=%s len=%d", target, #text)
end

return M
