local helpers = require("tests.unit.helpers.init_spec_helpers")
local setup = helpers.setup_with_deps

describe("codex.init send api", function()
  it("queues text until send and clears the draft after", function()
    -- ========= [A]rrange =========
    local env = setup()

    it("first send with queued message", function()
      env.codex.prompt_builder.add("a")
      env.codex.prompt_builder.add("b")
      assert.equal(0, #env.provider.open_calls)
      assert.equal(0, #env.provider.send_calls)
      -- ========= [A]ct     =========
      local ok, err = env.codex.prompt_builder.send()
      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equal(1, #env.provider.send_calls)
      assert.same("\27[200~ab\27[201~", env.provider.send_calls[1].text)
      assert.equal(1, #env.provider.focus_calls)
    end)

    it("second send with empty queued message", function()
      -- ========= [A]ct     =========
      local ok, err = env.codex.prompt_builder.send()
      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.is_not_nil(err)
      assert.is_matches("no queued", err)
      assert.equal(1, #env.provider.send_calls)
    end)
  end)
end)
