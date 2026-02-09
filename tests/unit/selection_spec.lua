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
  local expanded_path = overrides.expanded_path or "/repo/lua/codex/init.lua"
  local visual_mode = overrides.visual_mode

  return {
    api = {
      nvim_get_current_buf = function()
        return bufnr
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
        assert.equals(":p", modifier)
        return expanded_path
      end,
      visualmode = function()
        return visual_mode
      end,
    },
  }
end

describe("codex.context.selection", function()
  it("extracts multi-line selection from visual marks", function()
    local spec = selection.get_visual_selection(make_fake_vim_api())

    assert.equals("/repo/lua/codex/init.lua", spec.filepath)
    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.equals("lua", spec.filetype)
    assert.same({ "line 2", "line 3", "line 4" }, spec.lines)
  end)

  it("extracts single-line selection", function()
    local spec = selection.get_visual_selection(make_fake_vim_api({
      marks = { ["<"] = { 3, 0 }, [">"] = { 3, 8 } },
    }))

    assert.equals(3, spec.start_line)
    assert.equals(3, spec.end_line)
    assert.same({ "line 3" }, spec.lines)
  end)

  it("extracts charwise selection using mark columns", function()
    local spec = selection.get_visual_selection(
      make_fake_vim_api({
        marks = { ["<"] = { 2, 1 }, [">"] = { 4, 1 } },
      }),
      {
        visual_mode = "v",
      }
    )

    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "ine 2", "line 3", "li" }, spec.lines)
  end)

  it("extracts blockwise selection using mark columns", function()
    local spec = selection.get_visual_selection(
      make_fake_vim_api({
        marks = { ["<"] = { 2, 1 }, [">"] = { 4, 3 } },
      }),
      {
        visual_mode = string.char(22),
      }
    )

    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "ine", "ine", "ine" }, spec.lines)
  end)

  it("returns error when visual marks are invalid", function()
    local spec, err = selection.get_visual_selection(make_fake_vim_api({
      marks = { ["<"] = { 0, 0 }, [">"] = { 0, 0 } },
    }))

    assert.is_nil(spec)
    assert.equals("no visual selection range found", err)
  end)

  it("returns expanded absolute path", function()
    local spec = selection.get_visual_selection(make_fake_vim_api({
      filepath = "relative/path.lua",
      expanded_path = "/abs/relative/path.lua",
    }))

    assert.equals("/abs/relative/path.lua", spec.filepath)
  end)

  it("returns error for unnamed buffers", function()
    local spec, err = selection.get_visual_selection(make_fake_vim_api({ filepath = "" }))

    assert.is_nil(spec)
    assert.equals("current buffer has no file path", err)
  end)

  it("uses explicit range when provided", function()
    local spec = selection.get_visual_selection(
      make_fake_vim_api({
        marks = { ["<"] = { 4, 0 }, [">"] = { 5, 0 } },
      }),
      {
        line1 = 1,
        line2 = 2,
      }
    )

    assert.equals(1, spec.start_line)
    assert.equals(2, spec.end_line)
    assert.same({ "line 1", "line 2" }, spec.lines)
  end)

  it("normalizes reversed explicit ranges", function()
    local spec = selection.get_visual_selection(make_fake_vim_api(), {
      line1 = 4,
      line2 = 2,
    })

    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "line 2", "line 3", "line 4" }, spec.lines)
  end)

  it("normalizes reversed visual marks", function()
    local spec = selection.get_visual_selection(make_fake_vim_api({
      marks = { ["<"] = { 5, 0 }, [">"] = { 3, 0 } },
    }))

    assert.equals(3, spec.start_line)
    assert.equals(5, spec.end_line)
    assert.same({ "line 3", "line 4", "line 5" }, spec.lines)
  end)

  it("falls back to visual marks when explicit range is invalid", function()
    local spec = selection.get_visual_selection(
      make_fake_vim_api({
        marks = { ["<"] = { 2, 0 }, [">"] = { 3, 0 } },
      }),
      {
        line1 = 0,
        line2 = 3,
      }
    )

    assert.equals(2, spec.start_line)
    assert.equals(3, spec.end_line)
    assert.same({ "line 2", "line 3" }, spec.lines)
  end)

  it("uses explicit line and column opts when visual marks are unavailable", function()
    local spec = selection.get_visual_selection(
      make_fake_vim_api({
        marks = { ["<"] = { 0, 0 }, [">"] = { 0, 0 } },
      }),
      {
        line1 = 2,
        line2 = 4,
        start_col = 1,
        end_col = 1,
        visual_mode = "v",
      }
    )

    assert.equals(2, spec.start_line)
    assert.equals(4, spec.end_line)
    assert.same({ "ine 2", "line 3", "li" }, spec.lines)
  end)
end)
