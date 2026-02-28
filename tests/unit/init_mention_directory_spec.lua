local helpers = require("tests.unit.helpers.init_spec_helpers")
local make_fake_vim = helpers.make_fake_vim
local setup_with_deps = helpers.setup_with_deps
local run_deferred = helpers.run_deferred

describe("codex.init public api mention_directory", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("mention_directory sends /mention with explicit directory path", function()
    local env = setup_with_deps()

    local ok = env.codex.mention_directory("/tmp/")
    local mention_payload_expected = "<termcoded:<C-e>><termcoded:<C-u>>/mention ../../tmp/"

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals("../../tmp/", env.formatter.mention_paths[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)

    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
  end)

  it(
    "mention_directory appends trailing separator when explicit directory path omits it",
    function()
      local env = setup_with_deps()

      local ok = env.codex.mention_directory("/tmp")
      local mention_payload_expected = "<termcoded:<C-e>><termcoded:<C-u>>/mention ../../tmp/"

      assert.is_true(ok)
      assert.equals("../../tmp/", env.formatter.mention_paths[1])
      assert.equals(1, #env.provider.send_calls)
      assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
    end
  )

  it("mention_directory resolves current buffer directory when argument is nil", function()
    local env = setup_with_deps()
    env.fake_vim.uv.os_uname = function()
      return { sysname = "Linux" }
    end

    local ok = env.codex.mention_directory(nil)
    local mention_payload_expected = "<termcoded:<C-e>><termcoded:<C-u>>/mention ../"

    assert.is_true(ok)
    assert.equals("../", env.formatter.mention_paths[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
  end)

  it("mention_directory returns error when path is unavailable", function()
    local env = setup_with_deps({
      _deps = {
        vim = vim.tbl_deep_extend("force", make_fake_vim(), {
          fn = {
            expand = function(expr)
              if expr == "%:p" then
                return "" -- unnamed buffer
              end
              if expr == "%:p:h" then
                return "/fake/cwd" -- Neovim returns cwd for unnamed buffers
              end
              return ""
            end,
          },
        }),
      },
    })

    local ok, err = env.codex.mention_directory(nil)

    assert.is_false(ok)
    assert.equals("current buffer has no directory path", err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to mention directory: current buffer has no directory path",
      env.logger.errors[1]
    )
  end)

  it("mention_directory restores previously typed prompt text after submit", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> asdfadsfadsf" })

    local ok = env.codex.mention_directory("/tmp/")

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

  it("mention_directory runs post_execute after deferred restore completes", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> keep me" })
    local callback_calls = {}

    local ok = env.codex.mention_directory("/tmp/", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_true(ok)
    assert.equals(0, #callback_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(0, #callback_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #callback_calls)
    assert.is_true(callback_calls[1].ok)
    assert.is_nil(callback_calls[1].err)
  end)

  it("mention_directory submits via channel when post_execute is present", function()
    local env = setup_with_deps()
    local callback_calls = {}

    local ok = env.codex.mention_directory("/tmp/", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)
    assert.equals(0, #env.fake_vim._feedkeys_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("\r", env.provider.send_calls[2].text)
    assert.equals(0, #env.fake_vim._feedkeys_calls)
    assert.equals(1, #callback_calls)
    assert.is_true(callback_calls[1].ok)
    assert.is_nil(callback_calls[1].err)
  end)

  it("mention_directory runs post_execute when path resolution fails", function()
    local env = setup_with_deps({
      _deps = {
        vim = vim.tbl_deep_extend("force", make_fake_vim(), {
          fn = {
            expand = function(expr)
              if expr == "%:p" then
                return ""
              end
              if expr == "%:p:h" then
                return "/fake/cwd"
              end
              return ""
            end,
          },
        }),
      },
    })
    local callback_calls = {}

    local ok, err = env.codex.mention_directory(nil, {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_false(ok)
    assert.equals("current buffer has no directory path", err)
    assert.equals(1, #callback_calls)
    assert.is_false(callback_calls[1].ok)
    assert.equals("current buffer has no directory path", callback_calls[1].err)
  end)

  it("mention_directory runs post_execute when initial mention send fails", function()
    local env = setup_with_deps()
    env.provider.send_fn = function(_, text)
      if text:match("/mention ") then
        return false, "boom"
      end
      return true
    end
    local callback_calls = {}

    local ok, err = env.codex.mention_directory("/tmp/", {
      post_execute = function(callback_ok, callback_err)
        table.insert(callback_calls, { ok = callback_ok, err = callback_err })
      end,
    })

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals(1, #callback_calls)
    assert.is_false(callback_calls[1].ok)
    assert.equals("boom", callback_calls[1].err)
  end)

  it("mention_directory returns provider send errors with command context", function()
    local env = setup_with_deps()
    env.provider.send_fn = function(_, text)
      if text:match("/mention ") then
        return false, "boom"
      end
      return true
    end

    local ok, err = env.codex.mention_directory("/tmp/")

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.matches("failed to send command /mention: boom", env.logger.errors[1])
  end)
end)
