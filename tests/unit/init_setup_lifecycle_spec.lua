local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init public api lifecycle", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

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
      codex.open()
    end, "codex.nvim: call require('codex').setup() first")
  end)

  it("requires setup before clear_input", function()
    -- ========= [A]rrange =========
    local codex = require("codex")
    -- ========= [A]ct     =========
    local ok, err = pcall(codex.clear_input)
    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.matches("codex%.nvim: call require%('codex'%).setup%(%)" .. " first", err)
  end)

  it("requires setup before get_logs", function()
    -- ========= [A]rrange =========
    local codex = require("codex")

    -- ========= [A]ct     =========
    local ok, err = pcall(codex.get_logs)

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.matches("codex%.nvim: call require%('codex'%).setup%(%)" .. " first", err)
  end)

  it("requires setup before clear_logs", function()
    -- ========= [A]rrange =========
    local codex = require("codex")

    -- ========= [A]ct     =========
    local ok, err = pcall(codex.clear_logs)

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.matches("codex%.nvim: call require%('codex'%).setup%(%)" .. " first", err)
  end)

  it("setup uses injected dependencies and strips _deps from config", function()
    -- ========= [A]ct     =========
    local env = setup_with_deps({ log = { level = "info", verbose = true } })

    -- ========= [A]ssert  =========
    assert.equals(1, env.commands.register_calls)
    assert.same({ "commands" }, env.call_order)
    assert.equals("info", env.logger.set_levels[1])
    assert.is_true(env.logger.set_verboses[1])
    assert.equals(2, #env.fake_vim._autocmds)
    assert.same({ "WinEnter", "BufEnter" }, env.fake_vim._autocmds[1].event)
    assert.equals("VimLeavePre", env.fake_vim._autocmds[2].event)

    local cfg = env.codex.get_config()
    assert.equals("codex-test", cfg.launch.cmd)
    assert.is_nil(cfg._deps)
  end)

  it("get_logs returns captured logs and clear_logs empties them", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.send("hello")

    -- ========= [A]ct     =========
    local logs = env.codex.get_logs()

    -- ========= [A]ssert  =========
    assert.is_true(#logs > 0)

    env.codex.clear_logs()
    local cleared = env.codex.get_logs()
    assert.equals(0, #cleared)
  end)

  it("open creates a new session when none exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)

    local session = env.store.get_active()
    -- ========= [A]ct     =========
    -- ========= [A]ssert  =========
    assert.is_not_nil(session)
    assert.equals("native", session.provider_name)
    assert.equals("codex-test", session.cmd)
    assert.equals("/test/cwd", session.cwd)
    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
  end)

  it("open reuses live session and focuses when requested", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local first_handle = env.store.get_active().handle
    -- ========= [A]ct     =========
    env.codex.open(true)
    -- ========= [A]ssert  =========
    assert.equals(1, #env.provider.open_calls)
    assert.equals(1, #env.provider.focus_calls)
    assert.equals(first_handle, env.provider.focus_calls[1])
  end)

  it("open closes and replaces stale session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false
    -- ========= [A]ct     =========
    env.codex.open(false)
    -- ========= [A]ssert  =========
    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.equals(stale_handle, env.provider.close_calls[1])
    assert.equals("handle_2", env.store.get_active().handle.id)
  end)

  it("toggle updates handle when provider returns replacement", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local replacement = { id = "replacement", alive = true }
    env.provider.toggle_return_new = replacement
    -- ========= [A]ct     =========
    env.codex.toggle()
    -- ========= [A]ssert  =========
    assert.equals(1, #env.provider.toggle_calls)
    assert.equals(replacement, env.store.get_active().handle)
  end)

  it("toggle resolves provider once when opening from no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      terminal = { provider = "auto" },
    })
    -- ========= [A]ct     =========
    env.codex.toggle()
    -- ========= [A]ssert  =========
    assert.equals(1, #env.providers.resolve_calls)
    assert.equals("auto", env.providers.resolve_calls[1])
    assert.equals(1, #env.provider.open_calls)
  end)

  it("toggle opens a fresh session when active handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false
    -- ========= [A]ct     =========
    env.codex.toggle()
    -- ========= [A]ssert  =========
    assert.equals(2, #env.provider.open_calls)
    assert.equals(0, #env.provider.toggle_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
  end)

  it("focus opens a session when none exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    -- ========= [A]ct     =========
    env.codex.focus()
    -- ========= [A]ssert  =========
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("is_focused returns false when there is no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local focused = env.codex.is_focused()

    -- ========= [A]ssert  =========
    assert.is_false(focused)
  end)

  it("is_focused returns true only when the active Codex buffer has focus", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env)

    -- ========= [A]ct     =========
    env.codex.open(false)
    -- ========= [A]ssert  =========
    assert.is_false(env.codex.is_focused())

    env.provider.focus(env.store.get_active().handle)
    assert.is_true(env.codex.is_focused())
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
    env.codex.focus()
    assert.is_true(env.codex.is_focused())
    local ok, err = env.codex.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(3, env.fake_vim._get_current_win())
    assert.equals(31, env.fake_vim._get_current_buf())
    assert.is_false(env.codex.is_focused())
  end)

  it("unfocus returns false when there is no tracked non-Codex location", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env)

    -- ========= [A]ct     =========
    env.codex.open(false)
    env.provider.focus(env.store.get_active().handle)
    local ok, err = env.codex.unfocus()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("no previous non-Codex location", err)
    assert.is_true(env.codex.is_focused())
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
      env.codex.focus()
      env.fake_vim._set_win_valid(4, false)
      local ok, err = env.codex.unfocus()

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(6, env.fake_vim._get_current_win())
      assert.equals(41, env.fake_vim._get_current_buf())
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
    env.codex.focus()
    local ok, err = env.codex.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(14, env.fake_vim._get_current_win())
    assert.equals(141, env.fake_vim._get_current_buf())
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
    env.codex.focus()
    local ok, err = env.codex.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(15, env.fake_vim._get_current_win())
    assert.equals(152, env.fake_vim._get_current_buf())
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
    env.codex.focus()
    env.fake_vim._set_win_valid(17, false)
    local ok, err = env.codex.unfocus()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("tracked non-Codex location is no longer available", err)
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
      env.codex.focus()
      env.codex.send("hello")
      local ok, err = env.codex.unfocus()

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(9, env.fake_vim._get_current_win())
      assert.equals(91, env.fake_vim._get_current_buf())
    end
  )

  it("unfocus returns false when Codex is not currently focused", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    configure_focusable_terminal(env)

    -- ========= [A]ct     =========
    env.codex.focus()
    env.fake_vim._set_current_win(1)
    local ok, err = env.codex.unfocus()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("Codex is not focused", err)
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
    env.codex.focus()
    env.codex.close()
    env.codex.open(false)
    env.provider.focus(env.store.get_active().handle)
    local ok, err = env.codex.unfocus()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(9, env.fake_vim._get_current_win())
    assert.equals(91, env.fake_vim._get_current_buf())
  end)

  it("send auto-opens when missing and logs provider errors", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    -- ========= [A]ct     =========
    env.codex.send("hello")
    -- ========= [A]ssert  =========
    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
    assert.equals(0, #env.provider.focus_calls)
    assert.matches("failed to send text: boom", env.logger.errors[1])
  end)

  it("send focuses active terminal after successful send", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    -- ========= [A]ct     =========
    env.codex.send("hello")
    -- ========= [A]ssert  =========
    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
  end)

  it("send reopens session when active handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    -- ========= [A]ct     =========
    env.codex.send("hello")
    -- ========= [A]ssert  =========
    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
  end)

  it("send toggles and re-focuses when initial focus fails", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle
    local replacement_handle = { id = "replacement", alive = true }
    env.provider.focus_sequence = {
      { ok = false, err = "terminal window not found" },
      { ok = true },
    }
    env.provider.toggle_return_new = replacement_handle

    -- ========= [A]ct     =========
    env.codex.send("hello")
    -- ========= [A]ssert  =========
    assert.equals(1, #env.provider.send_calls)
    assert.equals(2, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.same(replacement_handle, env.provider.focus_calls[2])
    assert.equals(1, #env.provider.toggle_calls)
    assert.same(active_handle, env.provider.toggle_calls[1].handle)
    assert.same(replacement_handle, env.store.get_active().handle)
  end)

  it("clear_input sends a translated Ctrl-C sequence to the active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    -- ========= [A]ct     =========
    local ok, err = env.codex.clear_input()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(1, #env.fake_vim._replace_termcodes_calls)
    assert.same({
      str = "<C-c>",
      from_part = true,
      do_lt = false,
      special = true,
    }, env.fake_vim._replace_termcodes_calls[1])
    assert.equals(1, #env.provider.send_calls)
    assert.same(active_handle, env.provider.send_calls[1].handle)
    assert.equals("<termcoded:<C-c>>", env.provider.send_calls[1].text)
  end)

  it("clear_input returns false when there is no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.clear_input()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("no active Codex session", err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("clear_input returns false when the active session handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    env.store.get_active().handle.alive = false

    -- ========= [A]ct     =========
    local ok, err = env.codex.clear_input()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("no active Codex session", err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("clear_input returns provider send errors", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    -- ========= [A]ct     =========
    local ok, err = env.codex.clear_input()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-c>>", env.provider.send_calls[1].text)
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
    env.codex.send("first")
    env.codex.send("second")
    -- ========= [A]ssert  =========
    assert.equals(0, #env.provider.send_calls)
    run_deferred(env.fake_vim, 2)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("first", env.provider.send_calls[1].text)
    assert.equals("second", env.provider.send_calls[2].text)
  end)

  it("close removes session and is_running reflects alive state", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    assert.is_true(env.codex.is_running())
    -- ========= [A]ct     =========
    env.codex.close()
    -- ========= [A]ssert  =========
    assert.equals(1, #env.provider.close_calls)
    assert.is_nil(env.store.get_active())
    assert.is_false(env.codex.is_running())
  end)

  it("auto_start schedules open(false)", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({ launch = { auto_start = true } })

    -- ========= [A]ct     =========
    -- ========= [A]ssert  =========
    assert.equals(1, #env.fake_vim._scheduled)
    assert.equals(0, #env.provider.open_calls)

    env.fake_vim._scheduled[1]()

    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
  end)

  it("marks active session dead when provider exit callback fires", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    env.codex.open(false)
    local session = env.store.get_active()
    -- ========= [A]ssert  =========
    assert.is_true(env.codex.is_running())
    assert.equals(1, #env.provider.on_exit_callbacks)

    env.provider.on_exit_callbacks[1]()

    assert.is_nil(env.store.get_active())
    assert.is_false(env.codex.is_running())
    assert.is_false(session.alive)
  end)

  it("marks session dead when opened via toggle and exit callback fires", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    -- ========= [A]ct     =========
    env.codex.toggle()
    local session = env.store.get_active()
    -- ========= [A]ssert  =========
    assert.is_not_nil(session)
    assert.equals(1, #env.provider.on_exit_callbacks)

    env.provider.on_exit_callbacks[1]()

    assert.is_nil(env.store.get_active())
    assert.is_false(session.alive)
  end)
end)
