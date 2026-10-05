local path = require("codex.context.path")

describe("codex.context.path", function()
  it("returns relative path from fnamemodify", function()
    -- ========= [A]rrange =========
    local fake_vim = {
      fn = {
        fnamemodify = function(filepath, modifier)
          assert.equal("/repo/lua/codex/init.lua", filepath)
          assert.equal(":.", modifier)
          return "lua/codex/init.lua"
        end,
      },
    }

    -- ========= [A]ct     =========
    local relative_path = path.to_relative(fake_vim, "/repo/lua/codex/init.lua")

    -- ========= [A]ssert  =========
    assert.equal("lua/codex/init.lua", relative_path)
  end)

  it("falls back to original path when fnamemodify errors", function()
    -- ========= [A]rrange =========
    local fake_vim = {
      fn = {
        fnamemodify = function()
          error("boom")
        end,
      },
    }

    -- ========= [A]ct     =========
    local relative_path = path.to_relative(fake_vim, "/repo/file.lua")

    -- ========= [A]ssert  =========
    assert.equal("/repo/file.lua", relative_path)
  end)

  it("keeps empty path unchanged", function()
    -- ========= [A]rrange =========
    local fake_vim = { fn = {} }

    -- ========= [A]ct     =========
    local relative_path = path.to_relative(fake_vim, "")

    -- ========= [A]ssert  =========
    assert.equal("", relative_path)
  end)

  describe("ensure_dir_trailing_separator", function()
    it("adds forward slash for unix-style relative paths", function()
      -- ========= [A]rrange =========

      -- ========= [A]ct     =========
      local normalized_path = path.ensure_dir_trailing_separator(nil, "..")

      -- ========= [A]ssert  =========
      assert.equal("../", normalized_path)
    end)

    it("keeps existing unix trailing slash", function()
      -- ========= [A]rrange =========

      -- ========= [A]ct     =========
      local normalized_path = path.ensure_dir_trailing_separator(nil, "../../tmp/")

      -- ========= [A]ssert  =========
      assert.equal("../../tmp/", normalized_path)
    end)

    it("adds backslash for windows-style paths", function()
      -- ========= [A]rrange =========

      -- ========= [A]ct     =========
      local normalized_path = path.ensure_dir_trailing_separator(nil, "C:\\work\\repo")

      -- ========= [A]ssert  =========
      assert.equal("C:\\work\\repo\\", normalized_path)
    end)

    it("falls back to host OS separator when style is ambiguous", function()
      -- ========= [A]rrange =========
      local fake_vim = {
        uv = {
          os_uname = function()
            return { sysname = "Windows_NT" }
          end,
        },
      }

      -- ========= [A]ct     =========
      local normalized_path = path.ensure_dir_trailing_separator(fake_vim, ".")

      -- ========= [A]ssert  =========
      assert.equal(".\\", normalized_path)
    end)
  end)
end)
