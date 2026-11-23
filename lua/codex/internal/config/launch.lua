local M = {}

---@param cmd string|string[]|nil
---@return string|nil executable
---@return string[] args
function M.split_command(cmd)
  if type(cmd) == "string" then
    return cmd, {}
  end
  if type(cmd) == "table" then
    local executable = cmd[1]
    local args = {}
    for index = 2, #cmd do
      table.insert(args, cmd[index])
    end
    return executable, args
  end
  return nil, {}
end

---@param base_launch codex.LaunchConfig
---@param override_launch? codex.ProfileLaunch
---@return codex.LaunchConfig
function M.merge_launch(base_launch, override_launch)
  override_launch = override_launch or {}
  local cwd = override_launch.cwd
  if cwd == nil then
    cwd = base_launch.cwd
  end

  local env = override_launch.env
  if env == nil or next(env) ~= nil then
    env = vim.tbl_extend("force", {}, base_launch.env, env or {})
  else
    env = {}
  end

  return {
    cmd = vim.deepcopy(override_launch.cmd or base_launch.cmd),
    cwd = cwd or nil,
    env = env,
  }
end

return M
