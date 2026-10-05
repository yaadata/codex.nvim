local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps

describe("codex.init public api prompt_builder.add_file", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("add_file formats and sends the file payload", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.prompt_builder.add_file()
    env.codex.prompt_builder.send()
    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equal(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
    assert.equal(1, #env.selection.buffer_calls)
    assert.equal(env.fake_vim, env.selection.buffer_calls[1].vim_api)
    assert.equal(1, #env.formatter.buffer_paths)
    assert.equal("test/current.lua", env.formatter.buffer_paths[1])
    assert.equal(1, #env.provider.send_calls)
    assert.equal("\27[200~[@buffer] \27[201~", env.provider.send_calls[1].text)
    assert.equal(1, #env.provider.focus_calls)
  end)

  it("add_file warns and returns false for invalid selection path", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.selection.buffer_err = env.selection.errors.INVALID_FILEPATH

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.add_file()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal(env.selection.errors.INVALID_FILEPATH, err)
    assert.equal(0, #env.provider.send_calls)
    assert.matches(
      "failed to collect buffer: current buffer path is not a regular file",
      env.logger.warns[1]
    )
    assert.equal(0, #env.logger.errors)
  end)

  it("add_file warns and returns false for unnamed buffers", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.selection.buffer_err = env.selection.errors.NO_FILEPATH

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.add_file()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal(env.selection.errors.NO_FILEPATH, err)
    assert.equal(0, #env.provider.send_calls)
    assert.matches("failed to collect buffer: current buffer has no file path", env.logger.warns[1])
    assert.equal(0, #env.logger.errors)
  end)

  it("add_file warns and returns false when buffer does not exist", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.selection.buffer_err = env.selection.errors.BUFFER_NOT_FOUND

    -- ========= [A]ct     =========
    local ok, err = env.codex.prompt_builder.add_file()

    -- ========= [A]ssert  =========
    assert.is_false(ok)
    assert.equal(env.selection.errors.BUFFER_NOT_FOUND, err)
    assert.equal(0, #env.provider.send_calls)
    assert.matches("failed to collect buffer: buffer does not exist", env.logger.warns[1])
    assert.equal(0, #env.logger.errors)
  end)

  it("add_file forwards opts to filepath extractor", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    env.codex.prompt_builder.add_file({ bufnr = 42 })

    -- ========= [A]ssert  =========
    assert.same({ bufnr = 42 }, env.selection.buffer_calls[1].opts)
  end)

  it("add_file forwards explicit path to filepath extractor", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    env.codex.prompt_builder.add_file({ path = "/tmp/example.lua" })

    -- ========= [A]ssert  =========
    assert.same({ path = "/tmp/example.lua" }, env.selection.buffer_calls[1].opts)
  end)

  it("add_file forwards both path and bufnr when both are provided", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    env.codex.prompt_builder.add_file({ bufnr = 42, path = "/tmp/example.lua" })

    -- ========= [A]ssert  =========
    assert.same({ bufnr = 42, path = "/tmp/example.lua" }, env.selection.buffer_calls[1].opts)
  end)
end)
