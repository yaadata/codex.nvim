local M = {}

M.defaults = {
  cmd = "codex",
  args = {},
  env = {},
  auto_start = false,
  terminal = {
    provider = "auto",
    split_side = "right",
    split_width_pct = 40,
    auto_close = false,
    provider_opts = {
      snacks = {},
      external = { cmd = nil },
    },
  },
  cwd = nil,
  log_level = "warn",
}

local valid_providers = { auto = true, snacks = true, native = true, external = true, none = true }

function M.validate(config)
  vim.validate({
    cmd = { config.cmd, "string" },
    args = { config.args, "table" },
    env = { config.env, "table" },
    auto_start = { config.auto_start, "boolean" },
    terminal = { config.terminal, "table" },
    log_level = { config.log_level, "string" },
  })

  vim.validate({
    provider = { config.terminal.provider, "string" },
    split_side = { config.terminal.split_side, "string" },
    split_width_pct = { config.terminal.split_width_pct, "number" },
  })

  if not valid_providers[config.terminal.provider] then
    error(
      string.format(
        "codex: invalid terminal.provider %q, expected one of: auto, snacks, native, external, none",
        config.terminal.provider
      )
    )
  end

  if config.terminal.split_width_pct < 10 or config.terminal.split_width_pct > 90 then
    error("codex: terminal.split_width_pct must be between 10 and 90")
  end

  if config.terminal.split_side ~= "left" and config.terminal.split_side ~= "right" then
    error("codex: terminal.split_side must be 'left' or 'right'")
  end

  return true
end

function M.apply(user_opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
  M.validate(config)
  return config
end

return M
