local config_mod = require("codex.config")
local M = {}

---Build a job command without shell parsing or loss of argv boundaries.
---@param cmd string
---@param args string[]
---@return string[]
function M.command_argv(cmd, args)
  local argv = { cmd }
  for _, arg in ipairs(args) do
    argv[#argv + 1] = arg
  end
  return argv
end

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
    local size = M.pct_size(total, size_pct)
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
---@param profile_identifier? string
---@return nil
function M.set_codex_terminal_marker(bufnr, provider_name, full_cmd, cwd, profile_identifier)
  local api = vim.api
  pcall(api.nvim_buf_set_var, bufnr, "codex_terminal", {
    provider = provider_name,
    cmd = full_cmd,
    cwd = cwd,
    profile_identifier = profile_identifier or "default",
  })
end

local split_types = {
  left = "vsplit",
  right = "vsplit",
  above = "hsplit",
  below = "hsplit",
  top = "hsplit",
  bottom = "hsplit",
  float = "float",
}

function M.window_split_type(winid)
  if not winid then
    return nil
  end
  local api = vim.api
  local win = api.nvim_win_get_config(winid)
  if (win.relative and win.relative ~= "") or win.external then
    return "float"
  end
  local tabnr = api.nvim_tabpage_get_number(api.nvim_win_get_tabpage(winid))
  if vim.fn.winlayout(tabnr)[1] == "leaf" then
    return nil -- A lone normal window has no split even when `win.split` is set.
  end
  return split_types[win.split]
end

---Compute a window size from a percentage of the editor dimension.
---@param total number
---@param pct number
---@return integer
function M.pct_size(total, pct)
  return math.max(1, math.floor(total * pct / 100))
end

---Resolve centered float geometry for the given native provider options.
---@param native_opts table|nil
---@return table config  Ready for `vim.api.nvim_open_win` or `nvim_win_set_config`.
function M.float_geometry(native_opts)
  local float = (native_opts or {}).float or {}
  local width = M.pct_size(vim.o.columns, float.width_pct or 80)
  local height = M.pct_size(vim.o.lines, float.height_pct or 80)
  return {
    relative = "editor",
    anchor = "NW",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  }
end

local function configured_split_type(config, provider_name)
  local opts = config and config.terminal and config.terminal.provider_opts or {}
  if provider_name == "native" then
    return (opts.native or {}).window or "vsplit"
  end
  local win = (opts.snacks or {}).win or {}
  return split_types[win.position]
end

function M.is_live_job(jobid)
  return jobid ~= nil and vim.fn.jobwait({ jobid }, 0)[1] == -1
end

local function normalize_cwd(cwd)
  local expanded = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))
  return vim.uv.fs_realpath(expanded) or expanded
end

---@class codex.RestoreCandidate
---@field cmd? string|string[]
---@field cwd? string
---@field split? 'vsplit'|'hsplit'|'float'

---Return whether a terminal buffer belongs to the selected profile and provider.
---@param marker any
---@param provider_name string
---@param config codex.ProfileConfig|table|nil
---@param candidate codex.RestoreCandidate
---@return boolean
function M.matches_restorable_owner(marker, provider_name, config, candidate)
  local selected = (config and config.profile_identifier) or "default"
  if type(marker) == "table" then
    if marker.provider ~= provider_name then
      return false
    end
    if marker.profile_identifier ~= nil then
      return marker.profile_identifier == selected
    end
  end
  local launch = config and config.launch or {}
  local executable, args = config_mod.split_command(launch.cmd)
  if type(executable) ~= "string" or executable == "" then
    return false
  end
  local wanted_split = configured_split_type(config, provider_name)
  if wanted_split and candidate.split and wanted_split ~= candidate.split then
    return false
  end
  if
    launch.cwd
    and candidate.cwd
    and candidate.cwd ~= ""
    and normalize_cwd(launch.cwd) ~= normalize_cwd(candidate.cwd)
  then
    return false
  end

  local cmd = candidate.cmd
  local structured = type(cmd) == "table"
  if structured then
    local saved_args
    cmd, saved_args = config_mod.split_command(cmd)
    if #args > 0 and not vim.deep_equal(saved_args, args) then
      return false
    end
  end
  if type(cmd) ~= "string" or cmd == "" then
    return false
  end

  local suffix = not structured and #args > 0 and (" " .. table.concat(args, " "))
  local function matches(path)
    if suffix then
      return cmd == path or cmd == path .. suffix -- URI may record only argv[1].
    end
    if structured then
      return cmd == path
    end
    return M.matches_launch_cmd(cmd, path)
  end

  if matches(executable) then
    return true
  end
  local resolved = vim.fn.exepath(executable)
  return resolved ~= "" and matches(resolved)
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

---Find the window displaying the Codex terminal for a profile identifier.
---@param profile_identifier? string
---@param tabpage? integer Restricts the search to one tabpage; nil searches every tabpage.
---@return integer|nil winid
---@return table|nil marker  The `codex_terminal` buffer variable of that window.
function M.find_terminal_win(profile_identifier, tabpage)
  local api = vim.api
  local wanted = profile_identifier or "default"
  local wins = tabpage and api.nvim_tabpage_list_wins(tabpage) or api.nvim_list_wins()
  for _, winid in ipairs(wins) do
    local marker = M.get_buffer_var(api.nvim_win_get_buf(winid), "codex_terminal")
    if type(marker) == "table" and (marker.profile_identifier or "default") == wanted then
      return winid, marker
    end
  end
  return nil
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
