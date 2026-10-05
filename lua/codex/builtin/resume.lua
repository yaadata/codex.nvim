local enum = require("codex.enums.harness")
local M = {}

---@param plugin codex.Api
---@param opts? codex.ResumeOpts
---@return codex.Error err
local function default(plugin, opts)
  if plugin.session.is_running() then
    local builtin = require("codex.builtin.slash_command")
    return builtin.execute({
      command = "resume",
    })
  end
  local args = { "--resume" }
  if opts ~= nil and opts.last then
    args = { "--continue" }
  end
  plugin.session.open(true, args)
end

---@param plugin codex.Api
---@param opts? codex.ResumeOpts
---@return codex.Error err
local function codex(plugin, opts)
  if plugin.session.is_running() then
    local builtin = require("codex.builtin.slash_command")
    return builtin.execute({
      command = "resume",
    })
  end
  local args = { "resume" }
  if opts ~= nil and opts.last then
    table.insert(args, "--last")
  end
  plugin.session.open(true, args)
end

---Resumes context in-process when possible, otherwise launches `codex resume`.
---@param opts? codex.ResumeOpts
---@return codex.Error err
function M.resume(opts)
  local plugin = require("codex")
  opts = opts or {}
  if opts.harness == nil or opts.harness == enum.CODEX then
    return codex(plugin, opts)
  end
  return default(plugin, opts)
end
return M
