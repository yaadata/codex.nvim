local helpers = require("tests.unit.helpers.init_spec_helpers")
local make_fake_vim = helpers.make_fake_vim
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init public api mention_file", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("mention_file sends /mention with explicit path", function()
    local env = setup_with_deps()

    local ok = env.codex.mention_file("/tmp/example.lua")
    local mention_payload_expected =
      "<termcoded:<C-e>><termcoded:<C-u>>/mention ../../tmp/example.lua"

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals("../../tmp/example.lua", env.formatter.mention_paths[1])
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<C-e>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[2].str)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.equals(1, #env.fake_vim._deferred)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equals("nt", env.fake_vim._feedkeys_calls[1].mode)
    assert.is_false(env.fake_vim._feedkeys_calls[1].escape_ks)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(2, #env.provider.focus_calls)
  end)

  it("mention_file waits for startup readiness before sending", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    local ok = env.codex.mention_file("/tmp/example.lua")
    local mention_payload_expected =
      "<termcoded:<C-e>><termcoded:<C-u>>/mention ../../tmp/example.lua"

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equals(1, #env.provider.send_calls)
  end)

  it("mention_file resolves current buffer path when argument is nil", function()
    local env = setup_with_deps()

    local ok = env.codex.mention_file(nil)
    local mention_payload_expected =
      "<termcoded:<C-e>><termcoded:<C-u>>/mention ../current-buffer.lua"

    assert.is_true(ok)
    assert.equals("../current-buffer.lua", env.formatter.mention_paths[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equals(1, #env.provider.send_calls)
  end)

  it("mention_file restores previously typed prompt text after submit", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> asdfadsfadsf" })

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("asdfadsfadsf", env.provider.send_calls[2].text)
  end)

  it("mention_file clears multiline prompt input before dispatching /mention", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> first line", "  second line" })
    env.fake_vim._set_buf_cursor(77, 1701, 2, 11)

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>>/mention ../../tmp/example.lua",
      env.provider.send_calls[1].text
    )
    assert.equals(4, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<C-h>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[4].str)

    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.provider.send_calls)
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.equals("\27[200~first line\nsecond line\27[201~", env.provider.send_calls[3].text)
    assert.equals(0, #env.fake_vim._feedkeys_calls)
  end)

  it("mention_file prefers the nearest prompt head when multiple prompts exist", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "> old prompt",
      "  old continuation",
      "> current prompt",
      "  current continuation",
    })
    env.fake_vim._set_buf_cursor(77, 1701, 4, 22)

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>>/mention ../../tmp/example.lua",
      env.provider.send_calls[1].text
    )

    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.provider.send_calls)
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.equals(
      "\27[200~current prompt\ncurrent continuation\27[201~",
      env.provider.send_calls[3].text
    )
  end)

  it("mention_file strips continuation gutter markers from multiline restore", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "> first line",
      "  . second line",
      "  third line",
    })
    env.fake_vim._set_buf_cursor(77, 1701, 3, 12)

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>>/mention ../../tmp/example.lua",
      env.provider.send_calls[1].text
    )

    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.provider.send_calls)
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.equals(
      "\27[200~first line\nsecond line\nthird line\27[201~",
      env.provider.send_calls[3].text
    )
  end)

  it(
    "mention_file captures multiline drafts for non-standard prompt markers at cursor col 0",
    function()
      local env = setup_with_deps()
      env.codex.open(false)
      env.provider.get_bufnr_fn = function()
        return 77
      end
      env.fake_vim._set_buf_lines(77, {
        "▶ first line",
        "second line",
        "third line",
        "",
      })
      env.fake_vim._set_buf_cursor(77, 1701, 4, 0)

      local ok = env.codex.mention_file("/tmp/example.lua")

      assert.is_true(ok)
      assert.equals(
        "<termcoded:<C-e>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>><termcoded:<C-h>><termcoded:<C-u>>/mention ../../tmp/example.lua",
        env.provider.send_calls[1].text
      )

      run_deferred(env.fake_vim, 1)
      run_deferred(env.fake_vim, 1)
      assert.equals(3, #env.provider.send_calls)
      assert.equals("\r", env.provider.send_calls[2].text)
      assert.equals(
        "\27[200~first line\nsecond line\nthird line\27[201~",
        env.provider.send_calls[3].text
      )
    end
  )

  it("mention_file prefers full prompt head over code-fence-like compact lines", function()
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
      "codex.compact()",
      "end, {",
      'desc = "Run Codex /compact in the active session",',
      "nargs = 0,",
      "})",
      "```",
    }
    env.fake_vim._set_buf_lines(77, draft_lines)
    env.fake_vim._set_buf_cursor(77, 1701, 12, 3)

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    local expected_clear_prefix = "<termcoded:<C-e>><termcoded:<C-u>>"
      .. string.rep("<termcoded:<C-h>><termcoded:<C-u>>", #draft_lines - 1)
    assert.equals(
      expected_clear_prefix .. "/mention ../../tmp/example.lua",
      env.provider.send_calls[1].text
    )

    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.provider.send_calls)
    assert.equals("\r", env.provider.send_calls[2].text)
    local expected_restored = table.concat({
      "asdf",
      "qwerty",
      "asdf",
      "```lua",
      'vim.api.nvim_create_user_command("CodexCompact", function()',
      'local codex = require("codex")',
      "codex.compact()",
      "end, {",
      'desc = "Run Codex /compact in the active session",',
      "nargs = 0,",
      "})",
      "```",
    }, "\n")
    assert.equals("\27[200~" .. expected_restored .. "\27[201~", env.provider.send_calls[3].text)
    assert.equals(0, #env.fake_vim._feedkeys_calls)
  end)

  it("mention_file skips ghost prompt text when cursor is at input start", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> Run /review on my current changes" })
    env.fake_vim._set_buf_cursor(77, 1701, 1, 2)

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.provider.send_calls)
  end)

  it("mention_file falls back to channel submit when feedkeys throws", function()
    local env = setup_with_deps()
    env.fake_vim.api.nvim_feedkeys = function()
      error("feedkeys boom")
    end

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.matches("feedkeys submit failed, falling back to channel send", env.logger.warns[1])
  end)

  it("mention_file logs submit failure when session dies before deferred submit", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> keep me" })

    local ok = env.codex.mention_file("/tmp/example.lua")
    env.store.get_active().handle.alive = false

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
    assert.matches("failed to submit /mention: no active Codex session", env.logger.errors[1])
  end)

  it("mention_file propagates on_sent callback errors through command failure logging", function()
    local env = setup_with_deps()
    env.fake_vim.defer_fn = function()
      error("defer callback boom")
    end

    local ok, err = env.codex.mention_file("/tmp/example.lua")

    assert.is_false(ok)
    assert.matches("defer callback boom", err)
    assert.matches("failed to send command /mention: .*defer callback boom", env.logger.errors[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("mention_file logs restore dispatch failure without crashing", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> asdfadsfadsf" })
    env.provider.send_fn = function(_, text)
      if text == "asdfadsfadsf" then
        return false, "restore boom"
      end
      return true
    end

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)

    assert.equals(2, #env.provider.send_calls)
    assert.equals("asdfadsfadsf", env.provider.send_calls[2].text)
    local saw_restore_log = false
    for _, err in ipairs(env.logger.errors) do
      if err:match("failed to restore terminal input after /mention: restore boom") then
        saw_restore_log = true
        break
      end
    end
    assert.is_true(saw_restore_log)
  end)

  it("mention_file captures prompt text from a non-last line within lookback window", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "line 1",
      "line 2",
      "line 3",
      "> within-lookback",
      "line 5",
      "line 6",
      "line 7",
      "line 8",
      "line 9",
      "line 10",
      "line 11",
      "line 12",
    })

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)

    assert.equals(2, #env.provider.send_calls)
    assert.equals("within-lookback", env.provider.send_calls[2].text)
  end)

  it("mention_file does not capture prompt text beyond lookback window", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    local lines = { "> too-far" }
    for idx = 2, 1000 do
      table.insert(lines, "line " .. idx)
    end
    env.fake_vim._set_buf_lines(77, lines)

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("mention_file captures prompt text when cursor is on a different line", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "> draft-from-line-one",
      "non-prompt cursor line",
    })
    env.fake_vim._set_buf_cursor(77, 1702, 2, 0)

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("draft-from-line-one", env.provider.send_calls[2].text)
  end)

  it("mention_file skips restore when active terminal buffer is empty", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {})

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("mention_file parses normalized prompt tails and strips ANSI escapes", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "\27[32m> old\27[0m\r\27[33m> final-colored-draft\27[0m",
    })

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("final-colored-draft", env.provider.send_calls[2].text)
  end)

  it("mention_file rejects prompt tokens that contain word characters", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "gpt-5 > should-not-restore" })

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("mention_file captures indented prompt input and skips empty prompt input", function()
    local capture_env = setup_with_deps()
    capture_env.codex.open(false)
    capture_env.provider.get_bufnr_fn = function()
      return 77
    end
    capture_env.fake_vim._set_buf_lines(77, { "   › indented-draft" })

    local ok_capture = capture_env.codex.mention_file("/tmp/example.lua")
    assert.is_true(ok_capture)
    run_deferred(capture_env.fake_vim, 1)
    run_deferred(capture_env.fake_vim, 1)
    assert.equals("indented-draft", capture_env.provider.send_calls[2].text)

    local skip_env = setup_with_deps()
    skip_env.codex.open(false)
    skip_env.provider.get_bufnr_fn = function()
      return 77
    end
    skip_env.fake_vim._set_buf_lines(77, { "> " })

    local ok_skip = skip_env.codex.mention_file("/tmp/example.lua")
    assert.is_true(ok_skip)
    run_deferred(skip_env.fake_vim, 1)
    assert.equals(1, #skip_env.provider.send_calls)
    assert.equals(0, #skip_env.fake_vim._deferred)
  end)

  it("mention_file captures compact prompt input without delimiter space", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { ">draft-without-space" })

    local ok = env.codex.mention_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("draft-without-space", env.provider.send_calls[2].text)
  end)

  it("mention_file runs post_execute after deferred restore completes", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> keep me" })
    local callback_calls = {}

    local ok = env.codex.mention_file("/tmp/example.lua", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_true(ok)
    assert.equals(0, #callback_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(0, #callback_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #callback_calls)
    assert.is_true(callback_calls[1].ok)
    assert.is_nil(callback_calls[1].err)
  end)

  it("mention_file submits via channel when post_execute is present", function()
    local env = setup_with_deps()
    local callback_calls = {}

    local ok = env.codex.mention_file("/tmp/example.lua", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)
    assert.equals(0, #env.fake_vim._feedkeys_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.equals(0, #env.fake_vim._feedkeys_calls)
    assert.equals(1, #callback_calls)
    assert.is_true(callback_calls[1].ok)
    assert.is_nil(callback_calls[1].err)
  end)

  it("mention_file runs post_execute on deferred submit failure", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> keep me" })
    local callback_calls = {}

    local ok = env.codex.mention_file("/tmp/example.lua", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })
    env.store.get_active().handle.alive = false

    assert.is_true(ok)
    assert.equals(0, #callback_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #callback_calls)
    assert.is_false(callback_calls[1].ok)
    assert.equals("no active Codex session", callback_calls[1].err)
  end)

  it("mention_file runs post_execute on deferred restore failure", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> asdfadsfadsf" })
    env.provider.send_fn = function(_, text)
      if text == "asdfadsfadsf" then
        return false, "restore boom"
      end
      return true
    end
    local callback_calls = {}

    local ok = env.codex.mention_file("/tmp/example.lua", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    assert.equals(0, #callback_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #callback_calls)
    assert.is_false(callback_calls[1].ok)
    assert.equals("restore boom", callback_calls[1].err)
  end)

  it("mention_file runs post_execute when path resolution fails", function()
    local env = setup_with_deps({
      _deps = {
        vim = vim.tbl_deep_extend("force", make_fake_vim(), {
          fn = {
            expand = function()
              return ""
            end,
          },
        }),
      },
    })
    local callback_calls = {}

    local ok, err = env.codex.mention_file(nil, {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_false(ok)
    assert.equals("current buffer has no file path", err)
    assert.equals(1, #callback_calls)
    assert.is_false(callback_calls[1].ok)
    assert.equals("current buffer has no file path", callback_calls[1].err)
  end)

  it("mention_file runs post_execute when initial mention send fails", function()
    local env = setup_with_deps()
    env.provider.send_fn = function(_, text)
      if text:match("/mention ") then
        return false, "boom"
      end
      return true
    end
    local callback_calls = {}

    local ok, err = env.codex.mention_file("/tmp/example.lua", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals(1, #callback_calls)
    assert.is_false(callback_calls[1].ok)
    assert.equals("boom", callback_calls[1].err)
  end)

  it("mention_file logs and swallows post_execute callback failures", function()
    local env = setup_with_deps()

    local ok = env.codex.mention_file("/tmp/example.lua", {
      post_execute = function()
        error("hook boom")
      end,
    })

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    assert.matches(
      "failed to run /mention post_execute callback: .*hook boom",
      env.logger.errors[1]
    )
  end)

  it("mention_file returns provider send errors with command context", function()
    local env = setup_with_deps()
    env.provider.send_fn = function(_, text)
      if text:match("/mention ") then
        return false, "boom"
      end
      return true
    end

    local ok, err = env.codex.mention_file("/tmp/example.lua")

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.matches("failed to send command /mention: boom", env.logger.errors[1])
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
  end)

  it("mention_file returns error when path is unavailable", function()
    local env = setup_with_deps({
      _deps = {
        vim = vim.tbl_deep_extend("force", make_fake_vim(), {
          fn = {
            expand = function()
              return ""
            end,
          },
        }),
      },
    })

    local ok, err = env.codex.mention_file(nil)

    assert.is_false(ok)
    assert.equals("current buffer has no file path", err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches("failed to mention file: current buffer has no file path", env.logger.errors[1])
  end)
end)
