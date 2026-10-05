local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps

describe("codex.init public api input.copy", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("requires setup before input.copy", function()
    -- ========= [A]rrange =========
    local codex = require("codex")

    -- ========= [A]ct     =========
    local ok, err = pcall(codex.input.copy)

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.matches("codex%.nvim: call require%('codex'%).setup%(%)" .. " first", err)
  end)

  it("copies single-line prompt input to the unnamed register", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    local active_handle = env.store.get_active().handle
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.equal(1, #env.fake_vim._setreg_calls)
    assert.equal('"', env.fake_vim._setreg_calls[1].reg)
    assert.equal("draft instructions", env.fake_vim._setreg_calls[1].value)
    assert.equal(0, #env.logger.warns)
    assert.equal(0, #env.provider.send_calls)
  end)

  it("copies multiline prompt input with normalized continuation gutters", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "> first line",
      "  . second line",
      "  third line",
    })
    env.fake_vim._set_buf_cursor(77, 1701, 3, 12)

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(1, #env.fake_vim._setreg_calls)
    assert.equal("first line\nsecond line\nthird line", env.fake_vim._setreg_calls[1].value)
    assert.equal(0, #env.provider.send_calls)
  end)

  it("returns false when there is no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no active Codex session", err)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("returns false when the active session handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.store.get_active().handle.alive = false

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no active Codex session", err)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("returns false when there is no prompt input to copy", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> " })

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no prompt input to copy", err)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("returns false when prompt input capture is uncertain", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 0)

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("could not capture prompt input", err)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("returns false when prompt buffer is unavailable", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return nil
    end

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("could not capture prompt input", err)
    assert.equal(0, #env.fake_vim._setreg_calls)
  end)

  it("returns false when unnamed register copy fails", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> draft instructions" })
    env.fake_vim.fn.setreg = function()
      error("setreg boom")
    end

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.copy()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("failed to copy prompt input", err)
  end)
end)
