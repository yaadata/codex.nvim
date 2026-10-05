local terminal_io = require("codex.runtime.terminal_io")
local M = {}

local function valid_value(value)
  return type(value) == "string" and value:match("^[%w][%w_%-]*$") ~= nil
end

---@param opts codex.AgentSkillCreateOptions
---@return codex.AgentSkill
function M.create(opts)
  local dispatch_send = opts.dispatch_send

  ---@return string payload
  ---@return string|nil error
  local function prompt_payload(skill)
    if type(skill) ~= "table" or not valid_value(skill.name) then
      return "", "invalid skill name"
    end

    if skill.plugin ~= nil and not valid_value(skill.plugin) then
      return "", "invalid plugin name"
    end

    local name = skill.name
    if skill.plugin then
      name = skill.plugin .. ":" .. name
    end
    return "$" .. name, nil
  end

  ---@return codex.Outcome ok
  ---@return string|nil error
  local function send_skill(skill)
    local payload, err = prompt_payload(skill)
    if err ~= nil then
      return false, err
    end
    payload = terminal_io.encode_bracketed_paste(payload)
    return dispatch_send(payload)
  end
  return {
    send = send_skill,
    prompt_payload = prompt_payload,
  }
end

return M
