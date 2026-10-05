local M = {}
local enum = require("codex.enums.skill_style")

---@class codex.AgentSkillOptions
---@field plugin string|nil name of plugin the skill belongs to
---@field name string name of the skill

---@param opts codex.AgentSkillOptions
---@return string? payload
---@return codex.Error error
local function construct(opts)
  local function valid_value(value)
    return type(value) == "string" and value:match("^[%w][%w_%-]*$") ~= nil
  end

  if type(opts) ~= "table" or not valid_value(opts.name) then
    return nil, "invalid skill name"
  end

  if opts.plugin ~= nil and not valid_value(opts.plugin) then
    return nil, "invalid plugin name"
  end

  local name = opts.name
  if opts.plugin then
    name = opts.plugin .. ":" .. name
  end
  return name, nil
end

---@param opts codex.AgentSkillOptions
---@param style? codex.AgentSkillStyle
---@return string? payload
---@return codex.Error error
function M.format(opts, style)
  local constructed, err = construct(opts)
  if err ~= nil then
    return nil, err, nil
  end
  if style ~= nil and style == enum.SLASH then
    return "/" .. constructed
  end
  return "$" .. constructed, nil
end

return M
