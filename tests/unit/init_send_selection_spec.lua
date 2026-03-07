local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred
local CTRL_V = string.char(22)

describe("codex.init public api send_selection", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("send_selection formats and sends the visual payload", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(1, #env.selection.calls)
    assert.equals(env.fake_vim, env.selection.calls[1].vim_api)
    assert.equals(1, #env.formatter.selection_specs)
    assert.equals("test/current.lua", env.formatter.selection_specs[1].filepath)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~[selection]\n\27[201~", env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)
    assert.equals(0, #env.fake_vim._input_calls)
  end)

  it("send_selection exits visual mode before dispatching payload", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.fake_vim.fn.mode = function()
      return "v"
    end

    -- ========= [A]ct     =========
    local ok = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.fake_vim._input_calls)
    assert.equals("<termcoded:<Esc>>", env.fake_vim._input_calls[1].keys)
  end)

  it("send_selection schedules a follow-up focus to keep terminal input mode", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      launch = { auto_start = false },
    })

    -- ========= [A]ct     =========
    local ok = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.focus_calls)
    assert.equals(1, #env.fake_vim._scheduled)

    env.fake_vim._scheduled[1]()
    assert.equals(2, #env.provider.focus_calls)
  end)

  it("send_selection wraps real formatter output in bracketed paste", function()
    -- ========= [A]rrange =========
    local real_formatter = require("codex.context.formatter")
    local env = setup_with_deps({
      _deps = {
        formatter = real_formatter,
      },
    })
    env.selection.result = {
      filepath = "justfile",
      start_line = 12,
      end_line = 14,
      filetype = "",
      lines = { "```", "test-unit:" },
    }

    -- ========= [A]ct     =========
    local ok = env.codex.send_selection()
    local expected_payload = real_formatter.format_selection(env.selection.result)

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~" .. expected_payload .. "\27[201~", env.provider.send_calls[1].text)
  end)

  it("send_selection waits for startup readiness before sending", function()
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
    local ok = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 2)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~[selection]\n\27[201~", env.provider.send_calls[1].text)
  end)

  it("send_selection schedules follow-up focus when queued sends flush", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      launch = { auto_start = false },
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    -- ========= [A]ct     =========
    local ok = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._scheduled)

    run_deferred(env.fake_vim, 2)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.provider.focus_calls)
    assert.equals(1, #env.fake_vim._scheduled)
    assert.equals(0, #env.fake_vim._input_calls)

    env.fake_vim._scheduled[1]()
    assert.equals(2, #env.provider.focus_calls)
  end)

  it("send_selection drops queued payload after startup timeout", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 120, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function()
      return false
    end

    -- ========= [A]ct     =========
    local ok = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(0, #env.provider.send_calls)
    run_deferred(env.fake_vim, 3)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to send text: timed out waiting for terminal readiness",
      env.logger.errors[1]
    )
  end)

  it("send_selection logs and returns false when selection fails", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.selection.err = "no visual selection range found"

    -- ========= [A]ct     =========
    local ok, err = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("no visual selection range found", err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to collect selection: no visual selection range found",
      env.logger.errors[1]
    )
  end)

  it("send_selection logs warning and returns false for invalid selection path", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.selection.err = env.selection.errors.INVALID_FILEPATH

    -- ========= [A]ct     =========
    local ok, err = env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals(env.selection.errors.INVALID_FILEPATH, err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to collect selection: current buffer path is not a regular file",
      env.logger.warns[1]
    )
    assert.equals(0, #env.logger.errors)
  end)

  it("send_selection forwards explicit range options to selection extractor", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.fake_vim.fn.mode = function()
      return "v"
    end
    env.fake_vim.fn.getpos = function()
      return { 0, 8, 6, 0 }
    end
    env.fake_vim._set_buf_cursor(1, 0, 10, 4)

    -- ========= [A]ct     =========
    env.codex.send_selection({ line1 = 3, line2 = 5 })

    -- ========= [A]ssert  =========
    assert.same({ line1 = 3, line2 = 5 }, env.selection.calls[1].opts)
  end)

  it("send_selection derives visual range when called in visual mode without opts", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.fake_vim.fn.mode = function()
      return "v"
    end
    env.fake_vim.fn.getpos = function()
      return { 0, 4, 3, 0 }
    end
    env.fake_vim._set_buf_cursor(1, 0, 7, 9)

    -- ========= [A]ct     =========
    env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.same({
      line1 = 4,
      line2 = 7,
      start_col = 2,
      end_col = 9,
      visual_mode = "v",
    }, env.selection.calls[1].opts)
  end)

  it("send_selection derives blockwise mode for visual fallback", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.fake_vim.fn.mode = function()
      return CTRL_V
    end
    env.fake_vim.fn.getpos = function()
      return { 0, 6, 4, 0 }
    end
    env.fake_vim._set_buf_cursor(1, 0, 9, 12)

    -- ========= [A]ct     =========
    env.codex.send_selection()

    -- ========= [A]ssert  =========
    assert.same({
      line1 = 6,
      line2 = 9,
      start_col = 3,
      end_col = 12,
      visual_mode = CTRL_V,
    }, env.selection.calls[1].opts)
  end)
end)
