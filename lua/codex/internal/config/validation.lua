local M = {}
local defaults = require("codex.internal.config.defaults")
local keymaps = require("codex.internal.nvim.keymaps")
local hooks = require("codex.hooks")

local valid_setup_keys = { profiles = true, log = true, hooks = true }
local valid_profile_keys = {
  profile_name = true,
  auto_start = true,
  launch = true,
  terminal = true,
  keymaps = true,
}

local valid_providers = { auto = true, snacks = true, native = true }
local valid_windows = { vsplit = true, hsplit = true, float = true }
local valid_provider_opt_keys = { native = true, snacks = true }
local valid_native_provider_opt_keys = { window = true, vsplit = true, hsplit = true, float = true }
local valid_native_float_keys = {
  width_pct = true,
  height_pct = true,
  border = true,
  title = true,
  title_pos = true,
}
local valid_keymap_binding_keys = { mode = true, action = true, desc = true }
local valid_log_levels = { debug = true, info = true, warn = true, error = true }
local valid_launch_keys = {
  cmd = true,
  env = true,
  cwd = true,
}
---@param source table
---@param known table
---@param prefix string
---@param unknown string[]
local function collect_unknown_keys(source, known, prefix, unknown)
  for key in pairs(source) do
    if known[key] == nil then
      table.insert(unknown, prefix .. "." .. tostring(key))
    end
  end
end

---@param cmd any
---@param field_name string
---@return nil
local function validate_cmd_value(cmd, field_name)
  local cmd_type = type(cmd)
  if cmd_type == "string" then
    if cmd:match("%S") == nil then
      error(string.format("codex: %s must be a non-empty string or list of strings", field_name))
    end
    return
  end

  if cmd_type ~= "table" then
    error(string.format("codex: %s must be a string or list of strings", field_name))
  end

  if not vim.islist(cmd) then
    error(string.format("codex: %s must be a dense list of strings", field_name))
  end
  if #cmd == 0 then
    error(string.format("codex: %s must not be an empty list", field_name))
  end

  for index, entry in ipairs(cmd) do
    if type(entry) ~= "string" then
      error(string.format("codex: %s[%d] must be a string", field_name, index))
    end
    if index == 1 and entry:match("%S") == nil then
      error(string.format("codex: %s[1] executable must be a non-empty string", field_name))
    end
  end
end

---@param launch any
---@param prefix? string
---@return nil
function M.validate_launch_override(launch, prefix)
  local label = prefix or "launch"
  if type(launch) ~= "table" then
    error(string.format("codex: %s must be a table", label))
  end

  local unknown_launch = {}
  collect_unknown_keys(launch, valid_launch_keys, label, unknown_launch)
  if #unknown_launch > 0 then
    table.sort(unknown_launch)
    error("codex: unknown launch config key(s): " .. table.concat(unknown_launch, ", "))
  end

  if launch.cmd ~= nil then
    validate_cmd_value(launch.cmd, label .. ".cmd")
  end

  if launch.cwd ~= nil and launch.cwd ~= false then
    if type(launch.cwd) ~= "string" or launch.cwd == "" then
      error(string.format("codex: %s.cwd must be a non-empty string, false, or nil", label))
    end
  end

  if launch.env ~= nil then
    if type(launch.env) ~= "table" then
      error(string.format("codex: %s.env must be a table", label))
    end
    for key, value in pairs(launch.env) do
      if type(key) ~= "string" or key == "" then
        error(string.format("codex: %s.env keys must be non-empty strings", label))
      end
      if type(value) ~= "string" then
        error(string.format("codex: %s.env.%s must be a string", label, key))
      end
    end
  end
end

---@param hooks_tbl any
---@return nil
function M.validate_hooks_table(hooks_tbl)
  vim.validate({
    hooks = { hooks_tbl, "table" },
  })

  local unknown = {}
  for key, value in pairs(hooks_tbl) do
    if not hooks.is_valid_hook_key(key) then
      table.insert(unknown, "hooks." .. tostring(key))
    elseif type(value) ~= "function" and value ~= nil then
      error(string.format("codex: hooks.%s must be a function or nil", key))
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    error("codex: unknown hook key(s): " .. table.concat(unknown, ", "))
  end
end

