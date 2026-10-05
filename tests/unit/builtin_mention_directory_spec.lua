local helpers = require("tests.unit.helpers.init_spec_helpers")
local builtin = require("codex.builtin")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.builtin mention_directory", function()
  local original_defer_fn
  local original_expand
  local original_fnamemodify
  local original_setreg
  local original_notify

  before_each(function()
    original_defer_fn = vim.defer_fn
    original_expand = vim.fn.expand
    original_fnamemodify = vim.fn.fnamemodify
    original_setreg = vim.fn.setreg
    original_notify = vim.notify
    package.loaded["codex"] = nil
  end)

  after_each(function()
    vim.defer_fn = original_defer_fn
    vim.fn.expand = original_expand
    vim.fn.fnamemodify = original_fnamemodify
    vim.fn.setreg = original_setreg
    vim.notify = original_notify
  end)

  local function setup_terminal(lines, overrides)
    local env = setup_with_deps(overrides)
    vim.defer_fn = env.fake_vim.defer_fn
    vim.fn.expand = env.fake_vim.fn.expand
    vim.fn.fnamemodify = env.fake_vim.fn.fnamemodify
    vim.fn.setreg = env.fake_vim.fn.setreg
    vim.notify = env.fake_vim.notify
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, lines or { "> " })
    return env
  end

  it("sends the relative directory path with its trailing separator", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.mention_directory("/tmp/")
    run_deferred(env.fake_vim, 1)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(2, #env.provider.send_calls)
    assert.equal("<termcoded:<C-c>>", env.provider.send_calls[1].text)
    assert.equal("\27[200~/mention ../../tmp/\27[201~", env.provider.send_calls[2].text)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("appends a missing trailing separator", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.mention_directory("/tmp")
    run_deferred(env.fake_vim, 1)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(2, #env.provider.send_calls)
    assert.equal("<termcoded:<C-c>>", env.provider.send_calls[1].text)
    assert.equal("\27[200~/mention ../../tmp/\27[201~", env.provider.send_calls[2].text)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("uses the current buffer directory when no path is provided", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.mention_directory(nil)
    run_deferred(env.fake_vim, 1)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(2, #env.provider.send_calls)
    assert.equal("<termcoded:<C-c>>", env.provider.send_calls[1].text)
    assert.equal("\27[200~/mention ../\27[201~", env.provider.send_calls[2].text)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("returns an error without dispatch when the directory path is unavailable", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()
    vim.fn.expand = function(expr)
      assert.equal("%:p:h", expr)
      return ""
    end

    -- ========= [A]ct     =========
    local err = builtin.mention_directory(nil)

    -- ========= [A]ssert  =========
    assert.equal("current buffer has no directory path", err)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._deferred)
  end)
end)
