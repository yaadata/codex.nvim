local helpers = require("tests.unit.helpers.init_spec_helpers")
local builtin = require("codex.builtin")
local setup_with_deps = helpers.setup_with_deps

describe("codex.builtin sending formatted skills", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("sends a plugin-qualified skill without focusing Codex", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()
    env.codex.session.open(false)
    -- ========= [A]ct     =========
    local formatted, err = builtin.format_skill({
      plugin = "code",
      name = "comment",
    })
    assert.is_nil(err)
    assert.is_not_nil(formatted)

    -- ========= [A]ssert  =========
    local ok = env.codex.prompt_builder.add(formatted)
    assert.is_true(ok)

    -- ========= [A]ct     =========
    local sent, send_err = env.codex.prompt_builder.send()

    -- ========= [A]ssert  =========
    assert.is_true(sent)
    assert.is_nil(send_err)
    assert.equal(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
    assert.equal(1, #env.provider.send_calls)
    assert.equal("\27[200~$code:comment\27[201~", env.provider.send_calls[1].text)
  end)
end)
