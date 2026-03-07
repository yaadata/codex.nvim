local M = {}
local keymaps = require("codex.keymaps")

---@type codex.Config
M.defaults = {
  launch = {
    cmd = "codex",
    args = {},
    env = {},
    auto_start = true,
    cwd = nil,
  },
  terminal = {
    provider = "auto",
    auto_close = true,
    startup = {
      timeout_ms = 2000,
      retry_interval_ms = 50,
      grace_ms = 800,
    },
    keymaps = {
      -- User-defined terminal-local keymaps (empty by default).
    },
    provider_opts = {
      native = {
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
      },
      snacks = {},
    },
  },
  log = {
    level = "warn",
    verbose = false,
  },
}

local valid_providers = { auto = true, snacks = true, native = true }
local valid_windows = { vsplit = true, hsplit = true, float = true }
local valid_provider_opt_keys = { native = true, snacks = true }
local valid_native_provider_opt_keys = { window = true, vsplit = true, hsplit = true, float = true }
local valid_terminal_keymap_binding_keys = { mode = true, action = true, desc = true }
local valid_log_levels = { debug = true, info = true, warn = true, error = true }
local valid_launch_keys = {
  cmd = true,
  args = true,
  env = true,
  auto_start = true,
  cwd = true,
}
local valid_config_keys = {
  launch = true,
  terminal = true,
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
---@return nil
local function validate_terminal_keymaps(config)
  for lhs, binding in pairs(config.terminal.keymaps) do
    if type(lhs) ~= "string" or lhs == "" then
      error("codex: terminal.keymaps keys must be non-empty strings")
    end

    if type(binding) ~= "table" then
      error(
        string.format(
          "codex: terminal.keymaps[%q] must be a table with fields: mode, action, desc?",
          lhs
        )
      )
    end

    local binding_prefix = string.format("terminal.keymaps[%q]", lhs)
    local unknown_binding_keys = {}
    collect_unknown_keys(
      binding,
      valid_terminal_keymap_binding_keys,
      binding_prefix,
      unknown_binding_keys
    )
    if #unknown_binding_keys > 0 then
      table.sort(unknown_binding_keys)
      error("codex: unknown terminal keymap key(s): " .. table.concat(unknown_binding_keys, ", "))
    end

    vim.validate({
      [binding_prefix .. ".action"] = { binding.action, "function" },
    })

    if type(binding.desc) ~= "string" and binding.desc ~= nil then
      error(string.format("codex: %s.desc must be a string or nil", binding_prefix))
    end

    local mode_type = type(binding.mode)
    if mode_type ~= "string" and mode_type ~= "table" then
      error(string.format("codex: %s.mode must be a string or list of strings", binding_prefix))
    end

    if mode_type == "table" then
      if vim.tbl_isempty(binding.mode) then
        error(string.format("codex: %s.mode must not be an empty list", binding_prefix))
      end

      for index, mode in ipairs(binding.mode) do
        if type(mode) ~= "string" then
          error(string.format("codex: %s.mode[%d] must be a string", binding_prefix, index))
        end
      end
    end

    if binding.desc == nil and not keymaps.is_builtin_action(binding.action) then
      error(string.format("codex: %s.desc is required for custom actions", binding_prefix))
    end
  end
end

---@param config codex.Config
---@return true
function M.validate(config)
  vim.validate({
    launch = { config.launch, "table" },
    terminal = { config.terminal, "table" },
    log = { config.log, "table" },
  })

  local launch = config.launch or {}
  vim.validate({
    ["launch.cmd"] = { launch.cmd, "string" },
    ["launch.args"] = { launch.args, "table" },
    ["launch.env"] = { launch.env, "table" },
    ["launch.auto_start"] = { launch.auto_start, "boolean" },
  })
  if launch.cwd ~= nil and type(launch.cwd) ~= "string" then
    error("codex: launch.cwd must be a string or nil")
  end

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
    { key = "provider_opts", defaults = valid_provider_opt_keys },
    { key = "startup", defaults = M.defaults.terminal.startup },
  }
  for _, entry in ipairs(nested_terminal_tables) do
    local value = config.terminal[entry.key]
    if type(value) == "table" then
      collect_unknown_keys(value, entry.defaults, "terminal." .. entry.key, unknown)
    end
  end
  if type(config.terminal.provider_opts) == "table" then
    local native_opts = config.terminal.provider_opts.native
    if type(native_opts) == "table" then
      collect_unknown_keys(
        native_opts,
        valid_native_provider_opt_keys,
        "terminal.provider_opts.native",
        unknown
      )

      local nested_native_tables = {
        { key = "vsplit", defaults = M.defaults.terminal.provider_opts.native.vsplit },
        { key = "hsplit", defaults = M.defaults.terminal.provider_opts.native.hsplit },
        { key = "float", defaults = M.defaults.terminal.provider_opts.native.float },
      }
      for _, entry in ipairs(nested_native_tables) do
        local value = native_opts[entry.key]
        if type(value) == "table" then
          collect_unknown_keys(
            value,
            entry.defaults,
            "terminal.provider_opts.native." .. entry.key,
            unknown
          )
        end
      end
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    error("codex: unknown terminal config key(s): " .. table.concat(unknown, ", "))
  end

  local unknown_launch = {}
  if type(config.launch) == "table" then
    collect_unknown_keys(config.launch, valid_launch_keys, "launch", unknown_launch)
  end
  if #unknown_launch > 0 then
    table.sort(unknown_launch)
    error("codex: unknown launch config key(s): " .. table.concat(unknown_launch, ", "))
  end

  local unknown_log = {}
  if type(config.log) == "table" then
    collect_unknown_keys(config.log, M.defaults.log, "log", unknown_log)
  end
  if #unknown_log > 0 then
    table.sort(unknown_log)
    error("codex: unknown log config key(s): " .. table.concat(unknown_log, ", "))
  end

  for key, value in pairs(config.launch.env) do
    if type(key) ~= "string" then
      error("codex: launch.env keys must be strings")
    end
    if type(value) ~= "string" then
      error(string.format("codex: launch.env.%s must be a string", key))
    end
  end

  vim.validate({
    provider = { config.terminal.provider, "string" },
    ["terminal.keymaps"] = { config.terminal.keymaps, "table" },
    ["terminal.provider_opts"] = { config.terminal.provider_opts, "table" },
    ["terminal.provider_opts.native"] = { config.terminal.provider_opts.native, "table" },
    ["terminal.provider_opts.snacks"] = { config.terminal.provider_opts.snacks, "table" },
  })
  local native_opts = config.terminal.provider_opts.native

  validate_terminal_keymaps(config)

  if not valid_providers[config.terminal.provider] then
    error(
      string.format(
        "codex: invalid terminal.provider %q, expected one of: auto, snacks, native",
        config.terminal.provider
      )
    )
  end

  if not valid_windows[native_opts.window] then
    error(
      string.format(
        "codex: invalid terminal.provider_opts.native.window %q, expected one of: vsplit, hsplit, float",
        native_opts.window
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
    ["terminal.provider_opts.native.window"] = { native_opts.window, "string" },
    ["terminal.provider_opts.native.vsplit"] = { native_opts.vsplit, "table" },
    ["terminal.provider_opts.native.vsplit.side"] = { native_opts.vsplit.side, "string" },
    ["terminal.provider_opts.native.vsplit.size_pct"] = { native_opts.vsplit.size_pct, "number" },
    ["terminal.provider_opts.native.hsplit"] = { native_opts.hsplit, "table" },
    ["terminal.provider_opts.native.hsplit.side"] = { native_opts.hsplit.side, "string" },
    ["terminal.provider_opts.native.hsplit.size_pct"] = { native_opts.hsplit.size_pct, "number" },
    ["terminal.provider_opts.native.float"] = { native_opts.float, "table" },
    ["terminal.provider_opts.native.float.width_pct"] = { native_opts.float.width_pct, "number" },
    ["terminal.provider_opts.native.float.height_pct"] = { native_opts.float.height_pct, "number" },
    ["terminal.provider_opts.native.float.border"] = { native_opts.float.border, "string" },
    ["terminal.provider_opts.native.float.title"] = { native_opts.float.title, "string" },
    ["terminal.provider_opts.native.float.title_pos"] = { native_opts.float.title_pos, "string" },
    ["terminal.startup"] = { config.terminal.startup, "table" },
    ["terminal.startup.timeout_ms"] = { config.terminal.startup.timeout_ms, "number" },
    ["terminal.startup.retry_interval_ms"] = { config.terminal.startup.retry_interval_ms, "number" },
    ["terminal.startup.grace_ms"] = { config.terminal.startup.grace_ms, "number" },
  })

  if native_opts.vsplit.side ~= "left" and native_opts.vsplit.side ~= "right" then
    error("codex: terminal.provider_opts.native.vsplit.side must be 'left' or 'right'")
  end

  if native_opts.vsplit.size_pct < 10 or native_opts.vsplit.size_pct > 90 then
    error("codex: terminal.provider_opts.native.vsplit.size_pct must be between 10 and 90")
  end

  if native_opts.hsplit.side ~= "top" and native_opts.hsplit.side ~= "bottom" then
    error("codex: terminal.provider_opts.native.hsplit.side must be 'top' or 'bottom'")
  end

  if native_opts.hsplit.size_pct < 10 or native_opts.hsplit.size_pct > 90 then
    error("codex: terminal.provider_opts.native.hsplit.size_pct must be between 10 and 90")
  end

  if native_opts.float.width_pct < 10 or native_opts.float.width_pct > 100 then
    error("codex: terminal.provider_opts.native.float.width_pct must be between 10 and 100")
  end

  if native_opts.float.height_pct < 10 or native_opts.float.height_pct > 100 then
    error("codex: terminal.provider_opts.native.float.height_pct must be between 10 and 100")
  end

  if
    native_opts.float.title_pos ~= "left"
    and native_opts.float.title_pos ~= "center"
    and native_opts.float.title_pos ~= "right"
  then
    error(
      "codex: terminal.provider_opts.native.float.title_pos must be 'left', 'center', or 'right'"
    )
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
