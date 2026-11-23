local launch = require("codex.internal.config.launch")
local validation = require("codex.internal.config.validation")

local M = {
  defaults = require("codex.internal.config.defaults"),
  split_command = launch.split_command,
  merge_launch = launch.merge_launch,
  validate_launch_override = validation.validate_launch_override,
}

function M.prepare_setup(opts)
  validation.validate_setup(opts)
  opts = opts or {}
  local base = vim.tbl_extend("force", {}, M.defaults)
  base.log = vim.tbl_extend("force", {}, base.log, opts.log or {})
  base.hooks = vim.tbl_extend("force", {}, base.hooks, opts.hooks or {})
  validation.validate_log_table(base.log)
  validation.validate_hooks_table(base.hooks)
  return opts.profiles or { default = {} }, base
end

return M
