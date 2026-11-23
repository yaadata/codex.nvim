local config_mod = require("codex.config")
local keymaps_mod = require("codex.nvim.keymaps")

local Profile = {}
Profile.__index = Profile

---@param name string
---@param base_config codex.ProfileConfig
---@param global_keymaps codex.GlobalKeymapConfig|nil
---@return codex.Profile
function Profile.new(name, base_config, global_keymaps)
  return setmetatable({
    name = name,
    base_config = base_config,
    keymaps = global_keymaps or {},
    _keymap_handle = nil,
  }, Profile)
end

---@param launch_overrides? codex.ProfileLaunch
---@return codex.ProfileConfig|nil config
---@return string|nil err
function Profile:resolve(launch_overrides)
  if launch_overrides == nil then
    return vim.deepcopy(self.base_config), nil
  end

  local ok_override, override_err =
    pcall(config_mod.validate_launch_override, launch_overrides, "launch_overrides")
  if not ok_override then
    return nil, tostring(override_err)
  end

  local candidate = vim.deepcopy(self.base_config)
  candidate.launch = config_mod.merge_launch(self.base_config.launch, launch_overrides)

  return candidate, nil
end

---@return boolean ok
---@return string|nil err
function Profile:start_keymaps()
  if self._keymap_handle then
    return true, nil
  end

  local handle, err = keymaps_mod.apply_global(self.keymaps)
  if not handle then
    return false, err
  end

  self._keymap_handle = handle
  return true, nil
end

---@return (fun())|nil rollback
function Profile:stop_keymaps()
  local handle = self._keymap_handle
  if not handle then
    return nil
  end
  local restore = handle:stop()
  self._keymap_handle = nil
  return function()
    if restore then
      restore()
    end
    self._keymap_handle = handle
  end
end

return Profile
