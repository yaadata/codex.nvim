local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps

describe("codex.init public api send_buffer", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("send_buffer formats and sends the buffer payload", function()
    local env = setup_with_deps()

    local ok = env.codex.send_buffer()

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(1, #env.selection.buffer_calls)
    assert.equals(env.fake_vim, env.selection.buffer_calls[1].vim_api)
    assert.equals(1, #env.formatter.buffer_paths)
    assert.equals("test/current.lua", env.formatter.buffer_paths[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~[@buffer] \27[201~", env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)
  end)

  it("send_buffer warns and returns false for invalid selection path", function()
    local env = setup_with_deps()
    env.selection.buffer_err = env.selection.errors.INVALID_FILEPATH

    local ok, err = env.codex.send_buffer()

    assert.is_false(ok)
    assert.equals(env.selection.errors.INVALID_FILEPATH, err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to collect buffer: current buffer path is not a regular file",
      env.logger.warns[1]
    )
    assert.equals(0, #env.logger.errors)
  end)

  it("send_buffer warns and returns false for unnamed buffers", function()
    local env = setup_with_deps()
    env.selection.buffer_err = env.selection.errors.NO_FILEPATH

    local ok, err = env.codex.send_buffer()

    assert.is_false(ok)
    assert.equals(env.selection.errors.NO_FILEPATH, err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches("failed to collect buffer: current buffer has no file path", env.logger.warns[1])
    assert.equals(0, #env.logger.errors)
  end)

  it("send_buffer warns and returns false when buffer does not exist", function()
    local env = setup_with_deps()
    env.selection.buffer_err = env.selection.errors.BUFFER_NOT_FOUND

    local ok, err = env.codex.send_buffer()

    assert.is_false(ok)
    assert.equals(env.selection.errors.BUFFER_NOT_FOUND, err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches("failed to collect buffer: buffer does not exist", env.logger.warns[1])
    assert.equals(0, #env.logger.errors)
  end)

  it("send_buffer forwards opts to filepath extractor", function()
    local env = setup_with_deps()

    env.codex.send_buffer({ bufnr = 42 })

    assert.same({ bufnr = 42 }, env.selection.buffer_calls[1].opts)
  end)
end)
