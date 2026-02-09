local formatter = require("codex.context.formatter")

describe("codex.context.formatter", function()
  describe("format_selection", function()
    it("formats multi-line content with metadata and fence", function()
      local result = formatter.format_selection({
        filepath = "/tmp/example.lua",
        start_line = 10,
        end_line = 12,
        filetype = "lua",
        lines = { "local a = 1", "local b = 2", "return a + b" },
      })

      assert.equals(
        "# Selection from /tmp/example.lua (lines 10-12)\n\n```lua\nlocal a = 1\nlocal b = 2\nreturn a + b\n```\n",
        result
      )
    end)

    it("formats single-line content", function()
      local result = formatter.format_selection({
        filepath = "a.txt",
        start_line = 1,
        end_line = 1,
        filetype = "text",
        lines = { "hello" },
      })

      assert.equals("# Selection from a.txt (lines 1-1)\n\n```text\nhello\n```\n", result)
    end)

    it("uses text fence when filetype is empty", function()
      local result = formatter.format_selection({
        filepath = "a",
        start_line = 2,
        end_line = 3,
        filetype = "",
        lines = { "x", "y" },
      })

      assert.is_not_nil(result:find("```text", 1, true))
    end)

    it("keeps empty filepath as provided", function()
      local result = formatter.format_selection({
        filepath = "",
        start_line = 4,
        end_line = 4,
        filetype = "lua",
        lines = { "return 1" },
      })

      assert.is_not_nil(result:find("# Selection from  %(lines 4%-4%)"))
    end)

    it("extends fence length when content has backticks", function()
      local result = formatter.format_selection({
        filepath = "a.md",
        start_line = 1,
        end_line = 1,
        filetype = "markdown",
        lines = { "````", "body" },
      })

      assert.is_not_nil(result:find("`````markdown", 1, true))
      assert.is_not_nil(result:find("\n`````\n", 1, true))
    end)

    it("accepts string content", function()
      local result = formatter.format_selection({
        filepath = "plain.txt",
        start_line = 5,
        end_line = 6,
        filetype = "text",
        lines = "line a\nline b",
      })

      assert.equals(
        "# Selection from plain.txt (lines 5-6)\n\n```text\nline a\nline b\n```\n",
        result
      )
    end)
  end)

  describe("format_mention", function()
    it("formats mention with spaces in path", function()
      assert.equals(
        "/mention /tmp/dir with space/file.lua\n",
        formatter.format_mention("/tmp/dir with space/file.lua")
      )
    end)

    it("always includes trailing newline", function()
      local result = formatter.format_mention("file.lua")
      assert.equals("\n", result:sub(-1))
    end)
  end)
end)
