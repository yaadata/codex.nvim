local M = {}

---@class codex.SelectionSpec
---@field filepath string
---@field start_line integer
---@field end_line integer
---@field filetype string
---@field lines string[]|string

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

---@param path string
---@return boolean
local function needs_quoting(path)
  return path:find("[%s\"'`$;&|<>!()%[%]{}*?\\]") ~= nil
end

---@param path string
---@return string
local function quote_path(path)
  local escaped = path:gsub("\\", "\\\\"):gsub('"', '\\"')
  return '"' .. escaped .. '"'
end

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

  return string.format(
    "# Selection from %s (lines %d-%d)\n\n%s%s\n%s\n%s\n",
    filepath,
    start_line,
    end_line,
    fence,
    language,
    content,
    fence
  )
end

---@param filepath? string
---Formats a `/mention` payload. Paths are quoted and escaped when needed.
---@return string payload
function M.format_mention(filepath)
  local path = filepath or ""
  if path ~= "" and needs_quoting(path) then
    path = quote_path(path)
  end
  return string.format("/mention %s\n", path)
end

return M
