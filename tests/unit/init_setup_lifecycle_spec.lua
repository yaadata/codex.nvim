local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init public api lifecycle", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("requires setup before open", function()
    local codex = require("codex")
    assert.has_error(function()
      codex.open()
    end, "codex.nvim: call require('codex').setup() first")
  end)

  it("requires setup before clear_input", function()
    local codex = require("codex")
    assert.has_error(function()
      codex.clear_input()
    end, "codex.nvim: call require('codex').setup() first")
  end)

  it("setup uses injected dependencies and strips _deps from config", function()
    local env = setup_with_deps({ log_level = "info" })

    assert.equals(1, env.commands.register_calls)
    assert.equals(1, env.keymaps.register_calls)
    assert.same({ "commands", "keymaps" }, env.call_order)
    assert.equals("info", env.logger.set_levels[1])
    assert.equals(1, #env.fake_vim._autocmds)
    assert.equals("VimLeavePre", env.fake_vim._autocmds[1].event)

    local cfg = env.codex.get_config()
    assert.equals("codex-test", cfg.cmd)
    assert.is_nil(cfg._deps)
  end)

  it("open creates a new session when none exists", function()
    local env = setup_with_deps()
    env.codex.open(false)

    local session = env.store.get_active()
    assert.is_not_nil(session)
    assert.equals("native", session.provider_name)
    assert.equals("codex-test", session.cmd)
    assert.equals("/test/cwd", session.cwd)
    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
  end)

  it("open reuses live session and focuses when requested", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local first_handle = env.store.get_active().handle

    env.codex.open(true)

    assert.equals(1, #env.provider.open_calls)
    assert.equals(1, #env.provider.focus_calls)
    assert.equals(first_handle, env.provider.focus_calls[1])
  end)

  it("open closes and replaces stale session", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    env.codex.open(false)

    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.equals(stale_handle, env.provider.close_calls[1])
    assert.equals("handle_2", env.store.get_active().handle.id)
  end)

  it("toggle updates handle when provider returns replacement", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local replacement = { id = "replacement", alive = true }
    env.provider.toggle_return_new = replacement

    env.codex.toggle()

    assert.equals(1, #env.provider.toggle_calls)
    assert.equals(replacement, env.store.get_active().handle)
  end)

  it("toggle opens a fresh session when active handle is stale", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    env.codex.toggle()

    assert.equals(2, #env.provider.open_calls)
    assert.equals(0, #env.provider.toggle_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
  end)

  it("focus opens a session when none exists", function()
    local env = setup_with_deps()

    env.codex.focus()

    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("send auto-opens when missing and logs provider errors", function()
    local env = setup_with_deps()
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    env.codex.send("hello")

    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
    assert.equals(0, #env.provider.focus_calls)
    assert.matches("failed to send text: boom", env.logger.errors[1])
  end)

  it("send focuses active terminal after successful send", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    env.codex.send("hello")

    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
  end)

  it("send reopens session when active handle is stale", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    env.codex.send("hello")

    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
  end)

  it("send toggles and re-focuses when initial focus fails", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle
    local replacement_handle = { id = "replacement", alive = true }
    env.provider.focus_sequence = {
      { ok = false, err = "terminal window not found" },
      { ok = true },
    }
    env.provider.toggle_return_new = replacement_handle

    env.codex.send("hello")

    assert.equals(1, #env.provider.send_calls)
    assert.equals(2, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.same(replacement_handle, env.provider.focus_calls[2])
    assert.equals(1, #env.provider.toggle_calls)
    assert.same(active_handle, env.provider.toggle_calls[1].handle)
    assert.same(replacement_handle, env.store.get_active().handle)
  end)

  it("clear_input sends a translated Ctrl-C sequence to the active session", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    local ok, err = env.codex.clear_input()

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
    local env = setup_with_deps()

    local ok, err = env.codex.clear_input()

    assert.is_false(ok)
    assert.equals("no active Codex session", err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("clear_input returns false when the active session handle is stale", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.store.get_active().handle.alive = false

    local ok, err = env.codex.clear_input()

    assert.is_false(ok)
    assert.equals("no active Codex session", err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("clear_input returns provider send errors", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    local ok, err = env.codex.clear_input()

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-c>>", env.provider.send_calls[1].text)
  end)

  it("queued payloads flush in FIFO order once startup readiness is reached", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    env.codex.send("first")
    env.codex.send("second")

    assert.equals(0, #env.provider.send_calls)
    run_deferred(env.fake_vim, 2)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("first", env.provider.send_calls[1].text)
    assert.equals("second", env.provider.send_calls[2].text)
  end)

  it("close removes session and is_running reflects alive state", function()
    local env = setup_with_deps()
    env.codex.open(false)
    assert.is_true(env.codex.is_running())

    env.codex.close()

    assert.equals(1, #env.provider.close_calls)
    assert.is_nil(env.store.get_active())
    assert.is_false(env.codex.is_running())
  end)

  it("auto_start schedules open(false)", function()
    local env = setup_with_deps({ auto_start = true })

    assert.equals(1, #env.fake_vim._scheduled)
    assert.equals(0, #env.provider.open_calls)

    env.fake_vim._scheduled[1]()

    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
  end)

  it("marks active session dead when provider exit callback fires", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local session = env.store.get_active()

    assert.is_true(env.codex.is_running())
    assert.equals(1, #env.provider.on_exit_callbacks)

    env.provider.on_exit_callbacks[1]()

    assert.is_nil(env.store.get_active())
    assert.is_false(env.codex.is_running())
    assert.is_false(session.alive)
  end)

  it("marks session dead when opened via toggle and exit callback fires", function()
    local env = setup_with_deps()
    env.codex.toggle()
    local session = env.store.get_active()

    assert.is_not_nil(session)
    assert.equals(1, #env.provider.on_exit_callbacks)

    env.provider.on_exit_callbacks[1]()

    assert.is_nil(env.store.get_active())
    assert.is_false(session.alive)
  end)
end)
