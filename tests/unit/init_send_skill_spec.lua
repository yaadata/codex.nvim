local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup_with_deps = helpers.setup_with_deps

describe("codex.init public api send_skill", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("sends a plugin-qualified skill without focusing Codex", function()
    -- ========= [A]rrange =========
    local env = setup_with_deps()

    -- ========= [A]ct     =========
    local ok = env.codex.send_skill({
      plugin = "code",
      name = "comment",
    })

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~$code:comment \27[201~", env.provider.send_calls[1].text)
    assert.equals(0, #env.provider.focus_calls)
  end)
end)
