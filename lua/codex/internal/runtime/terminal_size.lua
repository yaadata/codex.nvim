local terminal_utils = require("codex.internal.providers.terminal_utils")

local M = {}

---Calls a window setter, reporting failures without interrupting the caller.
---@param deps table
---@param setter fun(...)
---@param ...
---@return nil
local function attempt(deps, setter, ...)
  local ok, err = pcall(setter, ...)
  if not ok then
    deps.logger.debug("resize failed: %s", err)
  end
end

---Locate the window displaying the profile's agent terminal.
---Searches every tabpage, so a terminal shown in a background tab is found.
---@param profile codex.ProfileConfig
---@return integer|nil winid
---@return table|nil marker
local function locate(profile)
  return terminal_utils.find_terminal_win(profile.profile_identifier)
end

---Return whether the profile's agent terminal is displayed on the current tabpage.
---Reports window presence only; a displayed terminal whose process already
---exited is still visible. Use `codex.session.is_running` for liveness.
---@param profile codex.ProfileConfig
---@return boolean
function M.is_visible(profile)
  return terminal_utils.find_terminal_win(profile.profile_identifier, 0) ~= nil
end

---Restore a visible agent terminal to the size configured for its profile.
---Splits use `native.vsplit`/`native.hsplit` `size_pct`; floats are only
---restored for the `native` provider, which re-centers on `native.float`.
---@param deps table
---@param profile codex.ProfileConfig
---@return nil
function M.resize(deps, profile)
  local winid, marker = locate(profile)
  if not winid then
    return
  end

  local api = deps.vim.api
  local native = ((profile.terminal or {}).provider_opts or {}).native or {}
  local kind = terminal_utils.window_split_type(winid)

  if kind == "vsplit" then
    local pct = (native.vsplit or {}).size_pct or 40
    attempt(deps, api.nvim_win_set_width, winid, terminal_utils.pct_size(vim.o.columns, pct))
  elseif kind == "hsplit" then
    local pct = (native.hsplit or {}).size_pct or 30
    attempt(deps, api.nvim_win_set_height, winid, terminal_utils.pct_size(vim.o.lines, pct))
  elseif kind == "float" and marker.provider == "native" then
    -- Other providers own their float geometry (for example snacks.win opts).
    local current = api.nvim_win_get_config(winid)
    if current.external then
      return
    end
    local config = terminal_utils.float_geometry(native)
    config.border = current.border
    config.title = current.title
    config.title_pos = current.title_pos
    attempt(deps, api.nvim_win_set_config, winid, config)
  end
end

return M
