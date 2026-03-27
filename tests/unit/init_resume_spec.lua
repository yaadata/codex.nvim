local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps

describe("codex.init public api resume", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("execute_slash_command does not warn for symbol-only prompt markers", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { ">> " })
    env.fake_vim._set_buf_cursor(77, 1702, 1, 0)

    -- ========= [A]ct     =========
    local ok = env.codex.resume()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(0, #env.logger.warns)
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/resume", env.provider.send_calls[1].text)
  end)

  it("resume warns when capture is unavailable for an alive-session buffer", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return nil
    end

    -- ========= [A]ct     =========
    local ok = env.codex.resume()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(0, #env.fake_vim._setreg_calls)
    assert.equals(1, #env.logger.warns)
    assert.equals("Could not save existing prompt before clearing", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/resume", env.provider.send_calls[1].text)
  end)

  it("resume sends /resume when an active session exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    -- ========= [A]ct     =========
    local ok = env.codex.resume()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals(3, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.same(active_handle, env.provider.focus_calls[2])
    assert.same(active_handle, env.provider.focus_calls[3])
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/resume", env.provider.send_calls[1].text)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<C-e>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[2].str)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
  end)

  it("resume copies existing prompt input to unnamed register before dispatching", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> asdf" })

    -- ========= [A]ct     =========
    local ok = env.codex.resume()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.fake_vim._setreg_calls)
    assert.equals('"', env.fake_vim._setreg_calls[1].reg)
    assert.equals("asdf", env.fake_vim._setreg_calls[1].value)
    assert.equals(1, #env.logger.warns)
    assert.equals("Saved current prompt to unnamed register", env.logger.warns[1])
    assert.equals(0, #env.fake_vim._notify_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/resume", env.provider.send_calls[1].text)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
  end)

  it("resume opens `codex resume` when no active session exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.resume()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.same({ "resume" }, env.provider.open_calls[1].args)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(0, #env.provider.send_calls)
  end)

  it("resume lazily reattaches a restored session before dispatching /resume", function()
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

    -- ========= [A]ct     =========
    local ok = env.codex.resume()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(2, discover_calls)
    assert.equals(0, #env.provider.open_calls)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/resume", env.provider.send_calls[1].text)
    assert.equals("restored", env.store.get_active().handle.id)
  end)

  it("resume opens `codex resume --last` when last=true and no active session exists", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.resume({ last = true })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.same({ "resume", "--last" }, env.provider.open_calls[1].args)
    assert.equals(0, #env.provider.send_calls)
  end)

  it("resume ignores last flag when dispatching to active session slash command", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)

    -- ========= [A]ct     =========
    local ok = env.codex.resume({ last = true })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals("<termcoded:<C-e>><termcoded:<C-u>>/resume", env.provider.send_calls[1].text)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
  end)

  it("resume closes stale session before opening resume process", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    -- ========= [A]ct     =========
    local ok = env.codex.resume()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
    assert.same({ "resume" }, env.provider.open_calls[2].args)
    assert.equals(0, #env.provider.send_calls)
  end)
end)
