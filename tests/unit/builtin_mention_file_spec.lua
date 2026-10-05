local helpers = require("tests.unit.helpers.init_spec_helpers")
local builtin = require("codex.builtin")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.builtin mention_file", function()
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
    vim.fn.expand = function(expr, ...)
      if expr == "%:p" then
        return env.fake_vim.fn.expand(expr)
      end
      return original_expand(expr, ...)
    end
    vim.fn.fnamemodify = function(path, modifier)
      if modifier == ":." then
        return env.fake_vim.fn.fnamemodify(path, modifier)
      end
      return original_fnamemodify(path, modifier)
    end
    vim.fn.setreg = env.fake_vim.fn.setreg
    vim.notify = env.fake_vim.notify
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, lines or { "> " })
    return env
  end

  it("sends the relative file path supplied explicitly", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.mention_file("/tmp/example.lua")
    run_deferred(env.fake_vim, 3)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.send_calls)
    assert.equal("\27[200~/mention ../../tmp/example.lua\27[201~", env.provider.send_calls[1].text)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal(0, #env.fake_vim._deferred)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("uses the current buffer file when no path is provided", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.mention_file(nil)
    run_deferred(env.fake_vim, 3)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.send_calls)
    assert.equal("\27[200~/mention ../current-buffer.lua\27[201~", env.provider.send_calls[1].text)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal(0, #env.fake_vim._deferred)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("returns an error without dispatch when the file path is unavailable", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()
    vim.fn.expand = function(expr, ...)
      if expr == "%:p" then
        return ""
      end
      return original_expand(expr, ...)
    end

    -- ========= [A]ct     =========
    local err = builtin.mention_file(nil)

    -- ========= [A]ssert  =========
    assert.equal("current buffer has no file path", err)
    assert.equal(0, #env.provider.send_calls)
    assert.equal(0, #env.fake_vim._deferred)
  end)
end)
