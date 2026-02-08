local config = require("codex.config")

describe("codex.config", function()
  describe("defaults", function()
    it("has expected default values", function()
      assert.equals("codex", config.defaults.cmd)
      assert.equals("auto", config.defaults.terminal.provider)
      assert.equals("right", config.defaults.terminal.split_side)
      assert.equals(40, config.defaults.terminal.split_width_pct)
      assert.is_false(config.defaults.auto_start)
      assert.equals("warn", config.defaults.log_level)
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
        terminal = { split_side = "left", split_width_pct = 50 },
      })
      assert.equals("/usr/local/bin/codex", cfg.cmd)
      assert.equals("left", cfg.terminal.split_side)
      assert.equals(50, cfg.terminal.split_width_pct)
      -- non-overridden values preserved
      assert.equals("auto", cfg.terminal.provider)
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
      assert.has_error(
        function()
          config.apply({ terminal = { provider = "invalid" } })
        end,
        'codex: invalid terminal.provider "invalid", expected one of: auto, snacks, native, external, none'
      )
    end)

    it("rejects split_width_pct below 10", function()
      assert.has_error(function()
        config.apply({ terminal = { split_width_pct = 5 } })
      end, "codex: terminal.split_width_pct must be between 10 and 90")
    end)

    it("rejects split_width_pct above 90", function()
      assert.has_error(function()
        config.apply({ terminal = { split_width_pct = 95 } })
      end, "codex: terminal.split_width_pct must be between 10 and 90")
    end)

    it("rejects invalid split_side", function()
      assert.has_error(function()
        config.apply({ terminal = { split_side = "top" } })
      end, "codex: terminal.split_side must be 'left' or 'right'")
    end)
  end)
end)
