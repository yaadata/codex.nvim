local config = require("codex.config")
local keymaps = require("codex.keymaps")

describe("codex.config", function()
  local function make_valid_config()
    return vim.deepcopy(config.defaults)
  end

  describe("defaults", function()
    it("has expected default values", function()
      -- ========= [A]ssert  =========
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
      -- ========= [A]ct     =========
      local cfg = config.apply(nil)
      -- ========= [A]ssert  =========
      assert.equals("codex", cfg.launch.cmd)
      assert.equals("auto", cfg.terminal.provider)
    end)

    it("returns defaults when called with empty table", function()
      -- ========= [A]ct     =========
      local cfg = config.apply({})
      -- ========= [A]ssert  =========
      assert.equals("codex", cfg.launch.cmd)
    end)

    it("merges user overrides", function()
      -- ========= [A]ct     =========
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
      -- ========= [A]ssert  =========
      assert.equals("/usr/local/bin/codex", cfg.launch.cmd)
      assert.equals("hsplit", cfg.terminal.provider_opts.native.window)
      assert.equals("left", cfg.terminal.provider_opts.native.vsplit.side)
      assert.equals(40, cfg.terminal.provider_opts.native.vsplit.size_pct)
      assert.equals("bottom", cfg.terminal.provider_opts.native.hsplit.side)
      assert.equals(50, cfg.terminal.provider_opts.native.hsplit.size_pct)
      assert.equals("t", cfg.terminal.keymaps["<C-d>"].mode)
      assert.equals(keymaps.builtins.close, cfg.terminal.keymaps["<C-d>"].action)
      assert.equals("auto", cfg.terminal.provider) -- non-overridden values preserved
    end)

    it("accepts cwd override despite nil default", function()
      -- ========= [A]ct     =========
      local cfg = config.apply({ launch = { cwd = "/tmp/project" } })
      -- ========= [A]ssert  =========
      assert.equals("/tmp/project", cfg.launch.cwd)
    end)

    it("merges log overrides", function()
      -- ========= [A]ct     =========
      local cfg = config.apply({
        log = {
          level = "info",
          verbose = true,
        },
      })
      -- ========= [A]ssert  =========
      assert.equals("info", cfg.log.level)
      assert.is_true(cfg.log.verbose)
    end)

    it("does not mutate defaults", function()
      -- ========= [A]ct     =========
      config.apply({ launch = { cmd = "other" } })
      -- ========= [A]ssert  =========
      assert.equals("codex", config.defaults.launch.cmd)
    end)
  end)

  describe("validate", function()
    it("accepts valid config", function()
      -- ========= [A]ssert  =========
      assert.is_true(config.validate(config.defaults))
    end)

    it("rejects invalid provider name", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { provider = "invalid" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches(
        'invalid terminal.provider "invalid", expected one of: auto, snacks, native',
        err
      )
    end)

    it("rejects invalid log.level", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { log = { level = "trace" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches('invalid log.level "trace", expected one of: debug, info, warn, error', err)
    end)

    it("rejects non-boolean log.verbose", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { log = { verbose = "yes" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("log.verbose: expected boolean, got string", err)
    end)

    it("rejects unknown log keys", function()
      -- ========= [A]ct     =========
      local ok, err =
        pcall(config.apply, { log = { level = "warn", verbose = false, extra = true } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown log config key%(s%): log.extra", err)
    end)

    it("rejects invalid native window type", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { window = "tabs" } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches(
        'invalid terminal.provider_opts.native.window "tabs", expected one of: vsplit, hsplit, float',
        err
      )
    end)

    it("rejects invalid native vsplit.side", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { vsplit = { side = "top" } } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.vsplit.side must be 'left' or 'right'", err)
    end)

    it("rejects native vsplit.size_pct below 10", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { vsplit = { size_pct = 5 } } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.vsplit.size_pct must be between 10 and 90", err)
    end)

    it("rejects native hsplit.side", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { hsplit = { side = "left" } } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.hsplit.side must be 'top' or 'bottom'", err)
    end)

    it("rejects native hsplit.size_pct above 90", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { hsplit = { size_pct = 95 } } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.hsplit.size_pct must be between 10 and 90", err)
    end)

    it("rejects native float.width_pct below 10", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { float = { width_pct = 5 } } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches(
        "terminal.provider_opts.native.float.width_pct must be between 10 and 100",
        err
      )
    end)

    it("rejects native float.height_pct above 100", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { float = { height_pct = 150 } } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches(
        "terminal.provider_opts.native.float.height_pct must be between 10 and 100",
        err
      )
    end)

    it("rejects invalid native float.title_pos", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { provider_opts = { native = { float = { title_pos = "middle" } } } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches(
        "terminal.provider_opts.native.float.title_pos must be 'left', 'center', or 'right'",
        err
      )
    end)

    it("rejects startup.timeout_ms below 1", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { startup = { timeout_ms = 0 } } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.startup.timeout_ms must be >= 1", err)
    end)

    it("rejects startup.retry_interval_ms below 1", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { startup = { retry_interval_ms = 0 } } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.startup.retry_interval_ms must be >= 1", err)
    end)

    it("rejects startup.grace_ms below 0", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { startup = { grace_ms = -1 } } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.startup.grace_ms must be >= 0", err)
    end)

    it("rejects a single unknown terminal key", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { startup_timeout_ms = 5000 } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown terminal config key%(s%): terminal.startup_timeout_ms", err)
    end)

    it("rejects multiple unknown terminal keys", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { startup_timeout_ms = 5000, foo = true } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.foo", err)
      assert.matches("terminal.startup_timeout_ms", err)
    end)

    it("rejects a typo in terminal key names", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { widnow = "vsplit" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown terminal config key%(s%): terminal.widnow", err)
    end)

    it("rejects removed terminal window key", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { terminal = { window = "vsplit" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown terminal config key%(s%): terminal.window", err)
    end)

    it("rejects a typo in terminal.startup key names", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = { startup = { retri_interval_ms = 25 } },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown terminal config key%(s%): terminal.startup.retri_interval_ms", err)
    end)

    it("rejects unknown launch keys", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { launch = { command = "codex" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown launch config key%(s%): launch.command", err)
    end)

    it("rejects legacy top-level launch keys", function()
      local ok, err

      -- ========= [A]ct     =========
      ok, err = pcall(config.apply, { cmd = "codex" })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown config key%(s%): cmd", err)

      -- ========= [A]ct     =========
      ok, err = pcall(config.apply, { args = { "--flag" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown config key%(s%): args", err)

      -- ========= [A]ct     =========
      ok, err = pcall(config.apply, { env = { CODEX_TEST = "1" } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown config key%(s%): env", err)

      -- ========= [A]ct     =========
      ok, err = pcall(config.apply, { auto_start = true })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown config key%(s%): auto_start", err)

      -- ========= [A]ct     =========
      ok, err = pcall(config.apply, { cwd = "/tmp/project" })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown config key%(s%): cwd", err)
    end)

    it("rejects non-string launch.cwd", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, { launch = { cwd = 123 } })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("launch.cwd must be a string or nil", err)
    end)

    it("rejects non-table terminal.provider_opts", function()
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.terminal.provider_opts = "bad"
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts: expected table", err)
    end)

    it("rejects non-table terminal.provider_opts.native", function()
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.terminal.provider_opts.native = "bad"
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native: expected table", err)
    end)

    it("rejects non-table terminal.provider_opts.snacks", function()
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.terminal.provider_opts.snacks = "bad"
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.snacks: expected table", err)
    end)

    it("rejects non-table terminal.keymaps", function()
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.terminal.keymaps = true
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps: expected table", err)
    end)

    it("rejects bad nested field types", function()
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.terminal.provider_opts.native.float.title = 123
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.float.title", err)
    end)

    it("accepts keymaps with builtin actions and omitted desc", function()
      -- ========= [A]ssert  =========
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
      -- ========= [A]ssert  =========
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
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.terminal.keymaps[1] = {
        mode = "t",
        action = keymaps.builtins.toggle,
      }
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps keys must be non%-empty strings", err)
    end)

    it("rejects terminal keymap bindings that are not tables", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = {
          keymaps = {
            ["<C-c>"] = true,
          },
        },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps%b[] must be a table with fields: mode, action, desc%?", err)
    end)

    it("rejects unknown terminal keymap binding keys", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
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
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("unknown terminal keymap key%(s%): terminal.keymaps%b[].foo", err)
    end)

    it("rejects missing terminal keymap mode", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = {
          keymaps = {
            ["<C-c>"] = {
              action = keymaps.builtins.toggle,
            },
          },
        },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps%b[].mode must be a string or list of strings", err)
    end)

    it("rejects invalid terminal keymap mode", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = {
          keymaps = {
            ["<C-c>"] = {
              mode = { "t", 1 },
              action = keymaps.builtins.toggle,
            },
          },
        },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps%b[].mode%b[] must be a string", err)
    end)

    it("rejects invalid terminal keymap action", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = {
          keymaps = {
            ["<C-c>"] = {
              mode = "t",
              action = true,
            },
          },
        },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps%b[].action: expected function, got boolean", err)
    end)

    it("rejects missing terminal keymap action", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = {
          keymaps = {
            ["<C-c>"] = {
              mode = "t",
            },
          },
        },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps%b[].action: expected function, got nil", err)
    end)

    it("rejects missing desc for custom terminal keymap actions", function()
      -- ========= [A]ct     =========
      local ok, err = pcall(config.apply, {
        terminal = {
          keymaps = {
            ["<leader>ot"] = {
              mode = "n",
              action = function() end,
            },
          },
        },
      })
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("terminal.keymaps%b[].desc is required for custom actions", err)
    end)

    it("rejects env maps with non-string keys", function()
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.launch.env = { [1] = "value" }
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("codex: launch.env keys must be strings", err)
    end)

    it("rejects env maps with non-string values", function()
      -- ========= [A]rrange =========
      local cfg = make_valid_config()
      cfg.launch.env = { CODEX_TEST = true }
      -- ========= [A]ct     =========
      local ok, err = pcall(config.validate, cfg)
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("codex: launch.env.CODEX_TEST must be a string", err)
    end)
  end)
end)
