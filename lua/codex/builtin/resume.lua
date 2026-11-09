local enum = require("codex.enums.harness")
local M = {}

local resume_args = {
  [enum.CODEX] = function(o)
    return o.last and { "resume", "--last" } or { "resume" }
  end,
  [enum.CLAUDE] = function(o)
    return { o.last and "--continue" or "--resume" }
  end,
  [enum.PI] = function(o)
    return { o.last and "--continue" or "--resume" }
  end,
  [enum.OPENCODE] = function(_)
    return { "--continue" }
  end,
}

---@param plugin codex.Api
---@param opts codex.ResumeOpts
---@return string?
local function detect_harness(plugin, opts)
  if opts.harness then
    return resume_args[opts.harness] and opts.harness or enum.CODEX
  end

  local config = plugin.get_config()
  local cmd = config and config.launch.cmd
  if type(cmd) ~= "string" or cmd == "" then
    return enum.CODEX
  end
  local base = vim.fn.fnamemodify(cmd, ":t:r")
  return resume_args[base] and base or enum.CODEX
end

---Resumes context in-process when possible, otherwise launches `codex resume`.
---@param opts? codex.ResumeOpts
---@return codex.Error err
function M.resume(opts)
  ---@type codex.Api
  local plugin = require("codex")
  opts = opts or {}

  if plugin.session.is_running() then
    return require("codex.builtin.slash_command").execute({
      command = "resume",
    })
  end

  local build = resume_args[detect_harness(plugin, opts)]
  return plugin.session.open(true, build(opts))
end
return M
