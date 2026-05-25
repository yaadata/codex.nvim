local M = {}

local valid_hook_keys = {
  on_setup = true,
  on_terminal_open = true,
  on_terminal_restore = true,
  on_terminal_close = true,
}

---Return true when `key` is a supported lifecycle hook.
---@param key string
---@return boolean
function M.is_valid_hook_key(key)
  return valid_hook_keys[key] == true
end

---Return lifecycle hook keys in stable order for docs/tests.
---@return string[]
function M.valid_hook_keys()
  return {
    "on_setup",
    "on_terminal_open",
    "on_terminal_restore",
    "on_terminal_close",
  }
end

---Dispatch a configured lifecycle hook.
---@param deps table
---@param config codex.Config
---@param hook_name string
---@param ctx table
---@return nil
function M.dispatch(deps, config, hook_name, ctx)
  local hooks = config.hooks or {}
  local hook = hooks[hook_name]
  if type(hook) ~= "function" then
    return
  end

  ctx = ctx or {}
  if ctx.event == nil then
    ctx.event = hook_name
  end
  if ctx.config == nil then
    ctx.config = config
  end

  local ok, err = pcall(hook, ctx)
  if not ok and deps.logger and type(deps.logger.warn) == "function" then
    deps.logger.warn("codex hook %s failed: %s", hook_name, tostring(err))
  end
end

return M
