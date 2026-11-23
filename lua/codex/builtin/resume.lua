local enum = require("codex.enums.harness")
local config_mod = require("codex.config")
local M = {}

local supports_non_last_resume = {
  [enum.CLAUDE] = true,
  [enum.CODEX] = true,
  [enum.PI] = true,
}

local resume_args = {
  [enum.ANTIGRAVITY] = function(_)
    return { "--continue" }
  end,
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

  local config = plugin.get_profile()
  local raw_cmd = config and config.launch and config.launch.cmd
  local cmd = config_mod.split_command(raw_cmd)
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

  if
    (not opts.last and not (supports_non_last_resume[opts.harness] or false))
    or plugin.session.is_running()
  then
    return require("codex.builtin.slash_command").execute({
      command = "resume",
    })
  end

  local build = resume_args[detect_harness(plugin, opts)]
  return plugin.session.open(true, build(opts))
end
return M
