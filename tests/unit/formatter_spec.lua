local formatter = require("codex.context.formatter")

describe("codex.context.formatter", function()
  describe("format_selection", function()
    it("formats multi-line content with metadata and fence", function()
      -- ========= [A]rrange =========
      local selection_spec = {
        filepath = "/tmp/example.lua",
        start_line = 10,
        end_line = 12,
        filetype = "lua",
        lines = { "local a = 1", "local b = 2", "return a + b" },
      }

      -- ========= [A]ct     =========
      local result = formatter.format_selection(selection_spec)

      -- ========= [A]ssert  =========
      assert.equals(
        "@/tmp/example.lua#L10-12\n\n```lua\nlocal a = 1\nlocal b = 2\nreturn a + b\n```\n",
        result
      )
    end)

    it("formats single-line content", function()
      -- ========= [A]rrange =========
      local selection_spec = {
        filepath = "a.txt",
        start_line = 1,
        end_line = 1,
        filetype = "text",
        lines = { "hello" },
      }

      -- ========= [A]ct     =========
      local result = formatter.format_selection(selection_spec)

      -- ========= [A]ssert  =========
      assert.equals("@a.txt#L1\n\n```text\nhello\n```\n", result)
    end)

    it("uses text fence when filetype is empty", function()
      -- ========= [A]rrange =========
      local selection_spec = {
        filepath = "a",
        start_line = 2,
        end_line = 3,
        filetype = "",
        lines = { "x", "y" },
      }

      -- ========= [A]ct     =========
      local result = formatter.format_selection(selection_spec)

      -- ========= [A]ssert  =========
      assert.is_not_nil(result:find("```text", 1, true))
    end)

    it("keeps empty filepath as provided", function()
      -- ========= [A]rrange =========
      local selection_spec = {
        filepath = "",
        start_line = 4,
        end_line = 4,
        filetype = "lua",
        lines = { "return 1" },
      }

      -- ========= [A]ct     =========
      local result = formatter.format_selection(selection_spec)

      -- ========= [A]ssert  =========
      assert.is_not_nil(result:find("@#L4", 1, true))
    end)

    it("extends fence length when content has backticks", function()
      -- ========= [A]rrange =========
      local selection_spec = {
        filepath = "a.md",
        start_line = 1,
        end_line = 1,
        filetype = "markdown",
        lines = { "````", "body" },
      }

      -- ========= [A]ct     =========
      local result = formatter.format_selection(selection_spec)

      -- ========= [A]ssert  =========
      assert.is_not_nil(result:find("`````markdown", 1, true))
      assert.is_not_nil(result:find("\n`````\n$", 1))
    end)

    it("accepts string content", function()
      -- ========= [A]rrange =========
      local selection_spec = {
        filepath = "plain.txt",
        start_line = 5,
        end_line = 6,
        filetype = "text",
        lines = "line a\nline b",
      }

      -- ========= [A]ct     =========
      local result = formatter.format_selection(selection_spec)

      -- ========= [A]ssert  =========
      assert.equals("@plain.txt#L5-6\n\n```text\nline a\nline b\n```\n", result)
    end)
  end)

  describe("format_mention", function()
    it("formats mention with spaces in path", function()
      -- ========= [A]rrange =========
      local filepath = "/tmp/dir with space/file.lua"

      -- ========= [A]ct     =========
      local result = formatter.format_mention(filepath)

      -- ========= [A]ssert  =========
      assert.equals('/mention "/tmp/dir with space/file.lua"', result)
    end)

    it("escapes double-quotes and backslashes for shell-significant paths", function()
      -- ========= [A]rrange =========
      local filepath = 'C:\\work\\my "file".lua'

      -- ========= [A]ct     =========
      local result = formatter.format_mention(filepath)

      -- ========= [A]ssert  =========
      assert.equals('/mention "C:\\\\work\\\\my \\"file\\".lua"', result)
    end)

    it("does not include trailing newline", function()
      -- ========= [A]rrange =========
      local filepath = "file.lua"

      -- ========= [A]ct     =========
      local result = formatter.format_mention(filepath)

      -- ========= [A]ssert  =========
      assert.equals("/mention file.lua", result)
    end)
  end)

  describe("format_buffer_ref", function()
    it("formats ACP buffer reference without line metadata", function()
      -- ========= [A]rrange =========
      local filepath = "lua/codex/init.lua"

      -- ========= [A]ct     =========
      local result = formatter.format_buffer_ref(filepath)

      -- ========= [A]ssert  =========
      assert.equals("@lua/codex/init.lua ", result)
    end)
  end)
end)
