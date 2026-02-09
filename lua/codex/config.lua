local M = {}

---@type codex.Config
M.defaults = {
  cmd = "codex",
  args = {},
  env = {},
  auto_start = false,
  terminal = {
    provider = "auto",
    window = "vsplit",
    vsplit = {
      side = "right",
      size_pct = 40,
    },
    hsplit = {
      side = "bottom",
      size_pct = 30,
    },
    float = {
      width_pct = 80,
      height_pct = 80,
      border = "rounded",
      title = " Codex ",
      title_pos = "center",
    },
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
local valid_windows = { vsplit = true, hsplit = true, float = true }

---@param config codex.Config
---@return true
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
    window = { config.terminal.window, "string" },
    vsplit = { config.terminal.vsplit, "table" },
    hsplit = { config.terminal.hsplit, "table" },
    float = { config.terminal.float, "table" },
  })

  if not valid_providers[config.terminal.provider] then
    error(
      string.format(
        "codex: invalid terminal.provider %q, expected one of: auto, snacks, native, external, none",
        config.terminal.provider
      )
    )
  end

  if not valid_windows[config.terminal.window] then
    error(
      string.format(
        "codex: invalid terminal.window %q, expected one of: vsplit, hsplit, float",
        config.terminal.window
      )
    )
  end

  vim.validate({
    ["terminal.vsplit.side"] = { config.terminal.vsplit.side, "string" },
    ["terminal.vsplit.size_pct"] = { config.terminal.vsplit.size_pct, "number" },
    ["terminal.hsplit.side"] = { config.terminal.hsplit.side, "string" },
    ["terminal.hsplit.size_pct"] = { config.terminal.hsplit.size_pct, "number" },
    ["terminal.float.width_pct"] = { config.terminal.float.width_pct, "number" },
    ["terminal.float.height_pct"] = { config.terminal.float.height_pct, "number" },
    ["terminal.float.border"] = { config.terminal.float.border, "string" },
    ["terminal.float.title"] = { config.terminal.float.title, "string" },
    ["terminal.float.title_pos"] = { config.terminal.float.title_pos, "string" },
  })

  if config.terminal.vsplit.side ~= "left" and config.terminal.vsplit.side ~= "right" then
    error("codex: terminal.vsplit.side must be 'left' or 'right'")
  end

  if config.terminal.vsplit.size_pct < 10 or config.terminal.vsplit.size_pct > 90 then
    error("codex: terminal.vsplit.size_pct must be between 10 and 90")
  end

  if config.terminal.hsplit.side ~= "top" and config.terminal.hsplit.side ~= "bottom" then
    error("codex: terminal.hsplit.side must be 'top' or 'bottom'")
  end

  if config.terminal.hsplit.size_pct < 10 or config.terminal.hsplit.size_pct > 90 then
    error("codex: terminal.hsplit.size_pct must be between 10 and 90")
  end

  if config.terminal.float.width_pct < 10 or config.terminal.float.width_pct > 100 then
    error("codex: terminal.float.width_pct must be between 10 and 100")
  end

  if config.terminal.float.height_pct < 10 or config.terminal.float.height_pct > 100 then
    error("codex: terminal.float.height_pct must be between 10 and 100")
  end

  if
    config.terminal.float.title_pos ~= "left"
    and config.terminal.float.title_pos ~= "center"
    and config.terminal.float.title_pos ~= "right"
  then
    error("codex: terminal.float.title_pos must be 'left', 'center', or 'right'")
  end

  return true
end

---@param user_opts? table
---@return codex.Config
function M.apply(user_opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_opts or {})
  M.validate(config)
  return config
end

return M
