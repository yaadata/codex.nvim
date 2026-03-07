local selection = require("codex.context.selection")

local function make_fake_vim_api(overrides)
  overrides = overrides or {}

  local bufnr = overrides.bufnr or 10
  local filepath = overrides.filepath
  if filepath == nil then
    filepath = "lua/codex/init.lua"
  end

  local marks = overrides.marks or { ["<"] = { 2, 0 }, [">"] = { 4, 0 } }
  local lines = overrides.lines
    or {
      "line 1",
      "line 2",
      "line 3",
      "line 4",
      "line 5",
    }
  local filetype = overrides.filetype or "lua"
  local relative_path = overrides.relative_path or "lua/codex/init.lua"
  local visual_mode = overrides.visual_mode
  local fs_stat = overrides.fs_stat
  local buf_valid = overrides.buf_valid

  return {
    api = {
      nvim_get_current_buf = function()
        return bufnr
      end,
      nvim_buf_is_valid = function()
        if buf_valid == nil then
          return true
        end
        return buf_valid
      end,
      nvim_buf_get_name = function()
        return filepath
      end,
      nvim_buf_get_mark = function(_, mark)
        return marks[mark] or { 0, 0 }
      end,
      nvim_buf_get_lines = function(_, start_idx, end_idx)
        local out = {}
        for i = start_idx + 1, end_idx do
          table.insert(out, lines[i])
        end
        return out
      end,
    },
    bo = {
      [bufnr] = { filetype = filetype },
    },
    fn = {
      fnamemodify = function(_, modifier)
        assert.equals(":.", modifier)
        return relative_path
      end,
      visualmode = function()
        return visual_mode
      end,
    },
    uv = {
      fs_stat = function(path)
        if type(fs_stat) == "function" then
          return fs_stat(path)
        end
        return { type = "file", path = path }
      end,
    },
  }
end

