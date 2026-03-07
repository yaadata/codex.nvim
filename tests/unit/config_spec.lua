local config = require("codex.config")
local keymaps = require("codex.keymaps")

describe("codex.config", function()
  local function assert_error_contains(fn, expected)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    assert.is_not_nil(err)
    assert.is_true(string.find(err, expected, 1, true) ~= nil)
  end

  local function make_valid_config()
    return vim.deepcopy(config.defaults)
  end

  describe("defaults", function()
    it("has expected default values", function()
      assert.equals("codex", config.defaults.launch.cmd)
      assert.same({}, config.defaults.launch.args)
      assert.same({}, config.defaults.launch.env)
      assert.is_true(config.defaults.launch.auto_start)
      assert.is_nil(config.defaults.launch.cwd)
      assert.equals("auto", config.defaults.terminal.provider)
      assert.is_true(config.defaults.terminal.auto_close)
      assert.equals("vsplit", config.defaults.terminal.provider_opts.native.window)
      assert.equals("right", config.defaults.terminal.provider_opts.native.vsplit.side)
      assert.equals(40, config.defaults.terminal.provider_opts.native.vsplit.size_pct)
      assert.equals("bottom", config.defaults.terminal.provider_opts.native.hsplit.side)
      assert.equals(30, config.defaults.terminal.provider_opts.native.hsplit.size_pct)
      assert.equals(80, config.defaults.terminal.provider_opts.native.float.width_pct)
      assert.equals(80, config.defaults.terminal.provider_opts.native.float.height_pct)
      assert.equals("rounded", config.defaults.terminal.provider_opts.native.float.border)
      assert.equals(" Codex ", config.defaults.terminal.provider_opts.native.float.title)
      assert.equals("center", config.defaults.terminal.provider_opts.native.float.title_pos)
      assert.equals(2000, config.defaults.terminal.startup.timeout_ms)
      assert.equals(50, config.defaults.terminal.startup.retry_interval_ms)
      assert.equals(800, config.defaults.terminal.startup.grace_ms)
      assert.same({}, config.defaults.terminal.keymaps)
      assert.equals("warn", config.defaults.log.level)
      assert.is_false(config.defaults.log.verbose)
    end)
  end)

  describe("apply", function()
    it("returns defaults when called with nil", function()
      local cfg = config.apply(nil)
      assert.equals("codex", cfg.launch.cmd)
      assert.equals("auto", cfg.terminal.provider)
    end)

    it("returns defaults when called with empty table", function()
      local cfg = config.apply({})
      assert.equals("codex", cfg.launch.cmd)
    end)

    it("merges user overrides", function()
      local cfg = config.apply({
        launch = {
          cmd = "/usr/local/bin/codex",
        },
        terminal = {
          provider_opts = {
            native = {
              window = "hsplit",
              vsplit = { side = "left" },
              hsplit = { size_pct = 50 },
            },
          },
          keymaps = {
            ["<C-d>"] = {
              mode = "t",
              action = keymaps.builtins.close,
            },
          },
        },
      })
      assert.equals("/usr/local/bin/codex", cfg.launch.cmd)
      assert.equals("hsplit", cfg.terminal.provider_opts.native.window)
      assert.equals("left", cfg.terminal.provider_opts.native.vsplit.side)
      assert.equals(40, cfg.terminal.provider_opts.native.vsplit.size_pct)
      assert.equals("bottom", cfg.terminal.provider_opts.native.hsplit.side)
      assert.equals(50, cfg.terminal.provider_opts.native.hsplit.size_pct)
      assert.equals("t", cfg.terminal.keymaps["<C-d>"].mode)
      assert.equals(keymaps.builtins.close, cfg.terminal.keymaps["<C-d>"].action)
      -- non-overridden values preserved
      assert.equals("auto", cfg.terminal.provider)
    end)

    it("accepts cwd override despite nil default", function()
      local cfg = config.apply({ launch = { cwd = "/tmp/project" } })
      assert.equals("/tmp/project", cfg.launch.cwd)
    end)

    it("merges log overrides", function()
      local cfg = config.apply({
        log = {
          level = "info",
          verbose = true,
        },
      })
      assert.equals("info", cfg.log.level)
      assert.is_true(cfg.log.verbose)
    end)

    it("does not mutate defaults", function()
      config.apply({ launch = { cmd = "other" } })
      assert.equals("codex", config.defaults.launch.cmd)
    end)
  end)

  describe("validate", function()
    it("accepts valid config", function()
      assert.is_true(config.validate(config.defaults))
    end)

    it("rejects invalid provider name", function()
      assert.has_error(function()
        config.apply({ terminal = { provider = "invalid" } })
      end, 'codex: invalid terminal.provider "invalid", expected one of: auto, snacks, native')
    end)

    it("rejects invalid log.level", function()
      assert.has_error(function()
        config.apply({ log = { level = "trace" } })
      end, 'codex: invalid log.level "trace", expected one of: debug, info, warn, error')
    end)

    it("rejects non-boolean log.verbose", function()
      assert.has_error(function()
        config.apply({ log = { verbose = "yes" } })
      end, "log.verbose: expected boolean, got string")
    end)

    it("rejects unknown log keys", function()
      assert.has_error(function()
        config.apply({ log = { level = "warn", verbose = false, extra = true } })
      end, "codex: unknown log config key(s): log.extra")
    end)

    it("rejects invalid native window type", function()
      assert.has_error(
        function()
          config.apply({ terminal = { provider_opts = { native = { window = "tabs" } } } })
        end,
        'codex: invalid terminal.provider_opts.native.window "tabs", expected one of: vsplit, hsplit, float'
      )
    end)

    it("rejects invalid native vsplit.side", function()
      assert.has_error(function()
        config.apply({ terminal = { provider_opts = { native = { vsplit = { side = "top" } } } } })
      end, "codex: terminal.provider_opts.native.vsplit.side must be 'left' or 'right'")
    end)

    it("rejects native vsplit.size_pct below 10", function()
      assert.has_error(function()
        config.apply({ terminal = { provider_opts = { native = { vsplit = { size_pct = 5 } } } } })
      end, "codex: terminal.provider_opts.native.vsplit.size_pct must be between 10 and 90")
    end)

    it("rejects native hsplit.side", function()
      assert.has_error(function()
        config.apply({ terminal = { provider_opts = { native = { hsplit = { side = "left" } } } } })
      end, "codex: terminal.provider_opts.native.hsplit.side must be 'top' or 'bottom'")
    end)

    it("rejects native hsplit.size_pct above 90", function()
      assert.has_error(function()
        config.apply({ terminal = { provider_opts = { native = { hsplit = { size_pct = 95 } } } } })
      end, "codex: terminal.provider_opts.native.hsplit.size_pct must be between 10 and 90")
    end)

    it("rejects native float.width_pct below 10", function()
      assert.has_error(function()
        config.apply({ terminal = { provider_opts = { native = { float = { width_pct = 5 } } } } })
      end, "codex: terminal.provider_opts.native.float.width_pct must be between 10 and 100")
    end)

    it("rejects native float.height_pct above 100", function()
      assert.has_error(function()
        config.apply({
          terminal = { provider_opts = { native = { float = { height_pct = 150 } } } },
        })
      end, "codex: terminal.provider_opts.native.float.height_pct must be between 10 and 100")
    end)

    it("rejects invalid native float.title_pos", function()
      assert.has_error(
        function()
          config.apply({
            terminal = { provider_opts = { native = { float = { title_pos = "middle" } } } },
          })
        end,
        "codex: terminal.provider_opts.native.float.title_pos must be 'left', 'center', or 'right'"
      )
    end)

    it("rejects startup.timeout_ms below 1", function()
      assert.has_error(function()
        config.apply({ terminal = { startup = { timeout_ms = 0 } } })
      end, "codex: terminal.startup.timeout_ms must be >= 1")
    end)

    it("rejects startup.retry_interval_ms below 1", function()
      assert.has_error(function()
        config.apply({ terminal = { startup = { retry_interval_ms = 0 } } })
      end, "codex: terminal.startup.retry_interval_ms must be >= 1")
    end)

    it("rejects startup.grace_ms below 0", function()
      assert.has_error(function()
        config.apply({ terminal = { startup = { grace_ms = -1 } } })
      end, "codex: terminal.startup.grace_ms must be >= 0")
    end)

    it("rejects a single unknown terminal key", function()
      assert.has_error(function()
        config.apply({ terminal = { startup_timeout_ms = 5000 } })
      end, "codex: unknown terminal config key(s): terminal.startup_timeout_ms")
    end)

    it("rejects multiple unknown terminal keys", function()
      local ok, err = pcall(config.apply, { terminal = { startup_timeout_ms = 5000, foo = true } })
      assert.is_false(ok)
      assert.is_truthy(string.find(err, "terminal.foo", 1, true))
      assert.is_truthy(string.find(err, "terminal.startup_timeout_ms", 1, true))
    end)

    it("rejects a typo in terminal key names", function()
      assert.has_error(function()
        config.apply({ terminal = { widnow = "vsplit" } })
      end, "codex: unknown terminal config key(s): terminal.widnow")
    end)

    it("rejects removed terminal window key", function()
      assert.has_error(function()
        config.apply({ terminal = { window = "vsplit" } })
      end, "codex: unknown terminal config key(s): terminal.window")
    end)

    it("rejects a typo in terminal.startup key names", function()
      assert.has_error(function()
        config.apply({ terminal = { startup = { retri_interval_ms = 25 } } })
      end, "codex: unknown terminal config key(s): terminal.startup.retri_interval_ms")
    end)

    it("rejects unknown launch keys", function()
      assert.has_error(function()
        config.apply({ launch = { command = "codex" } })
      end, "codex: unknown launch config key(s): launch.command")
    end)

    it("rejects legacy top-level launch keys", function()
      assert.has_error(function()
        config.apply({ cmd = "codex" })
      end, "codex: unknown config key(s): cmd")
      assert.has_error(function()
        config.apply({ args = { "--flag" } })
      end, "codex: unknown config key(s): args")
      assert.has_error(function()
        config.apply({ env = { CODEX_TEST = "1" } })
      end, "codex: unknown config key(s): env")
      assert.has_error(function()
        config.apply({ auto_start = true })
      end, "codex: unknown config key(s): auto_start")
      assert.has_error(function()
        config.apply({ cwd = "/tmp/project" })
      end, "codex: unknown config key(s): cwd")
    end)

    it("rejects non-string launch.cwd", function()
      assert.has_error(function()
        config.apply({ launch = { cwd = 123 } })
      end, "codex: launch.cwd must be a string or nil")
    end)

    it("rejects non-table terminal.provider_opts", function()
      local cfg = make_valid_config()
      cfg.terminal.provider_opts = "bad"
      assert_error_contains(function()
        config.validate(cfg)
      end, "terminal.provider_opts: expected table")
    end)

    it("rejects non-table terminal.provider_opts.native", function()
      local cfg = make_valid_config()
      cfg.terminal.provider_opts.native = "bad"
      assert_error_contains(function()
        config.validate(cfg)
      end, "terminal.provider_opts.native: expected table")
    end)

    it("rejects non-table terminal.provider_opts.snacks", function()
      local cfg = make_valid_config()
      cfg.terminal.provider_opts.snacks = "bad"
      assert_error_contains(function()
        config.validate(cfg)
      end, "terminal.provider_opts.snacks: expected table")
    end)

    it("rejects non-table terminal.keymaps", function()
      local cfg = make_valid_config()
      cfg.terminal.keymaps = true
      assert_error_contains(function()
        config.validate(cfg)
      end, "terminal.keymaps: expected table")
    end)

    it("rejects bad nested field types", function()
      local cfg = make_valid_config()
      cfg.terminal.provider_opts.native.float.title = 123
      assert_error_contains(function()
        config.validate(cfg)
      end, "terminal.provider_opts.native.float.title")
    end)

    it("accepts keymaps with builtin actions and omitted desc", function()
      assert.is_true(config.validate(config.apply({
        terminal = {
          keymaps = {
            ["<C-c>"] = {
              mode = "t",
              action = keymaps.builtins.toggle,
            },
          },
        },
      })))
    end)

    it("accepts keymaps with custom actions when desc is provided", function()
      assert.is_true(config.validate(config.apply({
        terminal = {
          keymaps = {
            ["<leader>ot"] = {
              mode = { "n", "v" },
              action = function() end,
              desc = "Codex: custom test action",
            },
          },
        },
      })))
    end)

    it("rejects non-string terminal.keymaps keys", function()
      local cfg = make_valid_config()
      cfg.terminal.keymaps[1] = {
        mode = "t",
        action = keymaps.builtins.toggle,
      }
      assert.has_error(function()
        config.validate(cfg)
      end, "codex: terminal.keymaps keys must be non-empty strings")
    end)

    it("rejects terminal keymap bindings that are not tables", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              ["<C-c>"] = true,
            },
          },
        })
      end, 'codex: terminal.keymaps["<C-c>"] must be a table with fields: mode, action, desc?')
    end)

    it("rejects unknown terminal keymap binding keys", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              ["<C-c>"] = {
                mode = "t",
                action = keymaps.builtins.toggle,
                foo = true,
              },
            },
          },
        })
      end, 'codex: unknown terminal keymap key(s): terminal.keymaps["<C-c>"].foo')
    end)

    it("rejects missing or invalid terminal keymap mode", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              ["<C-c>"] = {
                action = keymaps.builtins.toggle,
              },
            },
          },
        })
      end, 'codex: terminal.keymaps["<C-c>"].mode must be a string or list of strings')

      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              ["<C-c>"] = {
                mode = { "t", 1 },
                action = keymaps.builtins.toggle,
              },
            },
          },
        })
      end, 'codex: terminal.keymaps["<C-c>"].mode[2] must be a string')
    end)

    it("rejects missing or invalid terminal keymap action", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              ["<C-c>"] = {
                mode = "t",
              },
            },
          },
        })
      end, 'terminal.keymaps["<C-c>"].action: expected function, got nil')

      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              ["<C-c>"] = {
                mode = "t",
                action = true,
              },
            },
          },
        })
      end, 'terminal.keymaps["<C-c>"].action: expected function, got boolean')
    end)

    it("rejects missing desc for custom terminal keymap actions", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              ["<leader>ot"] = {
                mode = "n",
                action = function() end,
              },
            },
          },
        })
      end, 'codex: terminal.keymaps["<leader>ot"].desc is required for custom actions')
    end)

    it("rejects legacy terminal keymap action-based schema", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              toggle = "<C-c>",
            },
          },
        })
      end, 'codex: terminal.keymaps["toggle"] must be a table with fields: mode, action, desc?')
    end)

    it("rejects removed global keymaps config key", function()
      assert.has_error(function()
        config.apply({
          keymaps = {
            toggle = "<leader>xx",
          },
        })
      end, "codex: unknown config key(s): keymaps")
    end)

    it("rejects removed global keymaps_force config key", function()
      assert.has_error(function()
        config.apply({
          keymaps_force = true,
        })
      end, "codex: unknown config key(s): keymaps_force")
    end)

    it("rejects legacy log_level config key", function()
      assert.has_error(function()
        config.apply({
          log_level = "debug",
        })
      end, "codex: unknown config key(s): log_level")
    end)

    it("rejects env maps with non-string keys", function()
      local cfg = make_valid_config()
      cfg.launch.env = { [1] = "value" }
      assert.has_error(function()
        config.validate(cfg)
      end, "codex: launch.env keys must be strings")
    end)

    it("rejects env maps with non-string values", function()
      local cfg = make_valid_config()
      cfg.launch.env = { CODEX_TEST = true }
      assert.has_error(function()
        config.validate(cfg)
      end, "codex: launch.env.CODEX_TEST must be a string")
    end)
  end)
end)
