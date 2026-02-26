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
    env.fake_vim._set_buf_lines(77, {
      "> too-far",
      "line 2",
      "line 3",
      "line 4",
      "line 5",
      "line 6",
      "line 7",
      "line 8",
      "line 9",
      "line 10",
      "line 11",
      "line 12",
      "line 13",
      "line 14",
      "line 15",
      "line 16",
      "line 17",
      "line 18",
      "line 19",
      "line 20",
    })

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
