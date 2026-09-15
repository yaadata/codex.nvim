local terminal_io = require("codex.runtime.terminal_io")
local M = {}

---@class codex.SendSkillOptions
---@field plugin string|nil name of plugin the skill belongs to
---@field name string name of the skill

---@class codex.SendSkillCreateOptions
---@field dispatch_send fun(text: string, opts?: codex.DispatchSendOpts): codex.SendResult

---@class codex.SendSkill
---@field send_skill fun(opts?: codex.SendSkillOptions): codex.SendResult

local function valid_value(value)
  return type(value) == "string" and value:match("^[%w][%w_%-]*$") ~= nil
end

---@param opts codex.SendSkillCreateOptions
---@return codex.SendSkill
function M.create(opts)
  local dispatch_send = opts.dispatch_send

  local function send_skill(skill)
    if type(skill) ~= "table" or not valid_value(skill.name) then
      return false, "invalid skill name"
    end

    if skill.plugin ~= nil and not valid_value(skill.plugin) then
      return false, "invalid plugin name"
    end

    local name = skill.name
    if skill.plugin then
      name = skill.plugin .. ":" .. name
    end

    local payload = terminal_io.encode_bracketed_paste("$" .. name .. " ")
    return dispatch_send(payload)
  end
  return {
    send_skill = send_skill,
  }
end

return M
