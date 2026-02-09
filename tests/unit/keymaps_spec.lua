local config = require("codex.config")

---@return table
local function make_fake_vim()
  local maps = {
    n = {},
    x = {},
  }
  local set_calls = {}
  local del_calls = {}
  local cmd_calls = {}

  return {
    keymap = {
      set = function(mode, lhs, rhs, opts)
        maps[mode][lhs] = {
          rhs = rhs,
          opts = opts,
        }
        table.insert(set_calls, {
          mode = mode,
          lhs = lhs,
          rhs = rhs,
          opts = opts,
        })
      end,
      del = function(mode, lhs)
        maps[mode][lhs] = nil
        table.insert(del_calls, {
          mode = mode,
          lhs = lhs,
        })
      end,
    },
    fn = {
      maparg = function(lhs, mode)
        if maps[mode][lhs] ~= nil then
          return "<mapped>"
        end
        return ""
      end,
    },
    cmd = function(command)
      table.insert(cmd_calls, command)
    end,
    _maps = maps,
    _set_calls = set_calls,
    _del_calls = del_calls,
    _cmd_calls = cmd_calls,
  }
end

describe("codex.nvim.keymaps", function()
  before_each(function()
    package.loaded["codex.nvim.keymaps"] = nil
  end)

  it("registers all default keymaps with expected mode coverage", function()
    local fake_vim = make_fake_vim()
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(config.apply({}), fake_vim)

    assert.equals(13, #fake_vim._set_calls)
    assert.is_not_nil(fake_vim._maps.n["<leader>ot"])
    assert.is_not_nil(fake_vim._maps.n["<leader>oo"])
    assert.is_not_nil(fake_vim._maps.n["<leader>os"])
    assert.is_not_nil(fake_vim._maps.x["<leader>os"])
    assert.is_function(fake_vim._maps.x["<leader>os"].rhs)

    fake_vim._maps.x["<leader>os"].rhs()
    assert.same({ "'<,'>CodexSend" }, fake_vim._cmd_calls)
  end)

  it("registers no keymaps when keymaps=false", function()
    local fake_vim = make_fake_vim()
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(config.apply({ keymaps = false }), fake_vim)

    assert.equals(0, #fake_vim._set_calls)
  end)

  it("skips individual actions set to false", function()
    local fake_vim = make_fake_vim()
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(config.apply({ keymaps = { status = false } }), fake_vim)

    assert.equals(12, #fake_vim._set_calls)
    assert.is_nil(fake_vim._maps.n["<leader>oi"])
  end)

  it("uses custom key overrides", function()
    local fake_vim = make_fake_vim()
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(config.apply({ keymaps = { toggle = "<leader>xx" } }), fake_vim)

    assert.is_nil(fake_vim._maps.n["<leader>ot"])
    assert.is_not_nil(fake_vim._maps.n["<leader>xx"])
    assert.equals("<Cmd>Codex<CR>", fake_vim._maps.n["<leader>xx"].rhs)
  end)

  it("does not override existing mappings by default", function()
    local fake_vim = make_fake_vim()
    fake_vim._maps.n["<leader>ot"] = {
      rhs = "<Cmd>UserToggle<CR>",
      opts = { desc = "User mapping" },
    }
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(config.apply({}), fake_vim)

    assert.equals(12, #fake_vim._set_calls)
    assert.equals("<Cmd>UserToggle<CR>", fake_vim._maps.n["<leader>ot"].rhs)
  end)

  it("overrides existing mappings when keymaps_force=true", function()
    local fake_vim = make_fake_vim()
    fake_vim._maps.n["<leader>ot"] = {
      rhs = "<Cmd>UserToggle<CR>",
      opts = { desc = "User mapping" },
    }
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(config.apply({ keymaps_force = true }), fake_vim)

    assert.equals(13, #fake_vim._set_calls)
    assert.equals("<Cmd>Codex<CR>", fake_vim._maps.n["<leader>ot"].rhs)
  end)

  it("re-registers cleanly on repeated setup with changed keymaps", function()
    local fake_vim = make_fake_vim()
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(config.apply({}), fake_vim)
    keymaps.register(
      config.apply({
        keymaps = {
          toggle = "<leader>xx",
          status = false,
        },
      }),
      fake_vim
    )

    assert.equals(25, #fake_vim._set_calls)
    assert.equals(13, #fake_vim._del_calls)
    assert.is_nil(fake_vim._maps.n["<leader>ot"])
    assert.is_not_nil(fake_vim._maps.n["<leader>xx"])
    assert.is_nil(fake_vim._maps.n["<leader>oi"])
  end)

  it("disables both send keymaps when send=false", function()
    local fake_vim = make_fake_vim()
    local keymaps = require("codex.nvim.keymaps")

    keymaps.register(
      config.apply({
        keymaps = {
          send = false,
        },
      }),
      fake_vim
    )

    assert.equals(11, #fake_vim._set_calls)
    assert.is_nil(fake_vim._maps.n["<leader>os"])
    assert.is_nil(fake_vim._maps.x["<leader>os"])
  end)
end)
