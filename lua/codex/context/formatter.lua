local M = {}

---@class codex.SelectionSpec
---@field filepath string
---@field start_line integer
---@field end_line integer
---@field filetype string
---@field lines string[]|string

--- Return the length of the longest consecutive backtick run in a string.
---@param text string
---@return integer
local function longest_backtick_run(text)
  local longest = 0
  for run in text:gmatch("`+") do
    if #run > longest then
      longest = #run
    end
  end
  return longest
end

--- Convert a string, table of lines, or nil into a single string.
---@param lines string[]|string|nil
---@return string
local function normalize_lines(lines)
  if type(lines) == "string" then
    return lines
  end

  if type(lines) == "table" then
    return table.concat(lines, "\n")
  end

  return ""
end

--- Check whether a file path contains shell-significant characters.
---@param path string
---@return boolean
local function needs_quoting(path)
  return path:find("[%s\"'`$;&|<>!()%[%]{}*?\\]") ~= nil
end

--- Wrap a path in double quotes, escaping backslashes and double-quote characters.
---@param path string
---@return string
local function quote_path(path)
  local escaped = path:gsub("\\", "\\\\"):gsub('"', '\\"')
  return '"' .. escaped .. '"'
end

--- Format a code selection as a fenced Markdown block with file metadata.
---@param spec? codex.SelectionSpec
---@return string payload
function M.format_selection(spec)
  spec = spec or {}

  local filepath = spec.filepath or ""
  local start_line = spec.start_line or 0
  local end_line = spec.end_line or 0
  local filetype = spec.filetype or ""
  local content = normalize_lines(spec.lines)

  local fence_size = math.max(3, longest_backtick_run(content) + 1)
  local fence = string.rep("`", fence_size)
  local language = filetype ~= "" and filetype or "text"
  local location
  if start_line == end_line then
    location = string.format("@%s#L%d", filepath, start_line)
  else
    location = string.format("@%s#L%d-%d", filepath, start_line, end_line)
  end

  return string.format("%s\n\n%s%s\n%s\n%s\n", location, fence, language, content, fence)
end

--- Format an ACP file reference for the current buffer.
---@param filepath string
---@return string payload
function M.format_buffer_ref(filepath)
  return string.format("@%s ", filepath)
end

--- Format a `/mention` payload; paths are quoted and escaped when needed.
---@param filepath? string
---@return string payload
function M.format_mention(filepath)
  local path = filepath or ""
  if path ~= "" and needs_quoting(path) then
    path = quote_path(path)
  end
  return string.format("/mention %s", path)
end

return M
