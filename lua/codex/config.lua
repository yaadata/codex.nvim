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
    keymaps = {
      toggle = "<C-c>",
      close = false,
      nav_left = "<C-h>",
      nav_down = "<C-j>",
      nav_up = "<C-k>",
      nav_right = "<C-l>",
    },
    provider_opts = {
      snacks = {},
      external = { cmd = nil },
    },
  },
  cwd = nil,
  log_level = "warn",
  keymaps = {
    toggle = "<leader>ot",
    open = "<leader>oo",
    focus = "<leader>of",
    close = "<leader>ox",
    send = "<leader>os",
    add = "<leader>oa",
    resume = "<leader>or",
    model = "<leader>om",
    status = "<leader>oi",
    permissions = "<leader>op",
    compact = "<leader>oc",
    review = "<leader>oR",
    diff = "<leader>od",
  },
  keymaps_force = false,
}

local valid_providers = { auto = true, snacks = true, native = true, external = true, none = true }
local valid_windows = { vsplit = true, hsplit = true, float = true }
local valid_terminal_keymap_actions = {
  toggle = true,
  close = true,
  nav_left = true,
  nav_down = true,
  nav_up = true,
  nav_right = true,
}
local valid_terminal_keymap_action_list = "toggle, close, nav_left, nav_down, nav_up, nav_right"
local valid_keymap_actions = {
  toggle = true,
  open = true,
  focus = true,
  close = true,
  send = true,
  add = true,
  resume = true,
  model = true,
  status = true,
  permissions = true,
  compact = true,
  review = true,
  diff = true,
}
local valid_keymap_action_list =
  "toggle, open, focus, close, send, add, resume, model, status, permissions, compact, review, diff"

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
    keymaps_force = { config.keymaps_force, "boolean" },
  })

  for key, value in pairs(config.env) do
    if type(key) ~= "string" then
      error("codex: env keys must be strings")
    end
    if type(value) ~= "string" then
      error(string.format("codex: env.%s must be a string", key))
    end
  end

  if config.keymaps ~= false then
    vim.validate({
      keymaps = { config.keymaps, "table" },
    })
    for action, lhs in pairs(config.keymaps) do
      if not valid_keymap_actions[action] then
        error(
          string.format(
            "codex: invalid keymaps action %q, expected one of: %s",
            action,
            valid_keymap_action_list
          )
        )
      end
      if lhs ~= false and type(lhs) ~= "string" then
        error(string.format("codex: keymaps.%s must be a string or false", action))
      end
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
    if lhs ~= false and type(lhs) ~= "string" then
      error(string.format("codex: terminal.keymaps.%s must be a string or false", action))
    end
  end

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
