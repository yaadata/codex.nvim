describe("codex.keymaps", function()
  before_each(function()
    package.loaded["codex.keymaps"] = nil
  end)

  it("exposes builtin actions and descriptions", function()
    local keymaps = require("codex.keymaps")
    assert.is_function(keymaps.builtins.toggle)
    assert.is_function(keymaps.builtins.clear_input)
    assert.is_function(keymaps.builtins.close)
    assert.is_function(keymaps.builtins.nav_left)
    assert.is_function(keymaps.builtins.nav_down)
    assert.is_function(keymaps.builtins.nav_up)
    assert.is_function(keymaps.builtins.nav_right)
    assert.is_true(keymaps.is_builtin_action(keymaps.builtins.toggle))
    assert.equals("Codex: Toggle terminal", keymaps.get_builtin_desc(keymaps.builtins.toggle))
  end)

  it("apply_terminal uses builtin desc fallback and explicit desc overrides", function()
    local keymaps = require("codex.keymaps")
    local original_keymap_set = vim.keymap.set
    local calls = {}
    vim.keymap.set = function(mode, lhs, rhs, opts)
      table.insert(calls, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
    end

    keymaps.apply_terminal(42, {
      ["<C-c>"] = {
        mode = "t",
        action = keymaps.builtins.toggle,
      },
      ["<leader>ot"] = {
        mode = { "n", "v" },
        action = function() end,
        desc = "Codex: Custom action",
      },
    })

    vim.keymap.set = original_keymap_set

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

  it("apply_terminal is a no-op for nil keymaps", function()
    local keymaps = require("codex.keymaps")
    local original_keymap_set = vim.keymap.set
    local call_count = 0
    vim.keymap.set = function()
      call_count = call_count + 1
    end

    keymaps.apply_terminal(42, nil)

    vim.keymap.set = original_keymap_set
    assert.equals(0, call_count)
  end)

  it("nav builtins feed terminal navigation keys", function()
    local keymaps = require("codex.keymaps")
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

    keymaps.builtins.nav_left()

    vim.api.nvim_replace_termcodes = original_replace_termcodes
    vim.api.nvim_feedkeys = original_feedkeys

    assert.equals("<C-\\><C-n><C-w>h", seen.input)
    assert.equals("ENCODED", seen.keys)
    assert.equals("n", seen.mode)
    assert.is_false(seen.escape)
  end)
end)
