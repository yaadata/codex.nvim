local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init public api lifecycle", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  local function send_prompt(env, text)
    env.codex.prompt_builder.add(text)
    env.codex.prompt_builder.send()
  end

  local function configure_focusable_terminal(env, opts)
    opts = opts or {}
    local source_win = opts.source_win or 1
    local source_buf = opts.source_buf or 11
    local term_win = opts.term_win or 2
    local term_buf = opts.term_buf or 200

    env.fake_vim._set_window_buf(source_win, source_buf)
    env.fake_vim._set_current_win(source_win)

    env.provider.open_fn = function(call, handle)
      handle.winid = term_win
      handle.bufnr = term_buf
      env.fake_vim._set_window_buf(term_win, term_buf)
      if call.focus then
        env.fake_vim._set_current_win(term_win)
      end
    end
    env.provider.focus_fn = function(handle)
      env.fake_vim._set_current_win(handle.winid)
      return true
    end
  end

  it("requires setup before open", function()
    -- ========= [A]rrange =========
    local codex = require("codex")

    -- ========= [A]ct     =========
    -- ========= [A]ssert  =========
    assert.has_error(function()
      codex.session.open()
    end, "codex.nvim: call require('codex').setup() first")
  end)

  it("requires setup before input.clear", function()
    -- ========= [A]rrange =========
    local codex = require("codex")
    -- ========= [A]ct     =========
    local ok, err = pcall(codex.input.clear)
    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.matches("codex%.nvim: call require%('codex'%).setup%(%)" .. " first", err)
  end)

  it("requires setup before logs.get", function()
    -- ========= [A]rrange =========
    local codex = require("codex")

    -- ========= [A]ct     =========
    local ok, err = pcall(codex.logs.get)

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.matches("codex%.nvim: call require%('codex'%).setup%(%)" .. " first", err)
  end)

  it("requires setup before logs.clear", function()
    -- ========= [A]rrange =========
    local codex = require("codex")

    -- ========= [A]ct     =========
    local ok, err = pcall(codex.logs.clear)

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.matches("codex%.nvim: call require%('codex'%).setup%(%)" .. " first", err)
  end)

  it("setup uses injected dependencies and strips _deps from config", function()
    -- ========= [A]ct     =========
    local env = setup_with_deps({ log = { level = "info", verbose = true } })

    -- ========= [A]ssert  =========
    assert.equal(1, env.commands.register_calls)
    assert.same({ "commands" }, env.call_order)
    assert.equal("info", env.logger.set_levels[1])
    assert.is_true(env.logger.set_verboses[1])
    assert.equal(2, #env.fake_vim._autocmds)
    assert.same({ "WinEnter", "BufEnter" }, env.fake_vim._autocmds[1].event)
    assert.same({ "VimEnter", "SessionLoadPost" }, env.fake_vim._autocmds[2].event)

    local cfg = env.codex.get_config()
    assert.equal("codex-test", cfg.launch.cmd)
    assert.is_nil(cfg._deps)
  end)

  it("fires on_setup after setup internals are ready and before restore or auto-start", function()
    -- ========= [A]rrange =========
    local seen = nil

    -- ========= [A]ct     =========
    local env = setup_with_deps({
      hooks = {
        on_setup = function(ctx)
          seen = {
            event = ctx.event,
            config = ctx.config,
            commands = ctx.config.launch.cmd,
          }
        end,
      },
    })

    -- ========= [A]ssert  =========
    assert.same({ "commands" }, env.call_order)
    assert.is_not_nil(seen)
    assert.equal("on_setup", seen.event)
    assert.equal("codex-test", seen.commands)
    assert.equal(env.codex.get_config().launch.cmd, seen.config.launch.cmd)
    assert.equal(0, #env.provider.open_calls)
    assert.equal(1, #env.provider.discover_restorable_calls)
  end)

  it("warns and continues when a lifecycle hook fails", function()
    -- ========= [A]ct     =========
    local env = setup_with_deps({
      hooks = {
        on_setup = function()
          error("hook boom")
        end,
      },
    })

    -- ========= [A]ssert  =========
    assert.equal(1, env.commands.register_calls)
    assert.matches("codex hook on_setup failed: .*hook boom", env.logger.warns[1])
  end)

  it("get_logs returns captured logs and clear_logs empties them", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    send_prompt(env, "hello")

    -- ========= [A]ct     =========
    local logs = env.codex.logs.get()

    -- ========= [A]ssert  =========
    assert.is_true(#logs > 0)

    env.codex.logs.clear()
    local cleared = env.codex.logs.get()
    assert.equal(0, #cleared)
  end)

  it("setup reattaches the visible restored session and closes extras", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      _provider = function(provider, fake_vim)
        fake_vim._set_window_buf(7, 71)
        provider.discover_restorable_fn = function()
          return {
            {
              handle = { id = "hidden", alive = true, bufnr = 41 },
              cmd = "codex-test resume",
              cwd = "/hidden",
              bufnr = 41,
            },
            {
              handle = { id = "visible", alive = true },
              cmd = "codex-test",
              cwd = "/visible",
              bufnr = 71,
              winid = 7,
            },
          }
        end
      end,
    })

    -- ========= [A]ct     =========
    local session = env.store.get_active()

    -- ========= [A]ssert  =========
    assert.is_not_nil(session)
    assert.equal("visible", session.handle.id)
    assert.equal("codex-test", session.cmd)
    assert.equal("/visible", session.cwd)
    assert.equal(1, #env.provider.close_calls)
    assert.equal("hidden", env.provider.close_calls[1].id)
    assert.equal(1, #env.provider.attach_restored_calls)
    assert.equal("visible", env.provider.attach_restored_calls[1].handle.id)
    assert.same(env.provider.close_calls[1], {
      id = "hidden",
      alive = true,
      bufnr = 41,
    })
  end)

  it("fires on_terminal_restore after a restored session is attached", function()
    -- ========= [A]rrange =========
    local seen = nil
    local env = setup_with_deps({
      hooks = {
        on_terminal_restore = function(ctx)
          seen = ctx
        end,
      },
      _provider = function(provider, fake_vim)
        fake_vim._set_window_buf(7, 71)
        provider.discover_restorable_fn = function()
          return {
            {
              handle = { id = "visible", alive = true, bufnr = 71, winid = 7 },
              cmd = "codex-test",
              cwd = "/visible",
              bufnr = 71,
              winid = 7,
            },
          }
        end
      end,
    })

    -- ========= [A]ct     =========
    local session = env.store.get_active()

    -- ========= [A]ssert  =========
    assert.is_not_nil(session)
    assert.is_not_nil(seen)
    assert.equal("on_terminal_restore", seen.event)
    assert.equal("native", seen.provider)
    assert.equal(71, seen.bufnr)
    assert.equal(7, seen.winid)
    assert.equal("codex-test", seen.cmd)
    assert.equal("/visible", seen.cwd)
    assert.equal(env.codex.get_config().launch.cmd, seen.config.launch.cmd)
  end)

  it("setup attaches restored session only after extra sessions are closed", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      _provider = function(provider, fake_vim)
        fake_vim._set_window_buf(7, 71)
        provider.discover_restorable_fn = function()
          return {
            {
              handle = { id = "hidden", alive = true, bufnr = 41 },
              cmd = "codex-test resume",
              cwd = "/hidden",
              bufnr = 41,
            },
            {
              handle = { id = "visible", alive = true, bufnr = 71, winid = 7 },
              cmd = "codex-test",
              cwd = "/visible",
              bufnr = 71,
              winid = 7,
            },
          }
        end
        provider.attach_restored_fn = function(handle, _, on_exit)
          assert.equal(1, #provider.close_calls)
          assert.equal("hidden", provider.close_calls[1].id)
          assert.equal("visible", handle.id)
          assert.is_function(on_exit)
          return true
        end
      end,
    })

    -- ========= [A]ct     =========
    local session = env.store.get_active()

    -- ========= [A]ssert  =========
    assert.is_not_nil(session)
    assert.equal("visible", session.handle.id)
  end)

  it("SessionLoadPost schedules a restore after session buffers appear", function()
    -- ========= [A]rrange =========
    local restored = false
    local env = setup_with_deps({
      _provider = function(provider, fake_vim)
        provider.discover_restorable_fn = function()
          if not restored then
            return {}
          end
          return {
            {
              handle = { id = "restored", alive = true, bufnr = 71, winid = 7 },
              cmd = "codex-test",
              cwd = "/restored",
              bufnr = 71,
              winid = 7,
            },
          }
        end
        fake_vim._set_window_buf(7, 71)
      end,
    })

    -- ========= [A]ct     =========
    restored = true
    local scheduled_before = #env.fake_vim._scheduled
    env.fake_vim._fire_autocmd("SessionLoadPost")

    -- ========= [A]ssert  =========
    assert.is_nil(env.store.get_active())
    assert.equal(scheduled_before + 1, #env.fake_vim._scheduled)

    env.fake_vim._scheduled[#env.fake_vim._scheduled]()

    local session = env.store.get_active()
    assert.is_not_nil(session)
    assert.equal("restored", session.handle.id)
    assert.equal("codex-test", session.cmd)
    assert.equal("/restored", session.cwd)
  end)

  it("open creates a new session when none exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)

    local session = env.store.get_active()
    -- ========= [A]ct     =========
    -- ========= [A]ssert  =========
    assert.is_not_nil(session)
    assert.equal("native", session.provider_name)
    assert.equal("codex-test", session.cmd)
    assert.equal("/test/cwd", session.cwd)
    assert.equal(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
  end)

  it("fires on_terminal_open after a new session starts", function()
    -- ========= [A]rrange =========
    local seen = nil
    local env = setup_with_deps({
      hooks = {
        on_terminal_open = function(ctx)
          seen = ctx
        end,
      },
      _provider = function(provider)
        provider.open_fn = function(_, handle)
          handle.bufnr = 211
          handle.winid = 21
        end
      end,
    })

    -- ========= [A]ct     =========
    env.codex.session.open(false)

    -- ========= [A]ssert  =========
    assert.is_not_nil(seen)
    assert.equal("on_terminal_open", seen.event)
    assert.equal("native", seen.provider)
    assert.equal(211, seen.bufnr)
    assert.equal(21, seen.winid)
    assert.equal("codex-test", seen.cmd)
    assert.equal("/test/cwd", seen.cwd)
    assert.equal(env.codex.get_config().launch.cmd, seen.config.launch.cmd)
  end)

  it("includes Snacks terminal window fields in on_terminal_open context", function()
    -- ========= [A]rrange =========
    local seen = nil
    local env = setup_with_deps({
      hooks = {
        on_terminal_open = function(ctx)
          seen = ctx
        end,
      },
      _provider = function(provider)
        provider.next_open_handle = {
          id = "snacks_handle",
          alive = true,
          terminal = {
            buf = 212,
            win = 22,
          },
        }
      end,
    })

    -- ========= [A]ct     =========
    env.codex.session.open(false)

    -- ========= [A]ssert  =========
    assert.is_not_nil(seen)
    assert.equal(212, seen.bufnr)
    assert.equal(22, seen.winid)
  end)

  it("open reuses live session and focuses when requested", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    local first_handle = env.store.get_active().handle
    -- ========= [A]ct     =========
    env.codex.session.open(true)
    -- ========= [A]ssert  =========
    assert.equal(1, #env.provider.open_calls)
    assert.equal(1, #env.provider.focus_calls)
    assert.equal(first_handle, env.provider.focus_calls[1])
  end)

  it("open closes and replaces stale session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false
    -- ========= [A]ct     =========
    env.codex.session.open(false)
    -- ========= [A]ssert  =========
    assert.equal(2, #env.provider.open_calls)
    assert.equal(1, #env.provider.close_calls)
    assert.equal(stale_handle, env.provider.close_calls[1])
    assert.equal("handle_2", env.store.get_active().handle.id)
  end)

  it("toggle updates handle when provider returns replacement", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    local replacement = { id = "replacement", alive = true }
    env.provider.toggle_return_new = replacement
    -- ========= [A]ct     =========
    env.codex.session.toggle()
    -- ========= [A]ssert  =========
    assert.equal(1, #env.provider.toggle_calls)
    assert.equal(replacement, env.store.get_active().handle)
  end)

  it("toggle resolves provider once when opening from no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      terminal = { provider = "auto" },
    })
    env.providers.resolve_calls = {}
    -- ========= [A]ct     =========
    env.codex.session.toggle()
    -- ========= [A]ssert  =========
    assert.equal(1, #env.providers.resolve_calls)
    assert.equal("auto", env.providers.resolve_calls[1])
    assert.equal(1, #env.provider.open_calls)
  end)

  it("toggle opens a fresh session when active handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false
    -- ========= [A]ct     =========
    env.codex.session.toggle()
    -- ========= [A]ssert  =========
    assert.equal(2, #env.provider.open_calls)
    assert.equal(0, #env.provider.toggle_calls)
    assert.equal(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
  end)

  it("focus opens a session when none exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    -- ========= [A]ct     =========
    env.codex.session.toggle()
    -- ========= [A]ssert  =========
    assert.equal(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("is_focused returns false when there is no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local focused = env.codex.session.is_focused()

    -- ========= [A]ssert  =========
    assert.is_false(focused)
  end)

  it("is_focused returns true only when the active Codex buffer has focus", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env)
    -- ========= [A]ct     =========
    env.codex.session.open(false)
    -- ========= [A]ssert  =========
    assert.is_false(env.codex.session.is_focused())

    env.provider.focus(env.store.get_active().handle)
    assert.is_true(env.codex.session.is_focused())
  end)

  it("unfocus restores the last tracked non-Codex buffer after focus", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env, {
      source_win = 3,
      source_buf = 31,
      term_win = 5,
      term_buf = 51,
    })

    -- ========= [A]ct     =========
    env.codex.session.focus()
    assert.is_true(env.codex.session.is_focused())
    local ok, err = env.codex.session.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(3, env.fake_vim._get_current_win())
    assert.equal(31, env.fake_vim._get_current_buf())
    assert.is_false(env.codex.session.is_focused())
  end)

  it("unfocus returns false when there is no tracked non-Codex location", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env)

    -- ========= [A]ct     =========
    env.codex.session.open(false)
    env.provider.focus(env.store.get_active().handle)
    local ok, err = env.codex.session.unfocus()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no previous non-Codex location", err)
    assert.is_true(env.codex.session.is_focused())
  end)

  it(
    "unfocus restores to another window showing the tracked buffer when the original window is invalid",
    function()
      -- ========= [A]rrange =========
      local env = setup_with_deps()
      configure_focusable_terminal(env, {
        source_win = 4,
        source_buf = 41,
        term_win = 5,
        term_buf = 51,
      })
      env.fake_vim._set_window_buf(6, 41)

      -- ========= [A]ct     =========
      env.codex.session.focus()
      env.fake_vim._set_win_valid(4, false)
      local ok, err = env.codex.session.unfocus()

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equal(6, env.fake_vim._get_current_win())
      assert.equal(41, env.fake_vim._get_current_buf())
    end
  )

  it("unfocus tracks the latest non-Codex window entered before returning from Codex", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env, {
      source_win = 12,
      source_buf = 121,
      term_win = 13,
      term_buf = 131,
    })
    env.fake_vim._set_window_buf(14, 141)

    -- ========= [A]ct     =========
    env.fake_vim._set_current_win(14)
    env.codex.session.focus()
    local ok, err = env.codex.session.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(14, env.fake_vim._get_current_win())
    assert.equal(141, env.fake_vim._get_current_buf())
  end)

  it("unfocus tracks same-window buffer switches via BufEnter", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env, {
      source_win = 15,
      source_buf = 151,
      term_win = 16,
      term_buf = 161,
    })

    -- ========= [A]ct     =========
    env.fake_vim._set_window_buf(15, 152)
    env.fake_vim._fire_autocmd("BufEnter")
    env.codex.session.focus()
    local ok, err = env.codex.session.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(15, env.fake_vim._get_current_win())
    assert.equal(152, env.fake_vim._get_current_buf())
  end)

  it("unfocus returns a distinct error when the tracked buffer is no longer visible", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env, {
      source_win = 17,
      source_buf = 171,
      term_win = 18,
      term_buf = 181,
    })

    -- ========= [A]ct     =========
    env.codex.session.focus()
    env.fake_vim._set_win_valid(17, false)
    local ok, err = env.codex.session.unfocus()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("tracked non-Codex location is no longer available", err)
  end)

  it(
    "unfocus ignores repeated Codex focus calls and keeps the latest tracked non-Codex location",
    function()
      -- ========= [A]rrange =========
      local env = setup_with_deps()
      configure_focusable_terminal(env, {
        source_win = 7,
        source_buf = 71,
        term_win = 8,
        term_buf = 81,
      })
      env.fake_vim._set_window_buf(9, 91)

      -- ========= [A]ct     =========
      env.fake_vim._set_current_win(9)
      env.codex.session.focus()
      send_prompt(env, "hello")
      local ok, err = env.codex.session.unfocus()

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equal(9, env.fake_vim._get_current_win())
      assert.equal(91, env.fake_vim._get_current_buf())
    end
  )

  it("unfocus returns false when Codex is not currently focused", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env)

    -- ========= [A]ct     =========
    env.codex.session.focus()
    env.fake_vim._set_current_win(1)
    local ok, err = env.codex.session.unfocus()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("Codex is not focused", err)
  end)

  it("close preserves tracked focus state across session reopen", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env, {
      source_win = 9,
      source_buf = 91,
      term_win = 10,
      term_buf = 101,
    })

    -- ========= [A]ct     =========
    env.codex.session.focus()
    env.codex.session.close()
    env.codex.session.open(false)
    env.provider.focus(env.store.get_active().handle)
    local ok, err = env.codex.session.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(9, env.fake_vim._get_current_win())
    assert.equal(91, env.fake_vim._get_current_buf())
  end)

  it("fires on_terminal_close once for explicit session teardown", function()
    -- ========= [A]rrange =========
    local events = {}
    local env = setup_with_deps({
      hooks = {
        on_terminal_close = function(ctx)
          table.insert(events, ctx)
        end,
      },
    })
    env.codex.session.open(false)

    -- ========= [A]ct     =========
    env.codex.session.close()

    -- ========= [A]ssert  =========
    assert.equal(1, #events)
    assert.equal("on_terminal_close", events[1].event)
    assert.equal("native", events[1].provider)
    assert.equal("codex-test", events[1].cmd)
    assert.equal("/test/cwd", events[1].cwd)
    assert.is_nil(env.store.get_active())
  end)

  it("captures terminal fields before explicit provider close mutates the handle", function()
    -- ========= [A]rrange =========
    local seen = nil
    local env = setup_with_deps({
      hooks = {
        on_terminal_close = function(ctx)
          seen = ctx
        end,
      },
      _provider = function(provider)
        provider.open_fn = function(_, handle)
          handle.bufnr = 213
          handle.winid = 23
        end
        provider.close_fn = function(handle)
          handle.bufnr = nil
          handle.winid = nil
          return true
        end
      end,
    })
    env.codex.session.open(false)

    -- ========= [A]ct     =========
    env.codex.session.close()

    -- ========= [A]ssert  =========
    assert.is_not_nil(seen)
    assert.equal(213, seen.bufnr)
    assert.equal(23, seen.winid)
  end)

  it("captures terminal fields before stale-session provider close mutates the handle", function()
    -- ========= [A]rrange =========
    local events = {}
    local env = setup_with_deps({
      hooks = {
        on_terminal_close = function(ctx)
          table.insert(events, ctx)
        end,
      },
      _provider = function(provider)
        provider.open_fn = function(_, handle)
          handle.bufnr = 214
          handle.winid = 24
        end
        provider.close_fn = function(handle)
          handle.bufnr = nil
          handle.winid = nil
          return true
        end
      end,
    })
    env.codex.session.open(false)
    env.store.get_active().handle.alive = false

    -- ========= [A]ct     =========
    env.codex.session.open(false)

    -- ========= [A]ssert  =========
    assert.equal(1, #events)
    assert.equal(214, events[1].bufnr)
    assert.equal(24, events[1].winid)
  end)

  it("deduplicates on_terminal_close when provider close also reports process exit", function()
    -- ========= [A]rrange =========
    local close_count = 0
    local env = setup_with_deps({
      hooks = {
        on_terminal_close = function()
          close_count = close_count + 1
        end,
      },
      _provider = function(provider)
        provider.close_fn = function(handle)
          handle.alive = false
          provider.on_exit_callbacks[1]()
          return true
        end
      end,
    })
    env.codex.session.open(false)

    -- ========= [A]ct     =========
    env.codex.session.close()

    -- ========= [A]ssert  =========
    assert.equal(1, close_count)
    assert.is_nil(env.store.get_active())
  end)

  it("send auto-opens when missing and logs provider errors", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    local test_prompt = "hello"
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    -- ========= [A]ct     =========
    send_prompt(env, test_prompt)
    -- ========= [A]ssert  =========
    assert.equal(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
    assert.equal(1, #env.provider.send_calls)
    assert.same("\27[200~" .. test_prompt .. "\27[201~", env.provider.send_calls[1].text)
    assert.equal(0, #env.provider.focus_calls)
    assert.matches("failed to send text: boom", env.logger.errors[1])
  end)

  it("send focuses active terminal after successful send", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    local test_prompt = "hello"
    env.codex.session.open(false)
    local active_handle = env.store.get_active().handle
    -- ========= [A]ct     =========
    send_prompt(env, test_prompt)
    -- ========= [A]ssert  =========
    assert.equal(1, #env.provider.send_calls)
    assert.same("\27[200~" .. test_prompt .. "\27[201~", env.provider.send_calls[1].text)
    assert.equal(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
  end)

  it("send reopens session when active handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    local test_prompt = "hello"
    env.codex.session.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false
    -- ========= [A]ct     =========
    send_prompt(env, test_prompt)
    -- ========= [A]ssert  =========
    assert.equal(2, #env.provider.open_calls)
    assert.equal(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
    assert.equal(1, #env.provider.send_calls)
    assert.same("\27[200~" .. test_prompt .. "\27[201~", env.provider.send_calls[1].text)
  end)

  it("send toggles and re-focuses when initial focus fails", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    local test_prompt = "hello"
    env.codex.session.open(false)
    local active_handle = env.store.get_active().handle
    local replacement_handle = { id = "replacement", alive = true }
    env.provider.focus_sequence = {
      { ok = false, err = "terminal window not found" },
      { ok = true },
    }
    env.provider.toggle_return_new = replacement_handle
    -- ========= [A]ct     =========
    send_prompt(env, test_prompt)
    -- ========= [A]ssert  =========
    assert.equal(1, #env.provider.send_calls)
    assert.equal(2, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.same(replacement_handle, env.provider.focus_calls[2])
    assert.equal(1, #env.provider.toggle_calls)
    assert.same(active_handle, env.provider.toggle_calls[1].handle)
    assert.same(replacement_handle, env.store.get_active().handle)
  end)

  it("input.clear sends a translated Ctrl-C sequence to the active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    local test_prompt = "hello"
    env.codex.session.open(false)
    local active_handle = env.store.get_active().handle
    -- ========= [A]ct     =========
    local ok, err = env.codex.input.clear()
    send_prompt(env, test_prompt)
    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(1, #env.fake_vim._replace_termcodes_calls)
    assert.same({
      str = "<C-c>",
      from_part = true,
      do_lt = false,
      special = true,
    }, env.fake_vim._replace_termcodes_calls[1])
    assert.equal(2, #env.provider.send_calls)
    assert.same(active_handle, env.provider.send_calls[1].handle)
    assert.equal("<termcoded:<C-c>>", env.provider.send_calls[1].text)
  end)

  it("input.clear returns false when there is no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.clear()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no active Codex session", err)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("input.clear returns false when the active session handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.store.get_active().handle.alive = false

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.clear()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no active Codex session", err)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("input.clear returns provider send errors", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.clear()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("boom", err)
    assert.equal(1, #env.provider.send_calls)
    assert.equal("<termcoded:<C-c>>", env.provider.send_calls[1].text)
  end)

  it("queued payloads flush in FIFO order once startup readiness is reached", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    -- ========= [A]ct     =========
    send_prompt(env, "first")
    send_prompt(env, "second")
    -- ========= [A]ssert  =========
    assert.equal(0, #env.provider.send_calls)
    run_deferred(env.fake_vim, 2)
    assert.equal(2, #env.provider.send_calls)
    assert.same("\27[200~first\27[201~", env.provider.send_calls[1].text)
    assert.same("\27[200~second\27[201~", env.provider.send_calls[2].text)
  end)

  it("close removes session and is_running reflects alive state", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    assert.is_true(env.codex.session.is_running())
    -- ========= [A]ct     =========
    env.codex.session.close()
    -- ========= [A]ssert  =========
    assert.equal(1, #env.provider.close_calls)
    assert.is_nil(env.store.get_active())
    assert.is_false(env.codex.session.is_running())
  end)

  it("is_running remains read-only and does not trigger restore", function()
    -- ========= [A]rrange =========
    local discover_calls = 0
    local env = setup_with_deps({
      _provider = function(provider)
        provider.discover_restorable_fn = function()
          discover_calls = discover_calls + 1
          if discover_calls == 1 then
            return {}
          end
          return {
            {
              handle = { id = "restored", alive = true, bufnr = 77 },
              cmd = "codex-test",
              cwd = "/restored",
              bufnr = 77,
            },
          }
        end
      end,
    })

    -- ========= [A]ct     =========
    local running = env.codex.session.is_running()

    -- ========= [A]ssert  =========
    assert.is_false(running)
    assert.equal(1, discover_calls)
    assert.is_nil(env.store.get_active())
  end)
end)
