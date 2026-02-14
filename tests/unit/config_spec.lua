local config = require("codex.config")

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
      assert.equals("codex", config.defaults.cmd)
      assert.equals("auto", config.defaults.terminal.provider)
      assert.equals("vsplit", config.defaults.terminal.window)
      assert.equals("right", config.defaults.terminal.vsplit.side)
      assert.equals(40, config.defaults.terminal.vsplit.size_pct)
      assert.equals("bottom", config.defaults.terminal.hsplit.side)
      assert.equals(30, config.defaults.terminal.hsplit.size_pct)
      assert.equals(80, config.defaults.terminal.float.width_pct)
      assert.equals(80, config.defaults.terminal.float.height_pct)
      assert.equals("rounded", config.defaults.terminal.float.border)
      assert.equals(" Codex ", config.defaults.terminal.float.title)
      assert.equals("center", config.defaults.terminal.float.title_pos)
      assert.equals(2000, config.defaults.terminal.startup_timeout_ms)
      assert.equals(50, config.defaults.terminal.startup_retry_interval_ms)
      assert.equals(400, config.defaults.terminal.startup_grace_ms)
      assert.equals("<C-c>", config.defaults.terminal.keymaps.toggle)
      assert.is_false(config.defaults.terminal.keymaps.close)
      assert.equals("<C-h>", config.defaults.terminal.keymaps.nav.left)
      assert.equals("<C-j>", config.defaults.terminal.keymaps.nav.down)
      assert.equals("<C-k>", config.defaults.terminal.keymaps.nav.up)
      assert.equals("<C-l>", config.defaults.terminal.keymaps.nav.right)
      assert.is_false(config.defaults.auto_start)
      assert.equals("warn", config.defaults.log_level)
      assert.equals("<leader>ot", config.defaults.keymaps.toggle)
      assert.equals("<leader>ox", config.defaults.keymaps.close)
      assert.equals("<leader>os", config.defaults.keymaps.send)
      assert.equals("<leader>oR", config.defaults.keymaps.review)
      assert.is_false(config.defaults.keymaps_force)
    end)
  end)

  describe("apply", function()
    it("returns defaults when called with nil", function()
      local cfg = config.apply(nil)
      assert.equals("codex", cfg.cmd)
      assert.equals("auto", cfg.terminal.provider)
    end)

    it("returns defaults when called with empty table", function()
      local cfg = config.apply({})
      assert.equals("codex", cfg.cmd)
    end)

    it("merges user overrides", function()
      local cfg = config.apply({
        cmd = "/usr/local/bin/codex",
        terminal = {
          window = "hsplit",
          vsplit = { side = "left" },
          hsplit = { size_pct = 50 },
          keymaps = { close = "<C-d>" },
        },
        keymaps = {
          toggle = "<leader>xx",
          status = false,
        },
      })
      assert.equals("/usr/local/bin/codex", cfg.cmd)
      assert.equals("hsplit", cfg.terminal.window)
      assert.equals("left", cfg.terminal.vsplit.side)
      assert.equals(40, cfg.terminal.vsplit.size_pct)
      assert.equals("bottom", cfg.terminal.hsplit.side)
      assert.equals(50, cfg.terminal.hsplit.size_pct)
      assert.equals("<C-c>", cfg.terminal.keymaps.toggle)
      assert.equals("<C-d>", cfg.terminal.keymaps.close)
      assert.equals("<C-h>", cfg.terminal.keymaps.nav.left)
      assert.equals("<C-j>", cfg.terminal.keymaps.nav.down)
      assert.equals("<C-k>", cfg.terminal.keymaps.nav.up)
      assert.equals("<C-l>", cfg.terminal.keymaps.nav.right)
      assert.equals("<leader>xx", cfg.keymaps.toggle)
      assert.is_false(cfg.keymaps.status)
      assert.equals("<leader>ox", cfg.keymaps.close)
      assert.equals("<leader>os", cfg.keymaps.send)
      -- non-overridden values preserved
      assert.equals("auto", cfg.terminal.provider)
      assert.is_false(cfg.keymaps_force)
    end)

    it("accepts disabling all default keymaps", function()
      local cfg = config.apply({ keymaps = false })
      assert.is_false(cfg.keymaps)
    end)

    it("does not mutate defaults", function()
      config.apply({ cmd = "other" })
      assert.equals("codex", config.defaults.cmd)
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

    it("rejects invalid window type", function()
      assert.has_error(function()
        config.apply({ terminal = { window = "tabs" } })
      end, 'codex: invalid terminal.window "tabs", expected one of: vsplit, hsplit, float')
    end)

    it("rejects invalid vsplit.side", function()
      assert.has_error(function()
        config.apply({ terminal = { vsplit = { side = "top" } } })
      end, "codex: terminal.vsplit.side must be 'left' or 'right'")
    end)

    it("rejects vsplit.size_pct below 10", function()
      assert.has_error(function()
        config.apply({ terminal = { vsplit = { size_pct = 5 } } })
      end, "codex: terminal.vsplit.size_pct must be between 10 and 90")
    end)

    it("rejects hsplit.side", function()
      assert.has_error(function()
        config.apply({ terminal = { hsplit = { side = "left" } } })
      end, "codex: terminal.hsplit.side must be 'top' or 'bottom'")
    end)

    it("rejects hsplit.size_pct above 90", function()
      assert.has_error(function()
        config.apply({ terminal = { hsplit = { size_pct = 95 } } })
      end, "codex: terminal.hsplit.size_pct must be between 10 and 90")
    end)

    it("rejects float.width_pct below 10", function()
      assert.has_error(function()
        config.apply({ terminal = { float = { width_pct = 5 } } })
      end, "codex: terminal.float.width_pct must be between 10 and 100")
    end)

    it("rejects float.height_pct above 100", function()
      assert.has_error(function()
        config.apply({ terminal = { float = { height_pct = 150 } } })
      end, "codex: terminal.float.height_pct must be between 10 and 100")
    end)

    it("rejects invalid float.title_pos", function()
      assert.has_error(function()
        config.apply({ terminal = { float = { title_pos = "middle" } } })
      end, "codex: terminal.float.title_pos must be 'left', 'center', or 'right'")
    end)

    it("rejects startup_timeout_ms below 1", function()
      assert.has_error(function()
        config.apply({ terminal = { startup_timeout_ms = 0 } })
      end, "codex: terminal.startup_timeout_ms must be >= 1")
    end)

    it("rejects startup_retry_interval_ms below 1", function()
      assert.has_error(function()
        config.apply({ terminal = { startup_retry_interval_ms = 0 } })
      end, "codex: terminal.startup_retry_interval_ms must be >= 1")
    end)

    it("rejects startup_grace_ms below 0", function()
      assert.has_error(function()
        config.apply({ terminal = { startup_grace_ms = -1 } })
      end, "codex: terminal.startup_grace_ms must be >= 0")
    end)

    it("rejects non-table terminal.vsplit", function()
      local cfg = make_valid_config()
      cfg.terminal.vsplit = "bad"
      assert_error_contains(function()
        config.validate(cfg)
      end, "vsplit: expected table")
    end)

    it("rejects non-table terminal.hsplit", function()
      local cfg = make_valid_config()
      cfg.terminal.hsplit = "bad"
      assert_error_contains(function()
        config.validate(cfg)
      end, "hsplit: expected table")
    end)

    it("rejects non-table terminal.float", function()
      local cfg = make_valid_config()
      cfg.terminal.float = "bad"
      assert_error_contains(function()
        config.validate(cfg)
      end, "float: expected table")
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
      cfg.terminal.float.title = 123
      assert_error_contains(function()
        config.validate(cfg)
      end, "terminal.float.title")
    end)

    it("accepts keymaps = false", function()
      local cfg = make_valid_config()
      cfg.keymaps = false
      assert.is_true(config.validate(cfg))
    end)

    it("rejects unknown terminal keymap actions", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              hide = "<C-x>",
            },
          },
        })
      end, 'codex: invalid terminal.keymaps action "hide", expected one of: toggle, close, nav')
    end)

    it("rejects unknown terminal nav keymap actions", function()
      assert.has_error(
        function()
          config.apply({
            terminal = {
              keymaps = {
                nav = {
                  north = "<C-k>",
                },
              },
            },
          })
        end,
        'codex: invalid terminal.keymaps.nav action "north", expected one of: left, down, up, right'
      )
    end)

    it("rejects terminal nav keymap values that are not string|false", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              nav = {
                left = 42,
              },
            },
          },
        })
      end, "codex: terminal.keymaps.nav.left must be a string or false")
    end)

    it("rejects terminal keymap values that are not string|false", function()
      assert.has_error(function()
        config.apply({
          terminal = {
            keymaps = {
              toggle = 42,
            },
          },
        })
      end, "codex: terminal.keymaps.toggle must be a string or false")
    end)

    it("rejects unknown keymap actions", function()
      assert.has_error(
        function()
          config.apply({
            keymaps = {
              launch = "<leader>ol",
            },
          })
        end,
        'codex: invalid keymaps action "launch", expected one of: toggle, open, focus, close, send, add, resume, model, status, permissions, compact, review, diff'
      )
    end)

    it("rejects keymap values that are not string|false", function()
      assert.has_error(function()
        config.apply({
          keymaps = {
            toggle = 42,
          },
        })
      end, "codex: keymaps.toggle must be a string or false")
    end)

    it("rejects non-table keymaps when not false", function()
      local cfg = make_valid_config()
      cfg.keymaps = true
      assert_error_contains(function()
        config.validate(cfg)
      end, "keymaps: expected table")
    end)

    it("rejects non-boolean keymaps_force", function()
      local cfg = make_valid_config()
      cfg.keymaps_force = "yes"
      assert_error_contains(function()
        config.validate(cfg)
      end, "keymaps_force: expected boolean")
    end)

    it("rejects env maps with non-string keys", function()
      local cfg = make_valid_config()
      cfg.env = { [1] = "value" }
      assert.has_error(function()
        config.validate(cfg)
      end, "codex: env keys must be strings")
    end)

    it("rejects env maps with non-string values", function()
      local cfg = make_valid_config()
      cfg.env = { CODEX_TEST = true }
      assert.has_error(function()
        config.validate(cfg)
      end, "codex: env.CODEX_TEST must be a string")
    end)
  end)
end)
