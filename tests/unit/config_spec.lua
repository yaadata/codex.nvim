local config = require("codex.config")
local profiles = require("codex.internal.config.profiles")
local keymaps = require("codex.builtin").keymaps

describe("codex.config", function()
  local function resolve_profiles(opts)
    return profiles.resolve_profiles(config.prepare_setup(opts))
  end

  local function resolve_default(opts)
    return resolve_profiles(opts).default.config
  end

  describe("defaults", function()
    it("has expected default values", function()
      -- ========= [A]ssert  =========
      assert.equal("default", config.defaults.profile_identifier)
      assert.equal("default", config.defaults.profile_name)
      assert.is_true(config.defaults.auto_start)
      assert.equal("codex", config.defaults.launch.cmd)
      assert.same({}, config.defaults.launch.env)
      assert.is_nil(config.defaults.launch.cwd)
      assert.equal("auto", config.defaults.terminal.provider)
      assert.is_true(config.defaults.terminal.auto_close)
      assert.equal("vsplit", config.defaults.terminal.provider_opts.native.window)
      assert.equal("right", config.defaults.terminal.provider_opts.native.vsplit.side)
      assert.equal(40, config.defaults.terminal.provider_opts.native.vsplit.size_pct)
      assert.equal("bottom", config.defaults.terminal.provider_opts.native.hsplit.side)
      assert.equal(30, config.defaults.terminal.provider_opts.native.hsplit.size_pct)
      assert.equal(80, config.defaults.terminal.provider_opts.native.float.width_pct)
      assert.equal(80, config.defaults.terminal.provider_opts.native.float.height_pct)
      assert.equal("rounded", config.defaults.terminal.provider_opts.native.float.border)
      assert.is_nil(config.defaults.terminal.provider_opts.native.float.title)
      assert.equal("center", config.defaults.terminal.provider_opts.native.float.title_pos)
      assert.equal(2000, config.defaults.terminal.startup.timeout_ms)
      assert.equal(50, config.defaults.terminal.startup.retry_interval_ms)
      assert.equal(800, config.defaults.terminal.startup.grace_ms)
      assert.same({}, config.defaults.terminal.keymaps)
      assert.equal("warn", config.defaults.log.level)
      assert.is_false(config.defaults.log.verbose)
      assert.same({}, config.defaults.hooks)
    end)
  end)

  describe("split_command", function()
    it("returns plain string executable and empty args without shell splitting", function()
      local exe, args = config.split_command("/path/to/my codex")
      assert.equal("/path/to/my codex", exe)
      assert.same({}, args)
    end)

    it("returns executable and fresh argv copy for list commands", function()
      local exe, args = config.split_command({ "codex", "--model", "o3" })
      assert.equal("codex", exe)
      assert.same({ "--model", "o3" }, args)
      table.insert(args, "--mutated")
      local _, args2 = config.split_command({ "codex", "--model", "o3" })
      assert.same({ "--model", "o3" }, args2)
    end)
  end)

  describe("resolve_profiles", function()
    it("returns default profile from stock defaults when called with nil or empty", function()
      -- ========= [A]ct     =========
      local cfg_nil = resolve_default(nil)
      local cfg_empty = resolve_default({})
      -- ========= [A]ssert  =========
      assert.equal("default", cfg_nil.profile_identifier)
      assert.equal("default", cfg_nil.profile_name)
      assert.equal("codex", cfg_nil.launch.cmd)
      assert.equal("auto", cfg_nil.terminal.provider)
      assert.equal("codex", cfg_empty.launch.cmd)
    end)

    it("merges default overrides and inherits into named profiles", function()
      -- ========= [A]ct     =========
      local resolved = resolve_profiles({
        profiles = {
          default = {
            auto_start = false,
            launch = {
              cmd = "/usr/local/bin/codex",
              cwd = "/default",
              env = { A = "1", B = "2" },
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
                  action = keymaps.teardown,
                },
              },
            },
            keymaps = {
              ["<leader>dd"] = {
                mode = "n",
                action = keymaps.toggle,
              },
            },
          },
          work = {
            launch = {
              cwd = "/work",
              env = { B = "3", C = "4" },
            },
          },
          clean = {
            launch = {
              cmd = { "claude", "--flag" },
              cwd = false,
              env = {},
            },
            terminal = {
              keymaps = {},
            },
          },
        },
      })

      local def_cfg = resolved.default.config
      local work_cfg = resolved.work.config
      local clean_cfg = resolved.clean.config

      -- ========= [A]ssert  =========
      assert.equal("/usr/local/bin/codex", def_cfg.launch.cmd)
      assert.equal("hsplit", def_cfg.terminal.provider_opts.native.window)
      assert.equal("left", def_cfg.terminal.provider_opts.native.vsplit.side)
      assert.equal(40, def_cfg.terminal.provider_opts.native.vsplit.size_pct)
      assert.equal("bottom", def_cfg.terminal.provider_opts.native.hsplit.side)
      assert.equal(50, def_cfg.terminal.provider_opts.native.hsplit.size_pct)
      assert.equal("t", def_cfg.terminal.keymaps["<C-d>"].mode)
      assert.equal("auto", def_cfg.terminal.provider)

      assert.equal("work", work_cfg.profile_identifier)
      assert.equal("work", work_cfg.profile_name)
      assert.is_false(work_cfg.auto_start)
      assert.equal("/usr/local/bin/codex", work_cfg.launch.cmd)
      assert.equal("/work", work_cfg.launch.cwd)
      assert.same({ A = "1", B = "3", C = "4" }, work_cfg.launch.env)
      assert.is_not_nil(work_cfg.terminal.keymaps["<C-d>"])
      assert.same({}, resolved.work.keymaps)

      assert.equal("clean", clean_cfg.profile_identifier)
      assert.equal("clean", clean_cfg.profile_name)
      assert.same({ "claude", "--flag" }, clean_cfg.launch.cmd)
      assert.is_nil(clean_cfg.launch.cwd)
      assert.same({}, clean_cfg.launch.env)
      assert.same({}, clean_cfg.terminal.keymaps)
    end)

    it("resolves optional profile_name without inheriting from default", function()
      local resolved = resolve_profiles({
        profiles = {
          default = {
            profile_name = "Main Agent",
          },
          work = {
            profile_name = "Work Agent",
          },
          scratch = {},
        },
      })

      assert.equal("default", resolved.default.config.profile_identifier)
      assert.equal("Main Agent", resolved.default.config.profile_name)

      assert.equal("work", resolved.work.config.profile_identifier)
      assert.equal("Work Agent", resolved.work.config.profile_name)

      assert.equal("scratch", resolved.scratch.config.profile_identifier)
      assert.equal("scratch", resolved.scratch.config.profile_name)
    end)

    it("rejects invalid profile_name values", function()
      for _, bad in ipairs({ "", "   ", 123, true, {} }) do
        local ok, err = pcall(resolve_profiles, {
          profiles = {
            default = {},
            work = { profile_name = bad },
          },
        })
        assert.is_false(ok)
        assert.matches("profiles%.work%.profile_name must be a non%-empty string", err)
      end
    end)

    it("merges global log and hooks overrides", function()
      local function on_setup() end
      local cfg = resolve_default({
        log = { level = "info", verbose = true },
        hooks = { on_setup = on_setup },
      })
      assert.equal("info", cfg.log.level)
      assert.is_true(cfg.log.verbose)
      assert.equal(on_setup, cfg.hooks.on_setup)
    end)

    it("does not mutate defaults or input tables", function()
      local opts = {
        profiles = {
          default = {
            launch = { cmd = "other", env = { X = "1" } },
          },
          named = {
            launch = { env = { Y = "2" } },
          },
        },
      }
      local snapshot = vim.deepcopy(opts)
      resolve_profiles(opts)
      assert.equal("codex", config.defaults.launch.cmd)
      assert.same(snapshot, opts)
    end)

    it("requires profiles.default when profiles is provided", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          work = { launch = { cwd = "/work" } },
        },
      })
      assert.is_false(ok)
      assert.matches("profiles%.default is required", err)
    end)

    it("rejects empty or non-string profile names", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {},
          [""] = {},
        },
      })
      assert.is_false(ok)
      assert.matches("profile names must be non%-empty strings", err)
    end)

    it("rejects negative default snacks count when named profiles are configured", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            terminal = {
              provider_opts = {
                snacks = { count = -1 },
              },
            },
          },
          work = {},
        },
      })
      assert.is_false(ok)
      assert.matches("snacks%.count cannot be negative", err)
    end)

    it("allows negative default snacks count when no named profiles exist", function()
      local resolved = resolve_profiles({
        profiles = {
          default = {
            terminal = {
              provider_opts = {
                snacks = { count = -1 },
              },
            },
          },
        },
      })
      assert.equal(-1, resolved.default.config.terminal.provider_opts.snacks.count)
    end)
  end)

  describe("validate", function()
    it("accepts valid config", function()
      -- ========= [A]ssert  =========
      assert.is_table(resolve_default())
    end)

    it("rejects invalid provider name", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { terminal = { provider = "invalid" } } },
      })
      assert.is_false(ok)
      assert.matches(
        'invalid terminal.provider "invalid", expected one of: auto, snacks, native',
        err
      )
    end)

    it("rejects non-table shared settings", function()
      for _, key in ipairs({ "log", "hooks" }) do
        local ok, err = pcall(resolve_profiles, { [key] = false })
        assert.is_false(ok)
        assert.matches(key .. ": expected table, got boolean", err)
      end
    end)

    it("rejects invalid log.level", function()
      local ok, err = pcall(resolve_profiles, { log = { level = "trace" } })
      assert.is_false(ok)
      assert.matches('invalid log.level "trace", expected one of: debug, info, warn, error', err)
    end)

    it("rejects non-boolean log.verbose", function()
      local ok, err = pcall(resolve_profiles, { log = { verbose = "yes" } })
      assert.is_false(ok)
      assert.matches("log.verbose: expected boolean, got string", err)
    end)

    it("rejects unknown log keys", function()
      local ok, err =
        pcall(resolve_profiles, { log = { level = "warn", verbose = false, extra = true } })
      assert.is_false(ok)
      assert.matches("unknown log config key%(s%): log.extra", err)
    end)

    it("rejects unknown hook keys", function()
      local ok, err = pcall(resolve_profiles, { hooks = { on_focus = function() end } })
      assert.is_false(ok)
      assert.matches("unknown hook key%(s%): hooks.on_focus", err)
    end)

    it("rejects non-function hook values", function()
      local ok, err = pcall(resolve_profiles, { hooks = { on_setup = true } })
      assert.is_false(ok)
      assert.matches("hooks.on_setup must be a function or nil", err)
    end)

    it("rejects invalid native window type", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { terminal = { provider_opts = { native = { window = "tabs" } } } } },
      })
      assert.is_false(ok)
      assert.matches(
        'invalid terminal.provider_opts.native.window "tabs", expected one of: vsplit, hsplit, float',
        err
      )
    end)

    it("rejects invalid native vsplit.side", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = { terminal = { provider_opts = { native = { vsplit = { side = "top" } } } } },
        },
      })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.vsplit.side must be 'left' or 'right'", err)
    end)

    it("rejects native vsplit.size_pct below 10", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = { terminal = { provider_opts = { native = { vsplit = { size_pct = 5 } } } } },
        },
      })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.vsplit.size_pct must be between 10 and 90", err)
    end)

    it("rejects native hsplit.side", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = { terminal = { provider_opts = { native = { hsplit = { side = "left" } } } } },
        },
      })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.hsplit.side must be 'top' or 'bottom'", err)
    end)

    it("rejects native hsplit.size_pct above 90", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = { terminal = { provider_opts = { native = { hsplit = { size_pct = 95 } } } } },
        },
      })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.hsplit.size_pct must be between 10 and 90", err)
    end)

    it("rejects native float.width_pct below 10", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = { terminal = { provider_opts = { native = { float = { width_pct = 5 } } } } },
        },
      })
      assert.is_false(ok)
      assert.matches(
        "terminal.provider_opts.native.float.width_pct must be between 10 and 100",
        err
      )
    end)

    it("rejects native float.height_pct above 100", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            terminal = { provider_opts = { native = { float = { height_pct = 150 } } } },
          },
        },
      })
      assert.is_false(ok)
      assert.matches(
        "terminal.provider_opts.native.float.height_pct must be between 10 and 100",
        err
      )
    end)

    it("rejects invalid native float.title_pos", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            terminal = { provider_opts = { native = { float = { title_pos = "middle" } } } },
          },
        },
      })
      assert.is_false(ok)
      assert.matches(
        "terminal.provider_opts.native.float.title_pos must be 'left', 'center', or 'right'",
        err
      )
    end)

    it("rejects startup.timeout_ms below 1", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { terminal = { startup = { timeout_ms = 0 } } } },
      })
      assert.is_false(ok)
      assert.matches("terminal.startup.timeout_ms must be >= 1", err)
    end)

    it("rejects startup.retry_interval_ms below 1", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { terminal = { startup = { retry_interval_ms = 0 } } } },
      })
      assert.is_false(ok)
      assert.matches("terminal.startup.retry_interval_ms must be >= 1", err)
    end)

    it("rejects startup.grace_ms below 0", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { terminal = { startup = { grace_ms = -1 } } } },
      })
      assert.is_false(ok)
      assert.matches("terminal.startup.grace_ms must be >= 0", err)
    end)

    it("rejects unknown terminal keys", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { terminal = { startup_timeout_ms = 5000 } } },
      })
      assert.is_false(ok)
      assert.matches("unknown terminal config key%(s%): .*startup_timeout_ms", err)
    end)

    it("reports obsolete launch fields as unknown keys", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { launch = { args = { "--flag" }, auto_start = true } } },
      })
      assert.is_false(ok)
      assert.matches("unknown launch config key%(s%): .*%.args, .*%.auto_start", err)
    end)

    it("merges launch settings without sharing input tables", function()
      local base = { cmd = { "codex", "" }, cwd = "/base", env = { A = "base", B = "2" } }
      local override = { env = { A = "override" } }
      local merged = config.merge_launch(base, override)
      assert.same(
        { cmd = { "codex", "" }, cwd = "/base", env = { A = "override", B = "2" } },
        merged
      )
      merged.cmd[1] = "changed"
      merged.env.A = "changed"
      assert.same({ "codex", "" }, base.cmd)
      assert.same({ A = "base", B = "2" }, base.env)
      assert.same({ env = { A = "override" } }, override)
    end)

    it("rejects invalid launch.cmd forms (empty, sparse, non-string argv)", function()
      for _, bad_cmd in ipairs({
        "",
        "   ",
        {},
        { "" },
        { "codex", 123 },
        { [1] = "codex", [3] = "--flag" },
        { exe = "codex" },
        123,
      }) do
        local ok = pcall(resolve_profiles, {
          profiles = { default = { launch = { cmd = bad_cmd } } },
        })
        assert.is_false(ok)
      end
    end)

    it("rejects non-string/non-false launch.cwd", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = { default = { launch = { cwd = 123 } } },
      })
      assert.is_false(ok)
      assert.matches("cwd must be", err)
    end)

    it("rejects non-table terminal.provider_opts", function()
      local cfg = { terminal = { provider_opts = "bad" } }
      local ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts: expected table", err)
    end)

    it("rejects non-table terminal.provider_opts.native", function()
      local cfg = { terminal = { provider_opts = { native = "bad" } } }
      local ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native: expected table", err)
    end)

    it("rejects non-table terminal.provider_opts.snacks", function()
      local cfg = { terminal = { provider_opts = { snacks = "bad" } } }
      local ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.snacks: expected table", err)
    end)

    it("rejects non-table terminal.keymaps", function()
      local cfg = { terminal = { keymaps = true } }
      local ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("terminal.keymaps: expected table", err)
    end)

    it("rejects bad nested field types", function()
      local cfg = { terminal = { provider_opts = { native = { float = { title = 123 } } } } }
      local ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("terminal.provider_opts.native.float.title", err)
    end)

    it("accepts keymaps with builtin actions and omitted desc", function()
      assert.is_table(resolve_default({
        profiles = {
          default = {
            terminal = {
              keymaps = {
                ["<C-c>"] = {
                  mode = "t",
                  action = keymaps.toggle,
                },
              },
            },
          },
        },
      }))
    end)

    it("accepts keymaps with custom actions when desc is provided", function()
      assert.is_table(resolve_default({
        profiles = {
          default = {
            terminal = {
              keymaps = {
                ["<leader>ot"] = {
                  mode = { "n", "v" },
                  action = function() end,
                  desc = "Codex: custom test action",
                },
              },
            },
          },
        },
      }))
    end)

    it("rejects invalid global profile keymaps", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            keymaps = {
              ["<leader>ot"] = {
                mode = "n",
                action = function() end,
              },
            },
          },
        },
      })
      assert.is_false(ok)
      assert.matches("desc is required for custom actions", err)

      ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            keymaps = {
              ["<leader>ot"] = {
                mode = { [2] = "n" },
                action = keymaps.toggle,
              },
            },
          },
        },
      })
      assert.is_false(ok)
      assert.matches("mode must be a list of strings", err)
    end)

    it("rejects non-string terminal.keymaps keys", function()
      local cfg = { terminal = { keymaps = { { mode = "t", action = keymaps.toggle } } } }
      local ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("terminal.keymaps keys must be non%-empty strings", err)
    end)

    it("rejects terminal keymap bindings that are not tables", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            terminal = {
              keymaps = {
                ["<C-c>"] = true,
              },
            },
          },
        },
      })
      assert.is_false(ok)
      assert.matches("keymaps%b[] must be a table with fields: mode, action, desc%?", err)
    end)

    it("rejects unknown keymap binding keys", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            terminal = {
              keymaps = {
                ["<C-c>"] = {
                  mode = "t",
                  action = keymaps.toggle,
                  foo = true,
                },
              },
            },
          },
        },
      })
      assert.is_false(ok)
      assert.matches("unknown keymap key%(s%): .*%.foo", err)
    end)

    it("rejects missing desc for custom terminal keymap actions", function()
      local ok, err = pcall(resolve_profiles, {
        profiles = {
          default = {
            terminal = {
              keymaps = {
                ["<leader>ot"] = {
                  mode = "n",
                  action = function() end,
                },
              },
            },
          },
        },
      })
      assert.is_false(ok)
      assert.matches("desc is required for custom actions", err)
    end)

    it("rejects env maps with non-string keys or values", function()
      local cfg = { launch = { env = { [1] = "value" } } }
      local ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("launch.env keys must be non%-empty strings", err)

      cfg = { launch = { env = { CODEX_TEST = true } } }
      ok, err = pcall(resolve_default, { profiles = { default = cfg } })
      assert.is_false(ok)
      assert.matches("launch.env.CODEX_TEST must be a string", err)
    end)
  end)
end)
