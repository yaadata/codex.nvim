local helpers = require("tests.unit.helpers.init_spec_helpers")

describe("codex.nvim.visual", function()
  local visual = require("codex.nvim.visual")
  local CTRL_V = string.char(22)

  it("sends escape when mode is charwise visual", function()
    local fake_vim = helpers.make_fake_vim()
    fake_vim.fn.mode = function()
      return "v"
    end

    local ok = visual.exit_visual_mode_if_active(fake_vim)

    assert.is_true(ok)
    assert.equals(1, #fake_vim._input_calls)
    assert.equals("<termcoded:<Esc>>", fake_vim._input_calls[1].keys)
  end)

  it("sends escape when mode is linewise visual", function()
    local fake_vim = helpers.make_fake_vim()
    fake_vim.fn.mode = function()
      return "V"
    end

    local ok = visual.exit_visual_mode_if_active(fake_vim)

    assert.is_true(ok)
    assert.equals(1, #fake_vim._input_calls)
    assert.equals("<termcoded:<Esc>>", fake_vim._input_calls[1].keys)
  end)

  it("sends escape when mode is blockwise visual", function()
    local fake_vim = helpers.make_fake_vim()
    fake_vim.fn.mode = function()
      return CTRL_V
    end

    local ok = visual.exit_visual_mode_if_active(fake_vim)

    assert.is_true(ok)
    assert.equals(1, #fake_vim._input_calls)
    assert.equals("<termcoded:<Esc>>", fake_vim._input_calls[1].keys)
  end)

  it("does nothing when mode is not visual", function()
    local fake_vim = helpers.make_fake_vim()
    fake_vim.fn.mode = function()
      return "n"
    end

    local ok = visual.exit_visual_mode_if_active(fake_vim)

    assert.is_false(ok)
    assert.equals(0, #fake_vim._input_calls)
  end)

  it("does nothing when mode probe fails", function()
    local fake_vim = helpers.make_fake_vim()
    fake_vim.fn.mode = function()
      error("mode unavailable")
    end

    local ok = visual.exit_visual_mode_if_active(fake_vim)

    assert.is_false(ok)
    assert.equals(0, #fake_vim._input_calls)
  end)
end)
