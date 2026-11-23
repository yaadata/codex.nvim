local M = {}

---Best-effort host OS check for Windows to pick default path separators.
---@param vim_api table|nil
---@return boolean
local function is_windows(vim_api)
  vim_api = vim_api or vim

  local uv = vim_api.uv or vim_api.loop
  if uv and type(uv.os_uname) == "function" then
    local ok, uname = pcall(uv.os_uname)
    if ok and type(uname) == "table" and type(uname.sysname) == "string" then
      return uname.sysname:match("Windows") ~= nil
    end
  end

  local fn = vim_api.fn
  if type(fn) == "table" and type(fn.has) == "function" then
    local ok_win32, has_win32 = pcall(fn.has, "win32")
    if ok_win32 and has_win32 == 1 then
      return true
    end
    local ok_win64, has_win64 = pcall(fn.has, "win64")
    if ok_win64 and has_win64 == 1 then
      return true
    end
  end

  return false
end

---Choose separator by path style first, then host OS as fallback.
---@param vim_api table|nil
---@param path string
---@return string
local function choose_separator(vim_api, path)
  if path:find("\\", 1, true) ~= nil then
    return "\\"
  end

  if path:match("^%a:[/\\]?") or path:match("^\\\\") then
    return "\\"
  end

  if path:find("/", 1, true) ~= nil then
    return "/"
  end

  if is_windows(vim_api) then
    return "\\"
  end

  return "/"
end

--- Convert an absolute file path to a cwd-relative path via fnamemodify.
---@param vim_api table|nil
---@param filepath string
---@return string
function M.to_relative(vim_api, filepath)
  vim_api = vim_api or vim
  if filepath == "" then
    return filepath
  end

  local ok, relative_path = pcall(vim_api.fn.fnamemodify, filepath, ":.")
  if ok and type(relative_path) == "string" and relative_path ~= "" then
    return relative_path
  end

  return filepath
end

---Ensure directory paths end with one separator matching path style/OS.
---@param vim_api table|nil
---@param path string
---@return string
function M.ensure_dir_trailing_separator(vim_api, path)
  if path == "" then
    return path
  end

  local separator = choose_separator(vim_api, path)
  if path:sub(-1) == separator then
    return path
  end

  local normalized = path:gsub("[/\\]+$", "")
  if normalized == "" then
    return separator
  end

  return normalized .. separator
end

return M
