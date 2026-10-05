local helpers = require("tests.unit.helpers.init_spec_helpers")
local builtin = require("codex.builtin")
local harness = require("codex.enums.harness")
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.builtin.resume", function()
  local original_defer_fn

  before_each(function()
    original_defer_fn = vim.defer_fn
    package.loaded["codex"] = nil
  end)

  after_each(function()
    vim.defer_fn = original_defer_fn
  end)

  local function setup_terminal()
    local env = setup_with_deps()
    vim.defer_fn = env.fake_vim.defer_fn
    env.codex.session.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> " })
    return env
  end

  it("launches Codex resume by default when no session is running", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local err = builtin.resume()

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.same({ "resume" }, env.provider.open_calls[1].args)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equal(0, #env.provider.send_calls)
  end)

  it("launches Codex resume --last when requested", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local err = builtin.resume({ harness = harness.CODEX, last = true })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.same({ "resume", "--last" }, env.provider.open_calls[1].args)
  end)

  it("sends /resume to the active session instead of launching a process", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.resume()
    run_deferred(env.fake_vim, 3)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.equal(1, #env.provider.send_calls)
    assert.equal("\27[200~/resume\27[201~", env.provider.send_calls[1].text)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("ignores last when sending /resume to an active session", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.resume({ last = true })
    run_deferred(env.fake_vim, 3)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.equal("\27[200~/resume\27[201~", env.provider.send_calls[1].text)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("reattaches a restored session before sending /resume", function()
    -- ========= [A]rrange =========
    local discover_calls = 0
    local env = setup_with_deps({
      _provider = function(provider, fake_vim)
        provider.discover_restorable_fn = function()
          discover_calls = discover_calls + 1
          if discover_calls == 1 then
            return {}
          end
          fake_vim._set_buf_lines(77, { "> " })
          return {
            {
              handle = { id = "restored", alive = true, bufnr = 77, winid = 7 },
              cmd = "codex-test",
              cwd = "/restored",
              bufnr = 77,
              winid = 7,
            },
          }
        end
      end,
    })

    vim.defer_fn = env.fake_vim.defer_fn

    -- ========= [A]ct     =========
    local err = builtin.resume()
    run_deferred(env.fake_vim, 3)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(2, discover_calls)
    assert.equal(0, #env.provider.open_calls)
    assert.equal("restored", env.store.get_active().handle.id)
    assert.equal(0, #env.provider.send_calls)

    assert.is_nil(builtin.resume())
    run_deferred(env.fake_vim, 3)

    assert.equal(1, #env.provider.send_calls)
    assert.equal("\27[200~/resume\27[201~", env.provider.send_calls[1].text)
    assert.equal("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("launches CLAUDE with --resume", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local err = builtin.resume({ harness = harness.CLAUDE, last = false })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.same({ "--resume" }, env.provider.open_calls[1].args)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("launches CLAUDE with --continue", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local err = builtin.resume({ harness = harness.CLAUDE, last = true })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.same({ "--continue" }, env.provider.open_calls[1].args)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("launches PI with --resume", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local err = builtin.resume({ harness = harness.PI, last = false })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.same({ "--resume" }, env.provider.open_calls[1].args)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("launches PI with --continue", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local err = builtin.resume({ harness = harness.PI, last = true })

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.same({ "--continue" }, env.provider.open_calls[1].args)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("sends /resume to an active non-Codex session", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()

    -- ========= [A]ct     =========
    local err = builtin.resume({ harness = harness.CLAUDE })
    run_deferred(env.fake_vim, 3)

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(1, #env.provider.open_calls)
    assert.equal("\27[200~/resume\27[201~", env.provider.send_calls[1].text)
    assert.equal(1, #env.fake_vim._feedkeys_calls)
    assert.equal("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equal(0, #env.fake_vim._deferred)
  end)

  it("closes a stale session before launching a resume process", function()
    -- ========= [A]rrange =========
    local env = setup_terminal()
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    -- ========= [A]ct     =========
    local err = builtin.resume()

    -- ========= [A]ssert  =========
    assert.is_nil(err)
    assert.equal(2, #env.provider.open_calls)
    assert.equal(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
    assert.same({ "resume" }, env.provider.open_calls[2].args)
    assert.equal(0, #env.provider.send_calls)
  end)
end)
