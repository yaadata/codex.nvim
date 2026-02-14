local M = {}

---@return boolean
function M.is_available()
  return true
end

---@param _cmd? string
---@param _args? string[]
---@param _env? table<string, string>
---@param _config? codex.Config
---@param _focus? boolean
---@param _on_exit? fun(handle: codex.ProviderHandle): nil
---@return codex.ProviderHandle handle
---@return string|nil err
function M.open(_cmd, _args, _env, _config, _focus, _on_exit)
  return {}
end

---@param _handle? codex.ProviderHandle
---@return boolean ok
---@return string|nil err
function M.close(_handle)
  return true
end

---@param _handle? codex.ProviderHandle
---@param _text? string
---@return boolean ok
---@return string|nil err
function M.send(_handle, _text)
  return true
end

---@param _handle? codex.ProviderHandle
---@return boolean ok
---@return string|nil err
function M.focus(_handle)
  return true
end

---@param _handle? codex.ProviderHandle
---@param _cmd? string
---@param _args? string[]
---@param _env? table<string, string>
---@param _config? codex.Config
---@return codex.ProviderHandle handle
---@return string|nil err
function M.toggle(_handle, _cmd, _args, _env, _config)
  return {}
end

---@param _handle? codex.ProviderHandle
---@return boolean
function M.is_alive(_handle)
  return false
end

---@param _handle? codex.ProviderHandle
---@return boolean
function M.is_ready(_handle)
  return false
end

---@param _handle? codex.ProviderHandle
---@return integer|nil bufnr
function M.get_bufnr(_handle)
  return nil
end

return M
