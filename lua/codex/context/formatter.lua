local M = {}

local function longest_backtick_run(text)
  local longest = 0
  for run in text:gmatch("`+") do
    if #run > longest then
      longest = #run
    end
  end
  return longest
end

local function normalize_lines(lines)
  if type(lines) == "string" then
    return lines
  end

  if type(lines) == "table" then
    return table.concat(lines, "\n")
  end

  return ""
end

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

function M.format_mention(filepath)
  return string.format("/mention %s\n", filepath or "")
end

return M
