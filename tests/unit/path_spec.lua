local path = require("codex.context.path")

describe("codex.context.path", function()
  it("returns relative path from fnamemodify", function()
    local fake_vim = {
      fn = {
        fnamemodify = function(filepath, modifier)
          assert.equals("/repo/lua/codex/init.lua", filepath)
          assert.equals(":.", modifier)
          return "lua/codex/init.lua"
        end,
      },
    }

    assert.equals("lua/codex/init.lua", path.to_relative(fake_vim, "/repo/lua/codex/init.lua"))
  end)

  it("falls back to original path when fnamemodify errors", function()
    local fake_vim = {
      fn = {
        fnamemodify = function()
          error("boom")
        end,
      },
    }

    assert.equals("/repo/file.lua", path.to_relative(fake_vim, "/repo/file.lua"))
  end)

  it("keeps empty path unchanged", function()
    local fake_vim = { fn = {} }
    assert.equals("", path.to_relative(fake_vim, ""))
  end)
end)
