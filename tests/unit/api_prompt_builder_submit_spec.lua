local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps

describe("codex.init public api prompt_builder.submit", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("submits Enter on the active session via feedkeys", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    local active_handle = env.store.get_active().handle

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.submit()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.equal(1, #env.fake_vim._replace_termcodes_calls)
    assert.equal("<CR>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal("nt", env.fake_vim._feedkeys_calls[1].mode)
    assert.is_false(env.fake_vim._feedkeys_calls[1].escape_ks)
    assert.equal(0, #env.provider.send_calls)
  end)

  it("returns false when there is no active session", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.submit()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no active Codex session", err)
    assert.equal(0, #env.provider.focus_calls)
    assert.equal(0, #env.fake_vim._replace_termcodes_calls)
    assert.equal(0, #env.fake_vim._feedkeys_calls)
    assert.equal(0, #env.provider.send_calls)
  end)

  it("returns false when the active session handle is stale", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.store.get_active().handle.alive = false

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.submit()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("no active Codex session", err)
    assert.equal(0, #env.fake_vim._replace_termcodes_calls)
    assert.equal(0, #env.fake_vim._feedkeys_calls)
    assert.equal(0, #env.provider.send_calls)
  end)

  it("falls back to channel send when feedkeys throws", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    local active_handle = env.store.get_active().handle
    env.fake_vim.api.nvim_feedkeys = function()
      error("feedkeys boom")
    end

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.submit()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.equal(1, #env.fake_vim._replace_termcodes_calls)
    assert.equal("<CR>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equal(1, #env.provider.send_calls)
    assert.same(active_handle, env.provider.send_calls[1].handle)
    assert.equal("\r", env.provider.send_calls[1].text)
    assert.matches("feedkeys submit failed, falling back to channel send", env.logger.warns[1])
  end)

  it("returns provider send errors from the channel fallback", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    env.fake_vim.api.nvim_feedkeys = function()
      error("feedkeys boom")
    end
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.submit()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal("boom", err)
    assert.equal(1, #env.provider.send_calls)
    assert.equal("\r", env.provider.send_calls[1].text)
  end)
end)
