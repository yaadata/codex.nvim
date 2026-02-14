local M = {}

---@return boolean
function M.is_available()
  return false
end

---@return false
---@return string err
local function not_implemented()
  return false, "external provider is not yet implemented"
end

---@param _cmd? string
---@param _args? string[]
---@param _env? table<string, string>
---@param _config? codex.Config
---@param _focus? boolean
---@param _on_exit? fun(handle: codex.ProviderHandle): nil
---@return nil handle
---@return string err
function M.open(_cmd, _args, _env, _config, _focus, _on_exit)
  return nil, "external provider is not yet implemented"
end

---@param _handle? codex.ProviderHandle
---@return false
---@return string err
function M.close(_handle)
  return not_implemented()
end

---@param _handle? codex.ProviderHandle
---@param _text? string
---@return false
---@return string err
function M.send(_handle, _text)
  return not_implemented()
end

---@param _handle? codex.ProviderHandle
---@return false
---@return string err
function M.focus(_handle)
  return not_implemented()
end

---@param _handle? codex.ProviderHandle
---@param _cmd? string
---@param _args? string[]
---@param _env? table<string, string>
---@param _config? codex.Config
---@return nil handle
---@return string err
function M.toggle(_handle, _cmd, _args, _env, _config)
  return nil, "external provider is not yet implemented"
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
