---@type codex.ProfileConfig
local defaults = {
  profile_identifier = "default",
  profile_name = "default",
  auto_start = true,
  launch = {
    cmd = "codex",
    env = {},
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
          title = nil,
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
  hooks = {},
}

return defaults
