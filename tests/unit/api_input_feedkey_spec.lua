local helpers = require("tests.unit.helpers.init_spec_helpers")

describe("codex.input.feedkey", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  local function setup_terminal()
    local env = helpers.setup_with_deps()
    env.fake_vim._set_window_buf(1, 11)
    env.provider.open_fn = function(_, handle)
      handle.winid = 2
      handle.bufnr = 200
      env.fake_vim._set_window_buf(2, 200)
    end
    env.provider.focus_fn = function(handle)
      env.fake_vim._set_current_win(handle.winid)
      return true
    end
    local feedkeys = env.fake_vim.api.nvim_feedkeys
    env.fake_vim.api.nvim_feedkeys = function(...)
      env.feed_window = env.fake_vim._get_current_win()
      feedkeys(...)
    end
    env.codex.session.open(false)
    return env
  end

  it("sends the encoded key without changing focus when already focused", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()
    env.fake_vim._set_current_win(2)

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.feedkey("<A-m>")

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal("<termcoded:<A-m>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal("n", env.fake_vim._feedkeys_calls[1].mode)
    assert.is_true(env.fake_vim._feedkeys_calls[1].escape_ks)
    assert.equal(2, env.feed_window)
    assert.equal(2, env.fake_vim._get_current_win())
    assert.equal(0, #env.provider.focus_calls)
  end)

  it("focuses the terminal before sending and restores the editor afterward", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local ok, err = env.codex.input.feedkey("<A-m>")

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(1, #env.provider.focus_calls)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal(2, env.feed_window)
    assert.equal(1, env.fake_vim._get_current_win())
    assert.equal(11, env.fake_vim._get_current_buf())
  end)
end)
