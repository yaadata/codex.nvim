local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init public api send_command", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("send_command opens with focus when no active session", function()
    local env = setup_with_deps()

    local ok = env.codex.send_command("status")

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("/status", env.provider.send_calls[1].text)
    assert.equals(1, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.equals(2, #env.provider.focus_calls)
  end)

  it("send_command focuses existing session and sends slash command", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    local ok = env.codex.send_command("model")

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals(2, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.same(active_handle, env.provider.focus_calls[2])
    assert.equals("/model", env.provider.send_calls[1].text)
    assert.equals(1, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(0, #env.fake_vim._input_calls)
  end)

  it("send_command normalizes slash prefix and logs send failures", function()
    local env = setup_with_deps()
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    local ok, err = env.codex.send_command("/compact")

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals("/compact", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._feedkeys_calls)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.matches("failed to send command /compact: boom", env.logger.errors[1])
  end)

  it("send_command does not capture or store existing prompt input", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> keep this draft" })

    local ok = env.codex.send_command("status")

    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals("/status", env.provider.send_calls[1].text)
  end)

  it("send_command queues when terminal is starting and flushes later", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    local ok, err = env.codex.send_command("status")

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("/status", env.provider.send_calls[1].text)
    assert.equals(1, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.equals(2, #env.provider.focus_calls)
  end)

  it("send_command waits for provider readiness even when process is alive", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 300, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and true
    end
    env.provider.is_ready_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 150
    end

    local ok, err = env.codex.send_command("status")

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 2)
    assert.equals(0, #env.provider.send_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("/status", env.provider.send_calls[1].text)
    assert.equals(1, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(0, #env.fake_vim._input_calls)
  end)
end)
