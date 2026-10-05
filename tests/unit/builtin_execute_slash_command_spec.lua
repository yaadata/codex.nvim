local helpers = require("tests.unit.helpers.init_spec_helpers")
local builtin = require("codex.builtin")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.builtin execute_slash_command", function()
  local original_defer_fn
  local original_setreg
  local original_notify
  before_each(function()
    original_defer_fn = vim.defer_fn
    original_setreg = vim.fn.setreg
    original_notify = vim.notify
    package.loaded["codex"] = nil
  end)

  after_each(function()
    vim.defer_fn = original_defer_fn
    vim.fn.setreg = original_setreg
    vim.notify = original_notify
  end)

  it("requires an opts table", function()
    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command()

    -- ========= [A]ssert  =========
    assert.equal("execute_slash_command requires an opts table", err)
  end)

  it("requires opts.command", function()
    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command({})

    -- ========= [A]ssert  =========
    assert.equal("execute_slash_command requires opts.command", err)
  end)

  it("requires a non-empty command", function()
    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command({ command = "   " })

    -- ========= [A]ssert  =========
    assert.equal("execute_slash_command requires a non-empty opts.command", err)
  end)

  it("requires non-string args if args is present", function()
    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command({ command = "review", args = 1 })

    -- ========= [A]ssert  =========
    assert.equal("execute_slash_command expects opts.args to be a string", err)
  end)

  local function setup_terminal(lines, overrides)
    local env = setup_with_deps(overrides)
    vim.defer_fn = env.fake_vim.defer_fn
    vim.fn.setreg = env.fake_vim.fn.setreg
    vim.notify = env.fake_vim.notify
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, lines or { "> " })
    return env
  end

  local function assert_dispatch(env, command)
    assert.equal(1, #env.provider.send_calls)
    assert.equal("<termcoded:<C-c>>", env.provider.send_calls[1].text)
    assert.equal(1, #env.fake_vim._deferred)
    run_deferred(env.fake_vim, 1)
    assert.equal(2, #env.provider.send_calls)
    assert.equal("\27[200~/" .. command .. "\27[201~", env.provider.send_calls[2].text)
    assert.equal(0, #env.fake_vim._feedkeys_calls)
  end

  local function assert_draft_restored(env, draft)
    assert.equal(1, #env.fake_vim._deferred)
    run_deferred(env.fake_vim, 1)
    assert.equal(3, #env.provider.send_calls)
    assert.equal("\27[200~" .. draft .. "\27[201~", env.provider.send_calls[3].text)
    assert.equal(0, #env.fake_vim._deferred)
  end

  local function assert_saved_draft(env, draft)
    assert.equal(1, #env.fake_vim._setreg_calls)
    assert.equal("e", env.fake_vim._setreg_calls[1].reg)
    assert.equal(draft, env.fake_vim._setreg_calls[1].value)
  end

  it("normalizes a leading slash in opts.command", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command({ command = "/permissions" })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert_dispatch(env, "permissions")
  end)

  it("dispatches /review with inline args", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command({
      command = "review",
      args = "focus on security",
    })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert_dispatch(env, "review focus on security")
  end)

  it("treats args = '' as plain /review", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command({
      command = "review",
      args = "",
    })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert_dispatch(env, "review")
  end)

  it("treats empty args as plain /review", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.execute_slash_command({
      command = "review",
      args = "   ",
    })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert_dispatch(env, "review")
  end)

  it("returns an error when no active session exists", function()
    local env = setup_with_deps()
    vim.defer_fn = env.fake_vim.defer_fn

    local err = builtin.execute_slash_command({ command = "review" })

    assert.equal("failed to capture current input", err)
    assert.equal(0, #env.provider.open_calls)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("captures nearest multiline draft and normalizes continuation gutters", function()
    local env = setup_terminal({
      "> stale prompt",
      "  stale continuation",
      "> active prompt",
      "  . active continuation",
      "  final line",
    })
    env.fake_vim._set_buf_cursor(77, 1701, 5, 12)
    local expected_input = "active prompt\nactive continuation\nfinal line"

    local err = builtin.execute_slash_command({ command = "compact" })

    assert.is_nil(err)
    assert_dispatch(env, "compact")
    assert_saved_draft(env, expected_input)
    assert_draft_restored(env, expected_input)
  end)

  it("captures and clears full draft with code-fence-like lines near cursor", function()
    local draft_lines = {
      "> asdf",
      "qwerty",
      "asdf",
      "```lua",
      'vim.api.nvim_create_user_command("CodexCompact", function()',
      'local builtin = require("codex.builtin")',
      'builtin.execute_slash_command({ command = "compact" })',
      "end, {",
      'desc = "Run Codex /compact in the active session",',
      "nargs = 0,",
      "})",
      "```",
    }
    local env = setup_terminal(draft_lines)
    env.fake_vim._set_buf_cursor(77, 1701, #draft_lines, 3)
    local expected_lines = vim.deepcopy(draft_lines)
    expected_lines[1] = "asdf"
    local expected_input = table.concat(expected_lines, "\n")

    local err = builtin.execute_slash_command({ command = "compact" })

    assert.is_nil(err)
    assert_dispatch(env, "compact")
    assert_saved_draft(env, expected_input)
    assert_draft_restored(env, expected_input)
  end)

  it("stops before clearing input when saving the draft throws", function()
    local env = setup_terminal({ "> draft instructions" })
    vim.fn.setreg = function()
      error("setreg boom")
    end

    local ok, err = pcall(builtin.execute_slash_command, { command = "status" })

    assert.is_false(ok)
    assert.matches("setreg boom", err, 1, true)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("preserves the queued builder and skips dispatch when clearing input fails", function()
    local env = setup_terminal({ "> draft" })
    env.codex.prompt_builder.add("queued draft")
    env.provider.send_ok = false
    env.provider.send_err = "clear failed"

    local err = builtin.execute_slash_command({ command = "review" })

    assert.matches("clear failed", err, 1, true)
    assert_saved_draft(env, "draft")
    assert.same({ "queued draft" }, env.codex.prompt_builder.peak())
    assert.equal(1, #env.provider.send_calls)
    assert.equal("<termcoded:<C-c>>", env.provider.send_calls[1].text)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("treats the Codex placeholder at input start as empty input", function()
    local env = setup_terminal({ "› Ask Codex to do anything" })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 3)

    local err = builtin.execute_slash_command({ command = "resume" })

    assert.is_nil(err)
    assert.equal(1, #env.fake_vim._deferred)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("returns an error when prompt input is uncertain", function()
    local env = setup_terminal({ "> draft instructions" })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 0)

    local err = builtin.execute_slash_command({ command = "compact" })

    assert.equal("failed to capture current input", err)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._deferred)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("dispatches when prompt line has no typed input", function()
    local env = setup_terminal()

    env.codex.prompt_builder.add("queued draft")
    local err = builtin.execute_slash_command({ command = "compact" })

    assert.is_nil(err)
    assert.equal(0, #env.fake_vim._setreg_calls)
    assert.equal(0, #env.logger.warns)
    assert_dispatch(env, "compact")
    assert.same({ "queued draft" }, env.codex.prompt_builder.peak())
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("returns an error when capture is unavailable for an alive-session buffer", function()
    local env = setup_terminal()
    env.provider.get_bufnr_fn = function()
      return nil
    end

    local err = builtin.execute_slash_command({ command = "permissions" })

    assert.equal("failed to capture current input", err)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._deferred)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("saves the terminal draft and restores it before the queued builder", function()
    local env = setup_terminal({ "> draft instructions" })
    assert.is_true(env.codex.prompt_builder.add("queued draft"))

    local err = builtin.execute_slash_command({ command = "review" })

    assert.is_nil(err)
    assert_saved_draft(env, "draft instructions")
    assert.same({ "/review" }, env.codex.prompt_builder.peak())
    assert_dispatch(env, "review")
    assert.same({}, env.codex.prompt_builder.peak())
    assert_draft_restored(env, "draft instructions")
    assert.same({ "queued draft" }, env.codex.prompt_builder.peak())
    assert.equal(0, #env.logger.warns)
  end)
  it(
    "reports a failed command send and restores the builder without restoring terminal input",
    function()
      local env = setup_terminal({ "> draft" })
      env.codex.prompt_builder.add("queued draft")
      env.codex.prompt_builder.send = function()
        return false, "command send failed"
      end

      assert.is_nil(builtin.execute_slash_command({ command = "review" }))
      run_deferred(env.fake_vim, 1)

      assert.equal(1, #env.fake_vim._notify_calls)
      assert.equal(vim.log.levels.ERROR, env.fake_vim._notify_calls[1].level)
      assert.matches("command send failed", env.fake_vim._notify_calls[1].msg, 1, true)
      assert.equal(0, #env.fake_vim._deferred)
      assert.same({ "/review", "queued draft" }, env.codex.prompt_builder.peak())
    end
  )

  it("reports a failed draft send and restores the queued builder", function()
    local env = setup_terminal({ "> draft" })
    env.codex.prompt_builder.add("queued draft")
    assert.is_nil(builtin.execute_slash_command({ command = "review" }))
    assert_dispatch(env, "review")
    env.codex.prompt_builder.send = function()
      return false, "draft send failed"
    end

    run_deferred(env.fake_vim, 1)

    assert.equal(1, #env.fake_vim._notify_calls)
    assert.equal(vim.log.levels.ERROR, env.fake_vim._notify_calls[1].level)
    assert.matches("draft send failed", env.fake_vim._notify_calls[1].msg, 1, true)
    assert.equal(0, #env.fake_vim._deferred)
    assert.same({ "draft", "queued draft" }, env.codex.prompt_builder.peak())
  end)
end)
