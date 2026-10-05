local stub = require("luassert.stub")

local function with_stubbed_keymap_set(run)
  local calls = {}

  stub(vim.keymap, "set", function(mode, lhs, rhs, opts)
    table.insert(calls, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
  end)

  run(calls)
end

local function with_stubbed_feedkeys(run)
  local seen = {}

  stub(vim.api, "nvim_replace_termcodes", function(keys)
    seen.input = keys
    return "ENCODED"
  end)
  stub(vim.api, "nvim_feedkeys", function(keys, mode, escape)
    seen.keys = keys
    seen.mode = mode
    seen.escape = escape
  end)

  run(seen)
end

describe("codex keymap actions and registration", function()
  local stub_snapshot

  before_each(function()
    stub_snapshot = assert:snapshot()
    package.loaded["codex.builtin"] = nil
    package.loaded["codex.builtin.keymaps"] = nil
    package.loaded["codex.nvim.keymaps"] = nil
    package.loaded["codex"] = nil
  end)

  after_each(function()
    stub_snapshot:revert()
    package.loaded["codex"] = nil
  end)

  it("exposes builtin actions and descriptions", function()
    -- ========= [A]rrange =========
    local keymaps = require("codex.nvim.keymaps")
    local actions = require("codex.builtin").keymaps

    -- ========= [A]ct     =========
    local toggle_desc = keymaps.get_builtin_desc(actions.toggle)

    -- ========= [A]ssert  =========
    assert.is_function(actions.toggle)
    assert.is_function(actions.clear_input)
    assert.is_function(actions.unfocus)
    assert.is_function(actions.close)
    assert.is_function(actions.nav_left)
    assert.is_function(actions.nav_down)
    assert.is_function(actions.nav_up)
    assert.is_function(actions.nav_right)
    assert.is_true(keymaps.is_builtin_action(actions.toggle))
    assert.equal("Codex: Toggle terminal", toggle_desc)
    assert.is_nil(actions.apply_terminal)
    assert.is_nil(actions.is_builtin_action)
    assert.is_nil(actions.get_builtin_desc)
  end)

  it("apply_terminal uses builtin desc fallback and explicit desc overrides", function()
    with_stubbed_keymap_set(function(calls)
      -- ========= [A]rrange =========
      local keymaps = require("codex.nvim.keymaps")
      local actions = require("codex.builtin").keymaps
      local keymap_defs = {
        ["<C-c>"] = {
          mode = "t",
          action = actions.toggle,
        },
        ["<leader>ot"] = {
          mode = { "n", "v" },
          action = function() end,
          desc = "Codex: Custom action",
        },
      }

      -- ========= [A]ct     =========
      keymaps.apply_terminal(42, keymap_defs)

      -- ========= [A]ssert  =========
      assert.equal(2, #calls)

      local toggle_map = nil
      local custom_map = nil
      for _, call in ipairs(calls) do
        if call.lhs == "<C-c>" then
          toggle_map = call
        end
        if call.lhs == "<leader>ot" then
          custom_map = call
        end
      end

      assert.is_not_nil(toggle_map)
      assert.equal("t", toggle_map.mode)
      assert.equal("Codex: Toggle terminal", toggle_map.opts.desc)
      assert.equal(42, toggle_map.opts.buffer)
      assert.is_true(toggle_map.opts.silent)
      assert.is_true(toggle_map.opts.nowait)

      assert.is_not_nil(custom_map)
      assert.same({ "n", "v" }, custom_map.mode)
      assert.equal("Codex: Custom action", custom_map.opts.desc)
    end)
  end)

  it("apply_terminal is a no-op for nil keymaps", function()
    with_stubbed_keymap_set(function(calls)
      -- ========= [A]rrange =========
      local keymaps = require("codex.nvim.keymaps")

      -- ========= [A]ct     =========
      keymaps.apply_terminal(42, nil)

      -- ========= [A]ssert  =========
      assert.equal(0, #calls)
    end)
  end)

  it("nav builtins feed terminal navigation keys", function()
    with_stubbed_feedkeys(function(seen)
      -- ========= [A]rrange =========
      local actions = require("codex.builtin").keymaps

      -- ========= [A]ct     =========
      actions.nav_left()

      -- ========= [A]ssert  =========
      assert.equal("<C-\\><C-n><C-w>h", seen.input)
      assert.equal("ENCODED", seen.keys)
      assert.equal("n", seen.mode)
      assert.is_false(seen.escape)
    end)
  end)

  it("unfocus builtin dispatches to codex.session.unfocus", function()
    -- ========= [A]rrange =========
    local calls = 0

    package.loaded["codex"] = {
      session = {
        unfocus = function()
          calls = calls + 1
        end,
      },
    }

    -- ========= [A]ct     =========
    local keymaps = require("codex.nvim.keymaps")
    local actions = require("codex.builtin").keymaps
    actions.unfocus()

    -- ========= [A]ssert  =========
    assert.equal(1, calls)
    assert.equal("Codex: Return to previous buffer", keymaps.get_builtin_desc(actions.unfocus))
  end)
end)
