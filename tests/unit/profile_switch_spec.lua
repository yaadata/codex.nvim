local helpers = require("tests.unit.helpers.init_spec_helpers")
local builtin = require("codex.builtin")
local harness = require("codex.enums.harness")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init runtime launch profiles", function()
  local original_defer_fn

  before_each(function()
    original_defer_fn = vim.defer_fn
    package.loaded["codex"] = nil
  end)

  after_each(function()
    vim.defer_fn = original_defer_fn
  end)

  local function run_all_scheduled(fake_vim)
    for _, cb in ipairs(fake_vim._scheduled) do
      cb()
    end
  end

  describe("setup profile resolution", function()
    it("creates default profile from stock defaults when profiles is omitted", function()
      local env = setup_with_deps({
        profiles = nil,
        _provider = nil,
      })
      -- Re-setup with truly omitted profiles
      package.loaded["codex"] = nil
      local codex = require("codex")
      codex.setup({
        _deps = {
          providers = env.providers,
          session_store = env.store,
          logger = env.logger,
          formatter = env.formatter,
          selection = env.selection,
          vim = env.fake_vim,
        },
      })

      local cfg = codex.get_profile()
      assert.equal("default", cfg.profile_identifier)
      assert.equal("default", cfg.profile_name)
      assert.is_true(cfg.auto_start)
      assert.equal("codex", cfg.launch.cmd)
      assert.is_nil(cfg.launch.cwd)
      assert.same({}, cfg.launch.env)
    end)

    it("rejects explicit profiles missing required default", function()
      local codex = require("codex")
      local ok, err = pcall(codex.setup, {
        profiles = {
          work = { launch = { cwd = "/work" } },
        },
      })
      assert.is_false(ok)
      assert.matches("profiles%.default is required", err)
    end)

    it("reports obsolete top-level options as unknown keys", function()
      local codex = require("codex")
      for _, bad in ipairs({
        { launch = { cmd = "codex" } },
        { terminal = { provider = "native" } },
        { cmd = "codex" },
        { args = { "--flag" } },
        { env = { A = "1" } },
        { auto_start = false },
        { cwd = "/tmp" },
      }) do
        local ok, err = pcall(codex.setup, bad)
        assert.is_false(ok)
        assert.matches("unknown config key%(s%): " .. next(bad), err)
      end
    end)

    it("supports arbitrary profile names, inheritance, and clearing cwd/env", function()
      local env = setup_with_deps({
        profiles = {
          default = {
            auto_start = false,
            launch = {
              cmd = { "codex", "--model", "base" },
              cwd = "/base",
              env = { BASE = "1", OVER = "base" },
            },
            terminal = {
              provider_opts = { native = { window = "hsplit" } },
              keymaps = {
                ["<C-q>"] = { mode = "t", action = builtin.keymaps.teardown },
              },
            },
          },
          ["team/alpha-1"] = {
            launch = {
              cwd = "/alpha",
              env = { OVER = "alpha", EXTRA = "2" },
            },
          },
          ["plain:clean"] = {
            launch = {
              cmd = "claude",
              cwd = false,
              env = {},
            },
            terminal = {
              keymaps = {},
            },
          },
        },
      })

      assert.equal("default", env.codex.get_profile().profile_identifier)

      local ok1, err1 = env.codex.set_profile("team/alpha-1")
      assert.is_true(ok1)
      assert.is_nil(err1)
      local cfg1 = env.codex.get_profile()
      assert.equal("team/alpha-1", cfg1.profile_identifier)
      assert.is_false(cfg1.auto_start)
      assert.same({ "codex", "--model", "base" }, cfg1.launch.cmd)
      assert.equal("/alpha", cfg1.launch.cwd)
      assert.same({ BASE = "1", CODEX_TEST = "1", OVER = "alpha", EXTRA = "2" }, cfg1.launch.env)
      assert.equal("hsplit", cfg1.terminal.provider_opts.native.window)
      assert.is_not_nil(cfg1.terminal.keymaps["<C-q>"])

      local ok2, err2 = env.codex.set_profile("plain:clean")
      assert.is_true(ok2)
      assert.is_nil(err2)
      local cfg2 = env.codex.get_profile()
      assert.equal("claude", cfg2.launch.cmd)
      assert.is_nil(cfg2.launch.cwd)
      assert.same({}, cfg2.launch.env)
      assert.same({}, cfg2.terminal.keymaps)
    end)
  end)

  describe("set_profile overrides and error isolation", function()
    it("resets launch overrides on reselection and rejects unknown/invalid switches", function()
      local env = setup_with_deps({
        profiles = {
          default = {
            auto_start = false,
            launch = { cmd = "codex", cwd = "/default", env = { A = "1" } },
          },
          work = {
            launch = { cmd = { "codex", "--profile", "work" }, cwd = "/work", env = { B = "2" } },
          },
        },
      })

      local ok, err = env.codex.set_profile("work", {
        cmd = "opencode",
        cwd = false,
        env = {},
      })
      assert.is_true(ok)
      assert.is_nil(err)
      local cfg = env.codex.get_profile()
      assert.equal("opencode", cfg.launch.cmd)
      assert.is_nil(cfg.launch.cwd)
      assert.same({}, cfg.launch.env)

      -- Invalid/unknown profile leaves selected profile and config intact
      local ok_bad, err_bad = env.codex.set_profile("missing")
      assert.is_false(ok_bad)
      assert.matches("unknown profile", err_bad)
      assert.equal("work", env.codex.get_profile().profile_identifier)
      assert.equal("opencode", env.codex.get_profile().launch.cmd)

      local ok_invalid, err_invalid = env.codex.set_profile("default", { cmd = "" })
      assert.is_false(ok_invalid)
      assert.is_string(err_invalid)
      assert.equal("work", env.codex.get_profile().profile_identifier)
      assert.equal("opencode", env.codex.get_profile().launch.cmd)

      -- Reselecting work without overrides restores its resolved base
      local ok_reselect = env.codex.set_profile("work")
      assert.is_true(ok_reselect)
      local reset_cfg = env.codex.get_profile()
      assert.same({ "codex", "--profile", "work" }, reset_cfg.launch.cmd)
      assert.equal("/work", reset_cfg.launch.cwd)
      assert.same({ A = "1", B = "2", CODEX_TEST = "1" }, reset_cfg.launch.env)
    end)

    it(
      "runs scheduled auto_start only when profile stays selected and has no live session",
      function()
        local env = setup_with_deps({
          profiles = {
            default = { auto_start = true },
            work = { launch = { cwd = "/work" } },
            manual = { auto_start = false },
          },
        })

        -- Switch before initial scheduled auto_start runs -> stale default start ignored
        assert.equal(1, #env.fake_vim._scheduled)
        local ok = env.codex.set_profile("work")
        assert.is_true(ok)
        assert.equal(2, #env.fake_vim._scheduled)

        run_all_scheduled(env.fake_vim)
        assert.equal(1, #env.provider.open_calls)
        assert.equal("/work", env.provider.open_calls[1].config.launch.cwd)
        assert.is_false(env.provider.open_calls[1].focus)
        assert.is_nil(env.store.get_active("default"))
        assert.is_not_nil(env.store.get_active("work"))

        -- Switching back to work while work is already running does not open again
        env.fake_vim._scheduled = {}
        assert.is_true(env.codex.set_profile("work"))
        run_all_scheduled(env.fake_vim)
        assert.equal(1, #env.provider.open_calls)
        env.fake_vim._scheduled = {}
        assert.is_true(env.codex.set_profile("manual"))
        assert.equal(0, #env.fake_vim._scheduled)
      end
    )
  end)

  describe("session isolation, exit, teardown, and deactivate", function()
    it("teardown_all is safe before setup", function()
      local codex = require("codex")
      codex.session.teardown_all()
      assert.is_nil(codex.get_profile())
    end)

    it(
      "teardown_all closes tracked sessions and cancels pending auto-start without deactivating",
      function()
        local env = setup_with_deps({
          profiles = { default = { auto_start = false }, work = { auto_start = true } },
        })
        env.codex.session.open(false)
        assert.is_true(env.codex.set_profile("work"))
        assert.equal(1, #env.fake_vim._scheduled)
        env.codex.session.open(false)

        env.codex.session.teardown_all()
        env.codex.session.teardown_all()
        run_all_scheduled(env.fake_vim)
        assert.equal(2, #env.provider.close_calls)
        assert.equal(2, #env.provider.open_calls)
        assert.is_nil(env.store.get_active("default"))
        assert.is_nil(env.store.get_active("work"))
        assert.equal("work", env.codex.get_profile().profile_identifier)
        env.codex.session.open(false)
        assert.is_not_nil(env.store.get_active("work"))
      end
    )

    it("isolates A -> B -> A handles even with identical command and cwd", function()
      local env = setup_with_deps({
        profiles = {
          default = { auto_start = false, launch = { cmd = "codex", cwd = "/same" } },
          work = { auto_start = false, launch = { cmd = "codex", cwd = "/same" } },
        },
      })

      env.codex.session.open(false)
      local default_session = env.store.get_active("default")
      assert.is_not_nil(default_session)

      assert.is_true(env.codex.set_profile("work"))
      assert.is_false(env.codex.session.is_running())
      env.codex.session.open(false)
      local work_session = env.store.get_active("work")
      assert.is_not_nil(work_session)
      assert.is_not.equal(default_session.id, work_session.id)
      assert.is_not.equal(default_session.handle, work_session.handle)

      assert.is_true(env.codex.set_profile("default"))
      assert.is_true(env.codex.session.is_running())
      env.codex.session.open(true)
      assert.equal(2, #env.provider.open_calls)
      assert.equal(1, #env.provider.focus_calls)
      assert.equal(default_session.handle, env.provider.focus_calls[1])
    end)

    it(
      "handles inactive session exit with its own config, profile_identifier, and profile_name",
      function()
        local close_events = {}
        local env = setup_with_deps({
          profiles = {
            default = { auto_start = false, launch = { cmd = "codex", cwd = "/default" } },
            work = {
              profile_name = "Work Agent",
              auto_start = false,
              launch = { cmd = "claude", cwd = "/work" },
            },
          },
          hooks = {
            on_terminal_close = function(ctx)
              table.insert(close_events, ctx)
            end,
          },
        })

        env.codex.session.open(false)
        assert.is_true(env.codex.set_profile("work"))
        env.codex.session.open(false)
        assert.is_true(env.codex.set_profile("default"))

        -- Trigger work (inactive) process exit
        env.provider.on_exit_callbacks[2]()

        assert.equal(1, #close_events)
        assert.equal("work", close_events[1].profile_identifier)
        assert.equal("Work Agent", close_events[1].profile_name)
        assert.equal("claude", close_events[1].cmd)
        assert.equal("/work", close_events[1].cwd)
        assert.equal("work", close_events[1].config.profile_identifier)
        assert.equal("Work Agent", close_events[1].config.profile_name)
        assert.is_nil(env.store.get_active("work"))
        assert.is_not_nil(env.store.get_active("default"))
        assert.equal("default", env.codex.get_profile().profile_identifier)
      end
    )

    it("teardown closes only selected profile while deactivate closes all profiles", function()
      local close_events = {}
      local env = setup_with_deps({
        profiles = {
          default = { auto_start = false, launch = { cwd = "/default" } },
          work = { auto_start = false, launch = { cwd = "/work" } },
        },
        hooks = {
          on_terminal_close = function(ctx)
            table.insert(close_events, ctx)
          end,
        },
      })

      env.codex.session.open(false)
      local h1 = env.store.get_active("default").handle
      assert.is_true(env.codex.set_profile("work"))
      env.codex.session.open(false)
      local h2 = env.store.get_active("work").handle

      -- Teardown while work is selected closes only work
      env.codex.session.teardown()
      assert.equal(1, #env.provider.close_calls)
      assert.equal(h2, env.provider.close_calls[1])
      assert.is_nil(env.store.get_active("work"))
      assert.is_not_nil(env.store.get_active("default"))
      assert.equal(1, #close_events)
      assert.equal("work", close_events[1].profile_identifier)
      assert.equal("work", close_events[1].profile_name)

      -- Reopen work, then deactivate closes both without switching selection
      env.codex.session.open(false)
      local h3 = env.store.get_active("work").handle
      env.codex.deactivate()

      assert.equal(3, #env.provider.close_calls)
      local closed_handles = {
        [env.provider.close_calls[2]] = true,
        [env.provider.close_calls[3]] = true,
      }
      assert.is_true(closed_handles[h1])
      assert.is_true(closed_handles[h3])
      assert.same({}, env.store.list())
      assert.is_nil(env.codex.get_profile())
    end)

    it("ignores inactive profile terminal buffers when recording non-Codex focus", function()
      local env = setup_with_deps({
        profiles = {
          default = { auto_start = false },
          work = { auto_start = false },
        },
      })
      env.fake_vim._set_window_buf(1, 11)
      env.fake_vim._set_current_win(1)
      env.fake_vim._fire_autocmd("BufEnter")
      env.provider.open_fn = function(_, handle)
        local n = #env.provider.open_calls
        handle.winid = 10 + n
        handle.bufnr = 100 + n
        env.fake_vim._set_window_buf(handle.winid, handle.bufnr)
      end
      env.provider.focus_fn = function(handle)
        env.fake_vim._set_current_win(handle.winid)
        return true
      end

      -- Open default (win 11, buf 101)
      env.codex.session.open(false)
      -- Switch to work and open work (win 12, buf 102)
      assert.is_true(env.codex.set_profile("work"))
      env.codex.session.open(false)

      -- Enter default's terminal window (win 11, buf 101) while work is selected
      env.fake_vim._set_current_win(11)
      -- Focus work and then unfocus: should return to editor win 1 / buf 11, NOT default's terminal
      env.codex.session.focus()
      local ok, err = env.codex.session.unfocus()
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equal(1, env.fake_vim._get_current_win())
      assert.equal(11, env.fake_vim._get_current_buf())
    end)
  end)

  describe("queued payload and delayed Enter isolation", function()
    it("drops queued sends on profile switch and preserves prompt builder draft", function()
      local env = setup_with_deps({
        profiles = {
          default = {
            auto_start = false,
            terminal = { startup = { timeout_ms = 500, retry_interval_ms = 50 } },
          },
          work = {
            auto_start = false,
            terminal = { startup = { timeout_ms = 500, retry_interval_ms = 25 } },
          },
        },
      })
      env.provider.is_alive_fn = function()
        return false
      end

      env.codex.prompt_builder.add("queued message")
      local ok = env.codex.prompt_builder.send()
      assert.is_true(ok)
      assert.equal(0, #env.provider.send_calls)

      -- Unsent draft added before switch must remain intact
      env.codex.prompt_builder.add("still in builder")

      assert.is_true(env.codex.set_profile("work"))
      assert.same({ "still in builder" }, env.codex.prompt_builder.peak())

      -- Even after switching back A -> B -> A and marking alive, old scheduled retries are stale
      assert.is_true(env.codex.set_profile("default"))
      env.provider.is_alive_fn = function()
        return true
      end
      run_deferred(env.fake_vim, 5)
      assert.equal(0, #env.provider.send_calls)
    end)

    it("guards delayed Enter against A -> B -> A profile switch and session replacement", function()
      local env = setup_with_deps({
        profiles = {
          default = { auto_start = false },
          work = { auto_start = false },
        },
      })
      env.codex.session.open(false)

      -- Case 1: A -> B -> A invalidates scheduled delayed Enter
      env.codex.prompt_builder.add("hello")
      assert.is_true(env.codex.prompt_builder.submit())
      assert.equal(1, #env.provider.send_calls)
      assert.equal(1, #env.fake_vim._deferred)

      assert.is_true(env.codex.set_profile("work"))
      assert.is_true(env.codex.set_profile("default"))
      run_deferred(env.fake_vim, 2)
      assert.equal(0, #env.fake_vim._feedkeys_calls)

      -- Case 2: Replacing the session on the same profile invalidates scheduled delayed Enter
      env.codex.prompt_builder.add("hello2")
      assert.is_true(env.codex.prompt_builder.submit())
      assert.equal(2, #env.provider.send_calls)
      assert.equal(1, #env.fake_vim._deferred)

      env.codex.session.teardown()
      env.codex.session.open(false)
      run_deferred(env.fake_vim, 2)
      assert.equal(0, #env.fake_vim._feedkeys_calls)
    end)
  end)

  it("drops delayed Enter when a focus callback switches profiles", function()
    local env = setup_with_deps({ profiles = { default = {}, work = {} } })
    env.codex.session.open(false)
    env.codex.prompt_builder.add("hello")
    assert.is_true(env.codex.prompt_builder.submit())
    assert.equal(1, #env.provider.send_calls)

    env.provider.focus_fn = function()
      assert.is_true(env.codex.set_profile("work"))
      env.codex.session.open(false)
      return true
    end
    run_deferred(env.fake_vim, 5)
    assert.equal("work", env.codex.get_profile().profile_identifier)
    assert.equal(0, #env.fake_vim._feedkeys_calls)
    assert.equal(1, #env.provider.send_calls)
  end)

  describe("resume with list commands and path basenames", function()
    it("detects harness from executable basename of list command and replaces argv", function()
      local env = setup_with_deps({
        profiles = {
          default = {
            auto_start = false,
            launch = { cmd = { "/usr/local/bin/claude", "--dangerously-skip-permissions" } },
          },
          opencode = {
            auto_start = false,
            launch = { cmd = { "/opt/tools/opencode", "--model", "fast" } },
          },
          unknown = {
            auto_start = false,
            launch = { cmd = { "/usr/bin/custom-agent", "--foo" } },
          },
        },
      })

      -- List command with path basename -> claude --continue (replaces configured argv)
      local err1 = builtin.resume({ last = true })
      assert.is_nil(err1)
      assert.equal(1, #env.provider.open_calls)
      assert.equal("/usr/local/bin/claude", env.provider.open_calls[1].cmd)
      assert.same({ "--continue" }, env.provider.open_calls[1].args)

      -- Explicit harness overrides inferred executable
      env.codex.session.teardown()
      local err2 = builtin.resume({ harness = harness.PI, last = true })
      assert.is_nil(err2)
      assert.same({ "--continue" }, env.provider.open_calls[2].args)

      -- Non-last without explicit opts.harness uses slash-command path with configured argv
      vim.defer_fn = env.fake_vim.defer_fn
      env.provider.get_bufnr_fn = function()
        return 77
      end
      env.fake_vim._set_buf_lines(77, { "> " })
      assert.is_true(env.codex.set_profile("opencode"))
      local err_slash = builtin.resume({ last = false })
      run_deferred(env.fake_vim, 3)
      assert.is_nil(err_slash)
      assert.equal(3, #env.provider.open_calls)
      assert.equal("/opt/tools/opencode", env.provider.open_calls[3].cmd)
      assert.same({ "--model", "fast" }, env.provider.open_calls[3].args)
      assert.equal(1, #env.provider.send_calls)
      assert.equal("\27[200~/resume\27[201~", env.provider.send_calls[1].text)

      -- Unknown basename falls back to Codex resume args
      assert.is_true(env.codex.set_profile("unknown"))
      local err3 = builtin.resume({ last = true })
      assert.is_nil(err3)
      assert.equal(4, #env.provider.open_calls)
      assert.equal("/usr/bin/custom-agent", env.provider.open_calls[4].cmd)
      assert.same({ "resume", "--last" }, env.provider.open_calls[4].args)

      -- Live session uses /resume slash command instead of spawning new process
      local err4 = builtin.resume({ last = true })
      run_deferred(env.fake_vim, 3)
      assert.is_nil(err4)
      assert.equal(4, #env.provider.open_calls)
      assert.equal(2, #env.provider.send_calls)
      assert.equal("\27[200~/resume\27[201~", env.provider.send_calls[2].text)
    end)
  end)
end)
