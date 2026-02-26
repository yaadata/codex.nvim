local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps

describe("codex.init public api wrapper commands", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("set_model clears input and auto-submits /model", function()
    local env = setup_with_deps()

    local ok = env.codex.set_model()
    local model_payload_expected = "<termcoded:<C-e>><termcoded:<C-u>>/model"

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

  it("show_status dispatches /status", function()
    local env = setup_with_deps()

    local ok = env.codex.show_status()

    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/status", env.provider.send_calls[1].text)
  end)

  it("show_permissions dispatches /permissions", function()
    local env = setup_with_deps()

    local ok = env.codex.show_permissions()

    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/permissions", env.provider.send_calls[1].text)
  end)

  it("compact dispatches /compact", function()
    local env = setup_with_deps()

    local ok = env.codex.compact()

    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/compact", env.provider.send_calls[1].text)
  end)

  it("review dispatches /review when no instructions are provided", function()
    local env = setup_with_deps()

    local ok = env.codex.review()

    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/review", env.provider.send_calls[1].text)
  end)

  it("review dispatches /review with inline instructions", function()
    local env = setup_with_deps()

    local ok = env.codex.review("focus on security")

    assert.is_true(ok)
    assert.equals(
      "<termcoded:<C-e>><termcoded:<C-u>>/review focus on security",
      env.provider.send_calls[1].text
    )
  end)

  it("review treats empty instructions as plain /review", function()
    local env = setup_with_deps()

    local ok = env.codex.review("")

    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/review", env.provider.send_calls[1].text)
  end)

  it("review opens with focus when no active session exists", function()
    local env = setup_with_deps()

    local ok = env.codex.review()

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/review", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._notify_calls)
  end)

  it("show_diff dispatches /diff", function()
    local env = setup_with_deps()

    local ok = env.codex.show_diff()

    assert.is_true(ok)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/diff", env.provider.send_calls[1].text)
  end)

  it("wrapper commands are sent atomically and remain ordered for consecutive calls", function()
    local env = setup_with_deps()

    local ok_status = env.codex.show_status()
    local ok_diff = env.codex.show_diff()

    assert.is_true(ok_status)
    assert.is_true(ok_diff)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/status", env.provider.send_calls[1].text)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/diff", env.provider.send_calls[2].text)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(2, #env.fake_vim._feedkeys_calls)
  end)

  it("wrapper commands copy existing prompt input to unnamed register without restoring", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })

    local ok = env.codex.review("focus on security")

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

  it("wrapper commands warn when setreg fails", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })
    env.fake_vim.fn.setreg = function()
      error("setreg boom")
    end

    local ok = env.codex.show_status()

    assert.is_true(ok)
    assert.equals(1, #env.logger.warns)
    assert.equals("Could not save existing prompt before clearing", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/status", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
  end)

  it("wrapper commands do not warn when prompt input is uncertain", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 0)

    local ok = env.codex.compact()

    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(0, #env.logger.warns)
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/compact", env.provider.send_calls[1].text)
  end)

  it("wrapper commands do not warn when prompt line has no typed input", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> " })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 0)

    local ok = env.codex.compact()

    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(0, #env.logger.warns)
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/compact", env.provider.send_calls[1].text)
  end)

  it("wrapper commands warn when capture is unavailable for an alive-session buffer", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return nil
    end

    local ok = env.codex.show_permissions()

    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(1, #env.logger.warns)
    assert.equals("Could not save existing prompt before clearing", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/permissions", env.provider.send_calls[1].text)
  end)

  it("wrapper commands use logger.warn when prompt save succeeds", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })

    local ok = env.codex.review()

    assert.is_true(ok)
    assert.equals(1, #env.logger.warns)
    assert.equals("Saved current prompt to unnamed register", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
  end)
end)
