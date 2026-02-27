local log = require("codex.logger")

local M = {}

local provider_modules = {
  native = "codex.providers.native",
  snacks = "codex.providers.snacks",
}

local loaded = {}
---@type codex.Provider|nil
local auto_resolved_provider = nil
---@type string|nil
local auto_resolved_name = nil

--- Lazy-load and cache a provider module by name.
---@param name codex.ProviderName|"native"|"snacks"
---@return codex.Provider|nil
local function load_provider(name)
  if loaded[name] then
    return loaded[name]
  end

  local mod_path = provider_modules[name]
  if not mod_path then
    return nil
  end

  local ok, mod = pcall(require, mod_path)
  if not ok then
    log.warn("failed to load provider %q: %s", name, mod)
    return nil
  end

  loaded[name] = mod
  return mod
end

--- Resolve a provider name to a loaded provider module, auto-detecting if needed.
---@param provider_name codex.ProviderName
---@return codex.Provider provider
---@return string resolved_name
function M.resolve(provider_name)
  if provider_name == "auto" then
    if auto_resolved_provider and auto_resolved_name then
      return auto_resolved_provider, auto_resolved_name
    end

    local snacks = load_provider("snacks")
    if snacks and snacks.is_available() then
      log.debug("auto-resolved provider to snacks")
      auto_resolved_provider = snacks
      auto_resolved_name = "snacks"
      return snacks, "snacks"
    end

    local native = load_provider("native")
    log.debug("auto-resolved provider to native")
    auto_resolved_provider = native
    auto_resolved_name = "native"
    return native, "native"
  end

  local provider = load_provider(provider_name)
  if not provider then
    error(string.format("codex: unknown provider %q", provider_name))
  end

  if not provider.is_available() then
    error(string.format("codex: provider %q is not available", provider_name))
  end

  return provider, provider_name
end

--- Clear the cached provider modules so they are re-loaded on next resolve.
---@return nil
function M.reset()
  loaded = {}
  auto_resolved_provider = nil
  auto_resolved_name = nil
end

return M
