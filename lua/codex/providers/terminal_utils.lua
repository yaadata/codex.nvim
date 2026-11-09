local M = {}

---Maintain a terminal split's percentage of the editor dimensions.
---@param winid integer
---@param bufnr integer
---@param direction "vertical"|"horizontal"
---@param size_pct number
function M.maintain_split_size(winid, bufnr, direction, size_pct)
  local api = vim.api
  local vertical = direction == "vertical"
  local get_size = vertical and api.nvim_win_get_width or api.nvim_win_get_height
  local set_size = vertical and api.nvim_win_set_width or api.nvim_win_set_height
  local group = api.nvim_create_augroup("codex_split_" .. winid, { clear = true })
  local function resize()
    if not api.nvim_win_is_valid(winid) or api.nvim_win_get_buf(winid) ~= bufnr then
      return
    end
    local total = vertical and vim.o.columns or vim.o.lines
    local size = math.max(1, math.floor(total * size_pct / 100))
    if get_size(winid) ~= size then
      set_size(winid, size)
    end
  end
  api.nvim_set_option_value(vertical and "winfixwidth" or "winfixheight", true, { win = winid })
  resize()
  api.nvim_create_autocmd("VimResized", { group = group, callback = resize })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winid),
    once = true,
    callback = function()
      api.nvim_del_augroup_by_id(group)
    end,
  })
end

---Escape a string so it is safe to embed in a Lua pattern.
---@param value string
---@return string
local function escape_lua_pattern(value)
  return (value:gsub("([^%w])", "%%%1"))
end

---Return whether `full_cmd` launches the configured Codex command.
---@param full_cmd string|nil
---@param cmd string|nil
---@return boolean
function M.matches_launch_cmd(full_cmd, cmd)
  if type(full_cmd) ~= "string" or type(cmd) ~= "string" or cmd == "" then
    return false
  end
  return full_cmd == cmd or full_cmd:match("^" .. escape_lua_pattern(cmd) .. "%s") ~= nil
end

---Read a buffer-local variable when available.
---@param bufnr integer
---@param name string
---@return any
function M.get_buffer_var(bufnr, name)
  local api = vim.api
  local ok, value = pcall(api.nvim_buf_get_var, bufnr, name)
  if ok then
    return value
  end
  return nil
end

---Persist plugin metadata on the terminal buffer to improve future recovery.
---@param bufnr integer
---@param provider_name string
---@param full_cmd string
---@param cwd string
---@return nil
function M.set_codex_terminal_marker(bufnr, provider_name, full_cmd, cwd)
  local api = vim.api
  pcall(api.nvim_buf_set_var, bufnr, "codex_terminal", {
    provider = provider_name,
    cmd = full_cmd,
    cwd = cwd,
  })
end

---Extract the terminal command from a Neovim terminal buffer name.
---@param name string|nil
---@return string|nil
function M.extract_terminal_command(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  return name:match("^term://.-//%d+:(.+)$")
end

---Extract the terminal cwd from a Neovim terminal buffer name.
---@param name string|nil
---@return string|nil
function M.extract_terminal_cwd(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  return name:match("^term://(.-)//%d+:")
end

---Find the first window displaying a given buffer.
---@param bufnr integer
---@return integer|nil winid
function M.find_win_for_buf(bufnr)
  local api = vim.api
  for _, winid in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
  return nil
end

return M