---@param log_tbl any
---@return nil
function M.validate_log_table(log_tbl)
  vim.validate({
    log = { log_tbl, "table" },
    ["log.level"] = { log_tbl.level, "string" },
    ["log.verbose"] = { log_tbl.verbose, "boolean" },
  })

  local unknown_log = {}
  collect_unknown_keys(log_tbl, defaults.log, "log", unknown_log)
  if #unknown_log > 0 then
    table.sort(unknown_log)
    error("codex: unknown log config key(s): " .. table.concat(unknown_log, ", "))
  end

  if not valid_log_levels[log_tbl.level] then
    error(
      string.format(
        "codex: invalid log.level %q, expected one of: debug, info, warn, error",
        log_tbl.level
      )
    )
  end
end

---@param keymaps_tbl any
---@param prefix string
---@return nil
local function validate_keymaps(keymaps_tbl, prefix)
  if type(keymaps_tbl) ~= "table" then
    error(string.format("codex: %s: expected table, got %s", prefix, type(keymaps_tbl)))
  end

  for lhs, binding in pairs(keymaps_tbl) do
    if type(lhs) ~= "string" or lhs == "" then
      error(string.format("codex: %s keys must be non-empty strings", prefix))
    end

    if type(binding) ~= "table" then
      error(
        string.format("codex: %s[%q] must be a table with fields: mode, action, desc?", prefix, lhs)
      )
    end

    local binding_prefix = string.format("%s[%q]", prefix, lhs)
    local unknown_binding_keys = {}
    collect_unknown_keys(binding, valid_keymap_binding_keys, binding_prefix, unknown_binding_keys)
    if #unknown_binding_keys > 0 then
      table.sort(unknown_binding_keys)
      error("codex: unknown keymap key(s): " .. table.concat(unknown_binding_keys, ", "))
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
      if not vim.islist(binding.mode) then
        error(string.format("codex: %s.mode must be a list of strings", binding_prefix))
      end
      if #binding.mode == 0 then
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

