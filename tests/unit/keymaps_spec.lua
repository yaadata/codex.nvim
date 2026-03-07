local function with_stubbed_keymap_set(run)
  local original_keymap_set = vim.keymap.set
  local calls = {}

  vim.keymap.set = function(mode, lhs, rhs, opts)
    table.insert(calls, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
  end

  local ok, err = pcall(run, calls)
  vim.keymap.set = original_keymap_set

  if not ok then
    error(err)
  end
end

local function with_stubbed_feedkeys(run)
  local original_replace_termcodes = vim.api.nvim_replace_termcodes
  local original_feedkeys = vim.api.nvim_feedkeys
  local seen = {}

  vim.api.nvim_replace_termcodes = function(keys)
    seen.input = keys
    return "ENCODED"
  end
  vim.api.nvim_feedkeys = function(keys, mode, escape)
    seen.keys = keys
    seen.mode = mode
    seen.escape = escape
  end

  local ok, err = pcall(run, seen)
  vim.api.nvim_replace_termcodes = original_replace_termcodes
  vim.api.nvim_feedkeys = original_feedkeys

  if not ok then
    error(err)
  end
end

describe("codex.keymaps", function()
  before_each(function()
    package.loaded["codex.keymaps"] = nil
  end)

  it("exposes builtin actions and descriptions", function()
    -- ========= [A]rrange =========
    local keymaps = require("codex.keymaps")

    -- ========= [A]ct     =========
    local toggle_desc = keymaps.get_builtin_desc(keymaps.builtins.toggle)

    -- ========= [A]ssert  =========
    assert.is_function(keymaps.builtins.toggle)
    assert.is_function(keymaps.builtins.clear_input)
    assert.is_function(keymaps.builtins.close)
    assert.is_function(keymaps.builtins.nav_left)
    assert.is_function(keymaps.builtins.nav_down)
    assert.is_function(keymaps.builtins.nav_up)
    assert.is_function(keymaps.builtins.nav_right)
    assert.is_true(keymaps.is_builtin_action(keymaps.builtins.toggle))
    assert.equals("Codex: Toggle terminal", toggle_desc)
  end)

  it("apply_terminal uses builtin desc fallback and explicit desc overrides", function()
    with_stubbed_keymap_set(function(calls)
      -- ========= [A]rrange =========
      local keymaps = require("codex.keymaps")
      local keymap_defs = {
        ["<C-c>"] = {
          mode = "t",
          action = keymaps.builtins.toggle,
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
      assert.equals(2, #calls)

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
      assert.equals("t", toggle_map.mode)
      assert.equals("Codex: Toggle terminal", toggle_map.opts.desc)
      assert.equals(42, toggle_map.opts.buffer)
      assert.is_true(toggle_map.opts.silent)
      assert.is_true(toggle_map.opts.nowait)

      assert.is_not_nil(custom_map)
      assert.same({ "n", "v" }, custom_map.mode)
      assert.equals("Codex: Custom action", custom_map.opts.desc)
    end)
  end)

  it("apply_terminal is a no-op for nil keymaps", function()
    with_stubbed_keymap_set(function(calls)
      -- ========= [A]rrange =========
      local keymaps = require("codex.keymaps")

      -- ========= [A]ct     =========
      keymaps.apply_terminal(42, nil)

      -- ========= [A]ssert  =========
      assert.equals(0, #calls)
    end)
  end)

  it("nav builtins feed terminal navigation keys", function()
    with_stubbed_feedkeys(function(seen)
      -- ========= [A]rrange =========
      local keymaps = require("codex.keymaps")

      -- ========= [A]ct     =========
      keymaps.builtins.nav_left()

      -- ========= [A]ssert  =========
      assert.equals("<C-\\><C-n><C-w>h", seen.input)
      assert.equals("ENCODED", seen.keys)
      assert.equals("n", seen.mode)
      assert.is_false(seen.escape)
    end)
  end)
end)