describe("codex.context.selection", function()
  it("returns current buffer filepath as relative ACP path", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api()

    -- ========= [A]ct     =========
    local filepath = selection.get_current_buffer_filepath(vim_api)

    -- ========= [A]ssert  =========
    assert.equals("lua/codex/init.lua", filepath)
  end)

  it("returns error when target buffer is invalid", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({ buf_valid = false })

    -- ========= [A]ct     =========
    local filepath, err = selection.get_current_buffer_filepath(vim_api)

    -- ========= [A]ssert  =========
    assert.is_nil(filepath)
    assert.equals("buffer does not exist", err)
  end)

  it("returns explicit filepath as relative ACP path", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      relative_path = "../../tmp/example.lua",
    })
    local opts = {
      path = "/tmp/example.lua",
    }

    -- ========= [A]ct     =========
    local filepath = selection.get_current_buffer_filepath(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals("../../tmp/example.lua", filepath)
  end)

  it("returns error when explicit path is empty", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api()
    local opts = {
      path = "",
    }

    -- ========= [A]ct     =========
    local filepath, err = selection.get_current_buffer_filepath(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.is_nil(filepath)
    assert.equals("current buffer has no file path", err)
  end)

  it("returns error when explicit path is not a regular file", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      fs_stat = function(path)
        if path == "lua/codex" then
          return { type = "directory" }
        end
        return { type = "file", path = path }
      end,
    })
    local opts = {
      path = "lua/codex",
    }

    -- ========= [A]ct     =========
    local filepath, err = selection.get_current_buffer_filepath(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.is_nil(filepath)
    assert.equals("current buffer path is not a regular file", err)
  end)

  it("prefers explicit path over bufnr lookup when both are provided", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      buf_valid = false,
      relative_path = "src/new.lua",
    })
    local opts = {
      bufnr = 999,
      path = "/repo/src/new.lua",
    }

    -- ========= [A]ct     =========
    local filepath = selection.get_current_buffer_filepath(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals("src/new.lua", filepath)
  end)

  it("extracts multi-line selection from visual marks", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api()

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api)

    -- ========= [A]ssert  =========
    assert.equals("lua/codex/init.lua", spec.filepath)
    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.equals("lua", spec.filetype)
    assert.same({ "line 2", "line 3", "line 4" }, spec.lines)
  end)

  it("extracts single-line selection", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 3, 0 }, [">"] = { 3, 8 } },
    })

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api)

    -- ========= [A]ssert  =========
    assert.equals(3, spec.start_line)
    assert.equals(3, spec.end_line)
    assert.same({ "line 3" }, spec.lines)
  end)

  it("extracts charwise selection using mark columns", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 2, 1 }, [">"] = { 4, 1 } },
    })
    local opts = {
      visual_mode = "v",
    }

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "ine 2", "line 3", "li" }, spec.lines)
  end)

  it("extracts blockwise selection using mark columns", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 2, 1 }, [">"] = { 4, 3 } },
    })
    local opts = {
      visual_mode = string.char(22),
    }

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "ine", "ine", "ine" }, spec.lines)
  end)

  it("returns error when visual marks are invalid", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 0, 0 }, [">"] = { 0, 0 } },
    })

    -- ========= [A]ct     =========
    local spec, err = selection.get_visual_selection(vim_api)

    -- ========= [A]ssert  =========
    assert.is_nil(spec)
    assert.equals("no visual selection range found", err)
  end)

  it("returns relative path", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      filepath = "relative/path.lua",
      relative_path = "relative/path.lua",
    })

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api)

    -- ========= [A]ssert  =========
    assert.equals("relative/path.lua", spec.filepath)
  end)

  it("returns error for unnamed buffers", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({ filepath = "" })

    -- ========= [A]ct     =========
    local spec, err = selection.get_visual_selection(vim_api)

    -- ========= [A]ssert  =========
    assert.is_nil(spec)
    assert.equals("current buffer has no file path", err)
  end)

  it("returns error when buffer path is not a regular file", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      filepath = "lua/codex",
      fs_stat = function()
        return { type = "directory" }
      end,
    })

    -- ========= [A]ct     =========
    local spec, err = selection.get_visual_selection(vim_api)

    -- ========= [A]ssert  =========
    assert.is_nil(spec)
    assert.equals("current buffer path is not a regular file", err)
  end)

  it("uses explicit range when provided", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 4, 0 }, [">"] = { 5, 0 } },
    })
    local opts = {
      line1 = 1,
      line2 = 2,
    }

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals(1, spec.start_line)
    assert.equals(2, spec.end_line)
    assert.same({ "line 1", "line 2" }, spec.lines)
  end)

  it("normalizes reversed explicit ranges", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api()
    local opts = {
      line1 = 4,
      line2 = 2,
    }

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "line 2", "line 3", "line 4" }, spec.lines)
  end)

  it("normalizes reversed visual marks", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 5, 0 }, [">"] = { 3, 0 } },
    })

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api)

    -- ========= [A]ssert  =========
    assert.equals(3, spec.start_line)
    assert.equals(5, spec.end_line)
    assert.same({ "line 3", "line 4", "line 5" }, spec.lines)
  end)

  it("falls back to visual marks when explicit range is invalid", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 2, 0 }, [">"] = { 3, 0 } },
    })
    local opts = {
      line1 = 0,
      line2 = 3,
    }

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals(2, spec.start_line)
    assert.equals(3, spec.end_line)
    assert.same({ "line 2", "line 3" }, spec.lines)
  end)

  it("uses explicit line and column opts when visual marks are unavailable", function()
    -- ========= [A]rrange =========
    local vim_api = make_fake_vim_api({
      marks = { ["<"] = { 0, 0 }, [">"] = { 0, 0 } },
    })
    local opts = {
      line1 = 2,
      line2 = 4,
      start_col = 1,
      end_col = 1,
      visual_mode = "v",
    }

    -- ========= [A]ct     =========
    local spec = selection.get_visual_selection(vim_api, opts)

    -- ========= [A]ssert  =========
    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "ine 2", "line 3", "li" }, spec.lines)
  end)
end)
