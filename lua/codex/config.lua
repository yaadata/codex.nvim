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
    startup = {
      timeout_ms = 2000,
      retry_interval_ms = 50,
      grace_ms = 700,
    },
    keymaps = {
      toggle = "<C-c>",
      clear_input = "<M-BS>",
      close = false,
      nav = {
        left = "<C-h>",
        down = "<C-j>",
        up = "<C-k>",
        right = "<C-l>",
      },
    },
    provider_opts = {
      snacks = {},
    },
  },
  cwd = nil,
  log = {
    level = "warn",
    verbose = false,
  },
}

local valid_providers = { auto = true, snacks = true, native = true }
local valid_windows = { vsplit = true, hsplit = true, float = true }
local valid_terminal_keymap_actions = {
  toggle = true,
  clear_input = true,
  close = true,
  nav = true,
}
local valid_terminal_keymap_action_list = "toggle, clear_input, close, nav"
local valid_nav_keymap_actions = { left = true, down = true, up = true, right = true }
local valid_nav_keymap_action_list = "left, down, up, right"
local valid_log_levels = { debug = true, info = true, warn = true, error = true }
local valid_config_keys = {
  cmd = true,
  args = true,
  env = true,
  auto_start = true,
  terminal = true,
  cwd = true,
  log = true,
}
---@param source table
---@param known table
---@param prefix string
---@param unknown string[]
local function collect_unknown_keys(source, known, prefix, unknown)
  for key in pairs(source) do
    if known[key] == nil then
      table.insert(unknown, prefix .. "." .. key)
    end
  end
end

---@param config codex.Config
---@return true
function M.validate(config)
  vim.validate({
    cmd = { config.cmd, "string" },
    args = { config.args, "table" },
    env = { config.env, "table" },
    auto_start = { config.auto_start, "boolean" },
    terminal = { config.terminal, "table" },
    log = { config.log, "table" },
  })

  local log = config.log or {}
  vim.validate({
    ["log.level"] = { log.level, "string" },
    ["log.verbose"] = { log.verbose, "boolean" },
  })

  local unknown_config_keys = {}
  for key in pairs(config) do
    if not valid_config_keys[key] then
      table.insert(unknown_config_keys, key)
    end
  end
  if #unknown_config_keys > 0 then
    table.sort(unknown_config_keys)
    error("codex: unknown config key(s): " .. table.concat(unknown_config_keys, ", "))
  end

  local unknown = {}
  collect_unknown_keys(config.terminal, M.defaults.terminal, "terminal", unknown)

  local nested_terminal_tables = {
    { key = "vsplit", defaults = M.defaults.terminal.vsplit },
    { key = "hsplit", defaults = M.defaults.terminal.hsplit },
    { key = "float", defaults = M.defaults.terminal.float },
    { key = "startup", defaults = M.defaults.terminal.startup },
  }
  for _, entry in ipairs(nested_terminal_tables) do
    local value = config.terminal[entry.key]
    if type(value) == "table" then
      collect_unknown_keys(value, entry.defaults, "terminal." .. entry.key, unknown)
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    error("codex: unknown terminal config key(s): " .. table.concat(unknown, ", "))
  end

  local unknown_log = {}
  if type(config.log) == "table" then
    collect_unknown_keys(config.log, M.defaults.log, "log", unknown_log)
  end
  if #unknown_log > 0 then
    table.sort(unknown_log)
    error("codex: unknown log config key(s): " .. table.concat(unknown_log, ", "))
  end

  for key, value in pairs(config.env) do
    if type(key) ~= "string" then
      error("codex: env keys must be strings")
    end
    if type(value) ~= "string" then
      error(string.format("codex: env.%s must be a string", key))
    end
  end

  vim.validate({
    provider = { config.terminal.provider, "string" },
    window = { config.terminal.window, "string" },
    vsplit = { config.terminal.vsplit, "table" },
    hsplit = { config.terminal.hsplit, "table" },
    float = { config.terminal.float, "table" },
    ["terminal.keymaps"] = { config.terminal.keymaps, "table" },
  })

  for action, lhs in pairs(config.terminal.keymaps) do
    if not valid_terminal_keymap_actions[action] then
      error(
        string.format(
          "codex: invalid terminal.keymaps action %q, expected one of: %s",
          action,
          valid_terminal_keymap_action_list
        )
      )
    end

    if action == "nav" then
      if lhs ~= false and type(lhs) ~= "table" then
        error("codex: terminal.keymaps.nav must be a table or false")
      end

      if type(lhs) == "table" then
        for direction, direction_lhs in pairs(lhs) do
          if not valid_nav_keymap_actions[direction] then
            error(
              string.format(
                "codex: invalid terminal.keymaps.nav action %q, expected one of: %s",
                direction,
                valid_nav_keymap_action_list
              )
            )
          end

          if direction_lhs ~= false and type(direction_lhs) ~= "string" then
            error(
              string.format("codex: terminal.keymaps.nav.%s must be a string or false", direction)
            )
          end
        end
      end
    elseif lhs ~= false and type(lhs) ~= "string" then
      error(string.format("codex: terminal.keymaps.%s must be a string or false", action))
    end
  end

  if not valid_providers[config.terminal.provider] then
    error(
      string.format(
        "codex: invalid terminal.provider %q, expected one of: auto, snacks, native",
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

  if not valid_log_levels[config.log.level] then
    error(
      string.format(
        "codex: invalid log.level %q, expected one of: debug, info, warn, error",
        config.log.level
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
    ["terminal.startup"] = { config.terminal.startup, "table" },
    ["terminal.startup.timeout_ms"] = { config.terminal.startup.timeout_ms, "number" },
    ["terminal.startup.retry_interval_ms"] = { config.terminal.startup.retry_interval_ms, "number" },
    ["terminal.startup.grace_ms"] = { config.terminal.startup.grace_ms, "number" },
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

  if config.terminal.startup.timeout_ms < 1 then
    error("codex: terminal.startup.timeout_ms must be >= 1")
  end

  if config.terminal.startup.retry_interval_ms < 1 then
    error("codex: terminal.startup.retry_interval_ms must be >= 1")
  end

  if config.terminal.startup.grace_ms < 0 then
    error("codex: terminal.startup.grace_ms must be >= 0")
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