---@param terminal_tbl table
---@param prefix string
---@return nil
local function validate_terminal_keys(terminal_tbl, prefix)
  local unknown = {}
  collect_unknown_keys(terminal_tbl, defaults.terminal, prefix, unknown)

  local nested_terminal_tables = {
    { key = "provider_opts", defaults = valid_provider_opt_keys },
    { key = "startup", defaults = defaults.terminal.startup },
  }
  for _, entry in ipairs(nested_terminal_tables) do
    local value = terminal_tbl[entry.key]
    if value ~= nil then
      if type(value) ~= "table" then
        error(string.format("codex: %s.%s: expected table, got %s", prefix, entry.key, type(value)))
      end
      collect_unknown_keys(value, entry.defaults, prefix .. "." .. entry.key, unknown)
    end
  end

  if type(terminal_tbl.provider_opts) == "table" then
    local snacks_opts = terminal_tbl.provider_opts.snacks
    if snacks_opts ~= nil and type(snacks_opts) ~= "table" then
      error(
        string.format(
          "codex: %s.provider_opts.snacks: expected table, got %s",
          prefix,
          type(snacks_opts)
        )
      )
    end

    local native_opts = terminal_tbl.provider_opts.native
    if native_opts ~= nil then
      if type(native_opts) ~= "table" then
        error(
          string.format(
            "codex: %s.provider_opts.native: expected table, got %s",
            prefix,
            type(native_opts)
          )
        )
      end
      collect_unknown_keys(
        native_opts,
        valid_native_provider_opt_keys,
        prefix .. ".provider_opts.native",
        unknown
      )

      local nested_native_tables = {
        { key = "vsplit", defaults = defaults.terminal.provider_opts.native.vsplit },
        { key = "hsplit", defaults = defaults.terminal.provider_opts.native.hsplit },
        { key = "float", defaults = valid_native_float_keys },
      }
      for _, entry in ipairs(nested_native_tables) do
        local value = native_opts[entry.key]
        if value ~= nil then
          if type(value) ~= "table" then
            error(
              string.format(
                "codex: %s.provider_opts.native.%s: expected table, got %s",
                prefix,
                entry.key,
                type(value)
              )
            )
          end
          collect_unknown_keys(
            value,
            entry.defaults,
            prefix .. ".provider_opts.native." .. entry.key,
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

  if terminal_tbl.keymaps ~= nil then
    validate_keymaps(terminal_tbl.keymaps, prefix .. ".keymaps")
  end
end

---@param terminal codex.TerminalConfig
---@return nil
function M.validate_resolved_terminal(terminal)
  vim.validate({
    provider = { terminal.provider, "string" },
    ["terminal.auto_close"] = { terminal.auto_close, "boolean" },
    ["terminal.keymaps"] = { terminal.keymaps, "table" },
    ["terminal.provider_opts"] = { terminal.provider_opts, "table" },
    ["terminal.provider_opts.native"] = { terminal.provider_opts.native, "table" },
    ["terminal.provider_opts.snacks"] = { terminal.provider_opts.snacks, "table" },
  })
  local native_opts = terminal.provider_opts.native

  if not valid_providers[terminal.provider] then
    error(
      string.format(
        "codex: invalid terminal.provider %q, expected one of: auto, snacks, native",
        terminal.provider
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
    ["terminal.provider_opts.native.float.title"] = { native_opts.float.title, "string", true },
    ["terminal.provider_opts.native.float.title_pos"] = { native_opts.float.title_pos, "string" },
    ["terminal.startup"] = { terminal.startup, "table" },
    ["terminal.startup.timeout_ms"] = { terminal.startup.timeout_ms, "number" },
    ["terminal.startup.retry_interval_ms"] = { terminal.startup.retry_interval_ms, "number" },
    ["terminal.startup.grace_ms"] = { terminal.startup.grace_ms, "number" },
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

  if terminal.startup.timeout_ms < 1 then
    error("codex: terminal.startup.timeout_ms must be >= 1")
  end

  if terminal.startup.retry_interval_ms < 1 then
    error("codex: terminal.startup.retry_interval_ms must be >= 1")
  end

  if terminal.startup.grace_ms < 0 then
    error("codex: terminal.startup.grace_ms must be >= 0")
  end
end

local function validate_profile_opts(opts, name)
  local prefix = "profiles." .. name
  if type(opts) ~= "table" then
    error(string.format("codex: %s must be a table", prefix))
  end

  local unknown = {}
  collect_unknown_keys(opts, valid_profile_keys, prefix, unknown)
  if #unknown > 0 then
    table.sort(unknown)
    error("codex: unknown profile config key(s): " .. table.concat(unknown, ", "))
  end
  if opts.profile_name ~= nil then
    if type(opts.profile_name) ~= "string" or opts.profile_name:match("%S") == nil then
      error(string.format("codex: %s.profile_name must be a non-empty string", prefix))
    end
  end
  if opts.auto_start ~= nil and type(opts.auto_start) ~= "boolean" then
    error(
      string.format("codex: %s.auto_start: expected boolean, got %s", prefix, type(opts.auto_start))
    )
  end
  if opts.launch ~= nil then
    M.validate_launch_override(opts.launch, prefix .. ".launch")
  end
  if opts.terminal ~= nil then
    if type(opts.terminal) ~= "table" then
      error(
        string.format("codex: %s.terminal: expected table, got %s", prefix, type(opts.terminal))
      )
    end
    validate_terminal_keys(opts.terminal, prefix .. ".terminal")
  end
  if opts.keymaps ~= nil then
    validate_keymaps(opts.keymaps, prefix .. ".keymaps")
  end
end

function M.validate_setup_type(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("codex: setup opts must be a table or nil")
  end
end

function M.validate_setup(opts)
  M.validate_setup_type(opts)
  if opts == nil then
    return
  end
  local unknown = {}
  for key in pairs(opts) do
    if not valid_setup_keys[key] then
      table.insert(unknown, tostring(key))
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    error("codex: unknown config key(s): " .. table.concat(unknown, ", "))
  end

  for _, key in ipairs({ "log", "hooks" }) do
    if opts[key] ~= nil and type(opts[key]) ~= "table" then
      error(string.format("codex: %s: expected table, got %s", key, type(opts[key])))
    end
  end

  local profiles = opts.profiles
  if profiles == nil then
    return
  end
  if type(profiles) ~= "table" then
    error("codex: profiles must be a table")
  end
  if profiles.default == nil then
    error("codex: profiles.default is required when profiles is provided")
  end
  for name in pairs(profiles) do
    if type(name) ~= "string" or name == "" then
      error("codex: profile names must be non-empty strings")
    end
  end
  validate_profile_opts(profiles.default, "default")
  for name, raw_profile in pairs(profiles) do
    if name ~= "default" then
      validate_profile_opts(raw_profile, name)
    end
  end
end

return M
