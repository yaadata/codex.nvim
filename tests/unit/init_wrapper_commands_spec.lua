local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init public api execute_slash_command", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("requires an opts table", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.execute_slash_command()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("execute_slash_command requires an opts table", err)
  end)

  it("requires opts.command", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.execute_slash_command({})

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("execute_slash_command requires opts.command", err)
  end)

  it("requires a non-empty command", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.execute_slash_command({ command = "   " })

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("execute_slash_command requires a non-empty opts.command", err)
  end)

  it("rejects non-string args", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.execute_slash_command({ command = "review", args = 1 })

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equals("execute_slash_command expects opts.args to be a string", err)
  end)

  it("clears input and auto-submits /model", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "model" })
    local model_payload_expected = "<termcoded:<C-e>><termcoded:<C-u>>/model"

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(model_payload_expected, env.provider.send_calls[1].text)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<C-e>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[2].str)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
  end)

  it("dispatches /status", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "status" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/status", env.provider.send_calls[1].text)
  end)

  it("normalizes a leading slash in opts.command", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "/permissions" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/permissions", env.provider.send_calls[1].text)
  end)

  it("dispatches /compact", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "compact" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/compact", env.provider.send_calls[1].text)
  end)

  it("dispatches /review when no args are provided", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "review" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/review", env.provider.send_calls[1].text)
  end)

  it("dispatches /review with inline args", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({
      command = "review",
      args = "focus on security",
    })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>>/review focus on security",
      env.provider.send_calls[1].text
    )
  end)

  it("treats args = '' as plain /review", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "review", args = "" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/review", env.provider.send_calls[1].text)
  end)

  it("treats empty args as plain /review", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "review", args = "   " })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/review", env.provider.send_calls[1].text)
  end)

  it("queues while terminal startup is in progress and flushes later", function()
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
    local ok, err = env.codex.execute_slash_command({ command = "status" })

    -- ========= [A]ssert  =========
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
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/status", env.provider.send_calls[1].text)
    assert.equals(2, #env.provider.focus_calls)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<C-e>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[2].str)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
  end)

  it("opens with focus when no active session exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "review" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/review", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._notify_calls)
  end)

  it("dispatches /diff", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "diff" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/diff", env.provider.send_calls[1].text)
  end)

  it("commands are sent atomically and remain ordered for consecutive calls", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    local ok_status = env.codex.execute_slash_command({ command = "status" })

    -- ========= [A]ct     =========
    local ok_diff = env.codex.execute_slash_command({ command = "diff" })

    -- ========= [A]ssert  =========
    assert.is_true(ok_status)
    assert.is_true(ok_diff)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/status", env.provider.send_calls[1].text)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/diff", env.provider.send_calls[2].text)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(2, #env.fake_vim._feedkeys_calls)
  end)

  it("copies existing prompt input to unnamed register without restoring", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({
      command = "review",
      args = "focus on security",
    })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.fake_vim._setreg_calls)
    assert.equals('"', env.fake_vim._setreg_calls[1].reg)
    assert.equals("draft instructions", env.fake_vim._setreg_calls[1].value)
    assert.equals(1, #env.logger.warns)
    assert.equals("Saved current prompt to unnamed register", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>>/review focus on security",
      env.provider.send_calls[1].text
    )
    assert.equals(1, #env.provider.send_calls)
  end)

  it("clears multiline prompt input before slash dispatch", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> first line", "  second line" })
    env.fake_vim._set_buf_cursor(77, 1701, 2, 11)

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "status" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(2, #env.provider.send_calls)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>>/status",
      env.provider.send_calls[1].text
    )
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.equals(1, #env.fake_vim._setreg_calls)
    assert.equals("first line\nsecond line", env.fake_vim._setreg_calls[1].value)
    assert.equals("<C-e>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[2].str)
    assert.equals("<C-h>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[4].str)
    assert.equals(0, #env.fake_vim._feedkeys_calls)
  end)

  it("captures nearest multiline draft and normalizes continuation gutters", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "> stale prompt",
      "  stale continuation",
      "> active prompt",
      "  . active continuation",
      "  final line",
    })
    env.fake_vim._set_buf_cursor(77, 1701, 5, 12)

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "compact" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(2, #env.provider.send_calls)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>>/compact",
      env.provider.send_calls[1].text
    )
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.equals(1, #env.fake_vim._setreg_calls)
    assert.equals(
      "active prompt\nactive continuation\nfinal line",
      env.fake_vim._setreg_calls[1].value
    )
    assert.equals(0, #env.fake_vim._feedkeys_calls)
  end)

  it("clears full draft when code-fence-like lines are near cursor", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    local draft_lines = {
      "> asdf",
      "qwerty",
      "asdf",
      "```lua",
      'vim.api.nvim_create_user_command("CodexCompact", function()',
      'local codex = require("codex")',
      'codex.execute_slash_command({ command = "compact" })',
      "end, {",
      'desc = "Run Codex /compact in the active session",',
      "nargs = 0,",
      "})",
      "```",
    }
    env.fake_vim._set_buf_lines(77, draft_lines)
    env.fake_vim._set_buf_cursor(77, 1701, 12, 3)

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "compact" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(2, #env.provider.send_calls)
    local expected_clear_prefix = "<termcoded:<C-e>><termcoded:<C-u>>"
      .. string.rep("<termcoded:<C-h>><termcoded:<C-u>>", #draft_lines - 1)
    assert.equals(expected_clear_prefix .. "/compact", env.provider.send_calls[1].text)
    assert.equals("\r", env.provider.send_calls[2].text)
    local expected_saved = table.concat({
      "asdf",
      "qwerty",
      "asdf",
      "```lua",
      'vim.api.nvim_create_user_command("CodexCompact", function()',
      'local codex = require("codex")',
      'codex.execute_slash_command({ command = "compact" })',
      "end, {",
      'desc = "Run Codex /compact in the active session",',
      "nargs = 0,",
      "})",
      "```",
    }, "\n")
    assert.equals(1, #env.fake_vim._setreg_calls)
    assert.equals(expected_saved, env.fake_vim._setreg_calls[1].value)
    assert.equals(0, #env.fake_vim._feedkeys_calls)
  end)

  it("warns when setreg fails", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })
    env.fake_vim.fn.setreg = function()
      error("setreg boom")
    end

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "status" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.logger.warns)
    assert.equals("Could not save existing prompt before clearing", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/status", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
  end)

  it("does not warn when prompt input is uncertain", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 0)

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "compact" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(0, #env.logger.warns)
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/compact", env.provider.send_calls[1].text)
  end)

  it("does not warn when prompt line has no typed input", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> " })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 0)

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "compact" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(0, #env.logger.warns)
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/compact", env.provider.send_calls[1].text)
  end)

  it("warns when capture is unavailable for an alive-session buffer", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return nil
    end

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "permissions" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(1, #env.logger.warns)
    assert.equals("Could not save existing prompt before clearing", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/permissions", env.provider.send_calls[1].text)
  end)

  it("uses logger.warn when prompt save succeeds", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })

    -- ========= [A]ct     =========
    local ok = env.codex.execute_slash_command({ command = "review" })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.logger.warns)
    assert.equals("Saved current prompt to unnamed register", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
  end)
end)
