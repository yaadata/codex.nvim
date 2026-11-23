local launch_config = require("codex.config.launch")
local validation = require("codex.config.validation")
local M = {}

---@param base codex.TerminalConfig
---@param override? table
---@return codex.TerminalConfig
local function merge_terminal(base, override)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(base), vim.deepcopy(override or {}))
  if override and override.keymaps ~= nil then
    merged.keymaps = vim.deepcopy(override.keymaps)
  end
  return merged
end

---@param identifier string
---@param opts codex.ProfileOpts
---@param base codex.ProfileConfig
---@param snacks_count? integer
---@return { config: codex.ProfileConfig, keymaps: codex.GlobalKeymapConfig }
local function resolve_profile(identifier, opts, base, snacks_count)
  local auto_start = opts.auto_start
  if auto_start == nil then
    auto_start = base.auto_start
  end

  local profile_name = opts.profile_name
  if profile_name == nil then
    profile_name = identifier
  end

  local launch = launch_config.merge_launch(base.launch, opts.launch)
  local terminal = merge_terminal(base.terminal, opts.terminal)
  validation.validate_resolved_terminal(terminal)
  return {
    config = {
      profile_identifier = identifier,
      profile_name = profile_name,
      auto_start = auto_start,
      launch = launch,
      terminal = terminal,
      log = vim.deepcopy(base.log),
      hooks = vim.deepcopy(base.hooks),
      snacks_count = snacks_count,
    },
    keymaps = vim.deepcopy(opts.keymaps or {}),
  }
end

---@param input table<string, codex.ProfileOpts>
---@param stock codex.ProfileConfig
---@return table<string, { config: codex.ProfileConfig, keymaps: codex.GlobalKeymapConfig }>
function M.resolve_profiles(input, stock)
  local names = {}
  for name in pairs(input) do
    if name ~= "default" then
      table.insert(names, name)
    end
  end
  table.sort(names)

  local profiles = { default = resolve_profile("default", input.default, stock) }
  local base = profiles.default.config
  local default_count = base.terminal.provider_opts.snacks.count
  if #names > 0 and type(default_count) == "number" and default_count < 0 then
    error(
      "codex: terminal.provider_opts.snacks.count cannot be negative on profiles.default when named profiles are configured"
    )
  end
  for index, name in ipairs(names) do
    profiles[name] = resolve_profile(name, input[name], base, -index)
  end
  return profiles
end

return M
