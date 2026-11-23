local builtins = require("codex.builtin").keymaps

describe("codex profile global keymaps (real Neovim)", function()
  local original_mapleader
  local stub_provider
  local stub_providers
  local created_bufs

  local function find_global_map(mode, lhs)
    local tc = vim.api.nvim_replace_termcodes(lhs, true, true, true)
    for _, entry in ipairs(vim.api.nvim_get_keymap(mode)) do
      if entry.lhsraw == tc or entry.lhsrawalt == tc or entry.lhs == lhs then
        return entry
      end
    end
    return nil
  end

  local function find_buf_map(bufnr, mode, lhs)
    local tc = vim.api.nvim_replace_termcodes(lhs, true, true, true)
    for _, entry in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
      if entry.lhsraw == tc or entry.lhsrawalt == tc or entry.lhs == lhs then
        return entry
      end
    end
    return nil
  end

  local function make_provider()
    local next_buf = 1000
    local provider = {
      is_available = function()
        return true
      end,
      discover_restorable = function()
        return {}
      end,
      attach_restored = function()
        return true
      end,
      open = function(_, _, _, config)
        local bufnr = vim.api.nvim_create_buf(false, true)
        table.insert(created_bufs, bufnr)
        require("codex.internal.nvim.keymaps").apply_terminal(
          bufnr,
          config.terminal.keymaps,
          config.profile_identifier
        )
        next_buf = next_buf + 1
        return { bufnr = bufnr, id = next_buf, alive = true }
      end,
      close = function(handle)
        if handle then
          handle.alive = false
        end
        return true
      end,
      is_alive = function(handle)
        return handle ~= nil and handle.alive ~= false
      end,
      is_ready = function(handle)
        return handle ~= nil and handle.alive ~= false
      end,
      get_bufnr = function(handle)
        return handle and handle.bufnr or nil
      end,
      focus = function()
        return true
      end,
      send = function()
        return true
      end,
      toggle = function(handle)
        return handle
      end,
    }
    return provider
  end

  before_each(function()
    original_mapleader = vim.g.mapleader
    vim.g.mapleader = " "
    created_bufs = {}
    package.loaded["codex"] = nil
    stub_provider = make_provider()
    stub_providers = {
      resolve = function()
        return stub_provider, "native"
      end,
    }
  end)

  after_each(function()
    local codex = package.loaded["codex"]
    if codex and type(codex.deactivate) == "function" then
      pcall(codex.deactivate)
    end
    for _, mode in ipairs({ "n", "x", "s", "o", "i", "c", "t" }) do
      for _, lhs in ipairs({
        "<F7>",
        "<F8>",
        "<F9>",
        "<leader>ka",
        "<leader>kb",
        "<leader>kc",
        "<C-K>",
      }) do
        pcall(vim.api.nvim_del_keymap, mode, lhs)
      end
    end
    for _, bufnr in ipairs(created_bufs) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    vim.g.mapleader = original_mapleader
    package.loaded["codex"] = nil
  end)

  it("removes all outgoing owned slots and swaps overlapping slots across profiles", function()
    local calls = {}
    local codex = require("codex")
    codex.setup({
      profiles = {
        default = {
          auto_start = false,
          keymaps = {
            ["<leader>ka"] = {
              mode = "n",
              action = function()
                table.insert(calls, "default_a")
              end,
              desc = "Default A",
            },
            ["<leader>kb"] = {
              mode = "n",
              action = function()
                table.insert(calls, "default_b")
              end,
              desc = "Default B",
            },
          },
        },
        work = {
          keymaps = {
            ["<Space>kb"] = {
              mode = "n",
              action = function()
                table.insert(calls, "work_b")
              end,
              desc = "Work B",
            },
            ["<leader>kc"] = {
              mode = "n",
              action = function()
                table.insert(calls, "work_c")
              end,
              desc = "Work C",
            },
          },
        },
      },
      _deps = { providers = stub_providers },
    })

    assert.equal("Default A", find_global_map("n", "<leader>ka").desc)
    assert.equal("Default B", find_global_map("n", "<leader>kb").desc)
    assert.is_nil(find_global_map("n", "<leader>kc"))

    local ok, err = codex.set_profile("work")
    assert.is_true(ok)
    assert.is_nil(err)

    assert.is_nil(find_global_map("n", "<leader>ka"))
    local work_b = find_global_map("n", "<leader>kb")
    assert.equal("Work B", work_b.desc)
    work_b.callback()
    assert.same({ "work_b" }, calls)
    assert.equal("Work C", find_global_map("n", "<leader>kc").desc)
  end)

  it(
    "snapshots and restores displaced global Lua callbacks and flags without touching buffer-local maps",
    function()
      local orig_calls = 0
      local orig_cb = function()
        orig_calls = orig_calls + 1
        return "orig_expr"
      end
      local local_cb = function()
        return "local_only"
      end
      local buf = vim.api.nvim_create_buf(false, true)
      table.insert(created_bufs, buf)

      vim.keymap.set("n", "<F8>", orig_cb, {
        desc = "Original F8",
        silent = true,
        expr = true,
        nowait = true,
      })
      vim.keymap.set("n", "<F8>", local_cb, {
        buffer = buf,
        desc = "Shadowing buffer-local F8",
      })

      local codex = require("codex")
      codex.setup({
        profiles = {
          default = { auto_start = false },
          work = {
            keymaps = {
              ["<F8>"] = {
                mode = "n",
                action = function() end,
                desc = "Codex Work F8",
              },
            },
          },
        },
        _deps = { providers = stub_providers },
      })

      assert.is_true(codex.set_profile("work"))
      assert.equal("Codex Work F8", find_global_map("n", "<F8>").desc)
      assert.equal("Shadowing buffer-local F8", find_buf_map(buf, "n", "<F8>").desc)

      assert.is_true(codex.set_profile("default"))
      local restored = find_global_map("n", "<F8>")
      assert.is_not_nil(restored)
      assert.equal("Original F8", restored.desc)
      assert.equal(1, restored.silent)
      assert.equal(1, restored.expr)
      assert.equal(1, restored.nowait)
      assert.equal("orig_expr", restored.callback())
      assert.equal(1, orig_calls)

      local local_after = find_buf_map(buf, "n", "<F8>")
      assert.equal("Shadowing buffer-local F8", local_after.desc)
      assert.equal("local_only", local_after.callback())
    end
  )

  it("handles mode aliases, split modes, and canonical LHS equivalence", function()
    local orig_v = function()
      return "orig_v"
    end
    vim.keymap.set("v", "<c-k>", orig_v, { desc = "Original Visual Ctrl-K", silent = true })

    local codex = require("codex")
    codex.setup({
      profiles = {
        default = { auto_start = false },
        work = {
          keymaps = {
            ["<C-K>"] = {
              mode = "x",
              action = function() end,
              desc = "Work X Ctrl-K",
            },
          },
        },
      },
      _deps = { providers = stub_providers },
    })

    assert.is_true(codex.set_profile("work"))
    assert.equal("Work X Ctrl-K", find_global_map("x", "<c-k>").desc)
    -- Select mode 's' retains the untouched half of the split visual map
    assert.equal("Original Visual Ctrl-K", find_global_map("s", "<c-k>").desc)

    assert.is_true(codex.set_profile("default"))
    local restored_x = find_global_map("x", "<c-k>")
    assert.equal("Original Visual Ctrl-K", restored_x.desc)
    assert.equal("orig_v", restored_x.callback())
  end)

  it("skips cleanup for slots replaced by an external component", function()
    local codex = require("codex")
    codex.setup({
      profiles = {
        default = {
          auto_start = false,
          keymaps = {
            ["<F7>"] = { mode = "n", action = function() end, desc = "Codex F7" },
            ["<F8>"] = { mode = "n", action = function() end, desc = "Codex F8" },
          },
        },
        other = {},
      },
      _deps = { providers = stub_providers },
    })

    -- Another plugin overwrites <F7> while default is active
    vim.keymap.set("n", "<F7>", function() end, { desc = "External F7" })

    assert.is_true(codex.set_profile("other"))
    assert.equal("External F7", find_global_map("n", "<F7>").desc)
    assert.is_nil(find_global_map("n", "<F8>"))
  end)

  it("rolls back partial installs and restores outgoing maps on activation failure", function()
    local codex = require("codex")
    codex.setup({
      profiles = {
        default = {
          auto_start = false,
          keymaps = {
            ["<F7>"] = { mode = "n", action = function() end, desc = "Default F7" },
            ["<F8>"] = { mode = "n", action = function() end, desc = "Default F8" },
          },
        },
        bad_overlap = {
          keymaps = {
            ["<leader>ka"] = { mode = "n", action = function() end, desc = "Overlap 1" },
            ["<Space>ka"] = { mode = "n", action = function() end, desc = "Overlap 2" },
          },
        },
        bad_mode = {
          keymaps = {
            ["<F9>"] = { mode = "z", action = function() end, desc = "Bad mode" },
          },
        },
        bad_install = {
          keymaps = {
            ["<F8>"] = { mode = "n", action = function() end, desc = "Incoming F8" },
            ["<F9>"] = { mode = "n", action = function() end, desc = "Incoming F9" },
          },
        },
      },
      _deps = { providers = stub_providers },
    })

    -- 1. Pre-install overlap check rejects without touching default maps
    local ok1, err1 = codex.set_profile("bad_overlap")
    assert.is_false(ok1)
    assert.matches("overlapping global keymap", err1)
    assert.equal("default", codex.get_profile().profile_identifier)
    assert.equal("Default F7", find_global_map("n", "<F7>").desc)

    local mode_ok, mode_err = codex.set_profile("bad_mode")
    assert.is_false(mode_ok)
    assert.matches('invalid keymap mode "z"', mode_err)
    assert.equal("default", codex.get_profile().profile_identifier)
    assert.equal("Default F7", find_global_map("n", "<F7>").desc)

    -- Runtime failure rolls back installed slots without reclaiming an external replacement.
    local external = function() end
    vim.keymap.set("n", "<F8>", external, { desc = "External F8" })
    local real_set = vim.keymap.set
    local calls = 0
    vim.keymap.set = function(...)
      calls = calls + 1
      if calls == 2 then
        error("simulated keymap install failure")
      end
      return real_set(...)
    end

    local ok2, err2 = codex.set_profile("bad_install")
    vim.keymap.set = real_set

    assert.is_false(ok2)
    assert.matches("simulated keymap install failure", err2)
    assert.equal("default", codex.get_profile().profile_identifier)
    assert.equal(external, find_global_map("n", "<F8>").callback)
    assert.is_nil(find_global_map("n", "<F9>"))
    assert.equal("Default F7", find_global_map("n", "<F7>").desc)
  end)

  it("does not tear down the selected session from another profile's terminal map", function()
    local codex = require("codex")
    codex.setup({
      profiles = {
        default = {
          terminal = { keymaps = { ["<C-q>"] = { mode = "t", action = builtins.teardown } } },
        },
        work = {},
      },
      _deps = { providers = stub_providers },
    })
    codex.session.open(false)
    local teardown = find_buf_map(created_bufs[1], "t", "<C-q>").callback
    teardown()
    assert.is_true(codex.set_profile("work"))
    codex.session.open(false)
    teardown()
    local drained = false
    vim.schedule(function()
      drained = true
    end)
    assert.is_true(vim.wait(1000, function()
      return drained
    end))
    assert.is_true(codex.session.is_running())
    assert.is_true(codex.set_profile("default"))
    assert.is_true(codex.session.is_running())
  end)

  it(
    "cleans up global maps on repeated setup and deactivate while keeping terminal-local maps",
    function()
      vim.keymap.set("n", "<F7>", function() end, { desc = "Preexisting F7" })

      local codex = require("codex")
      codex.setup({
        profiles = {
          default = {
            auto_start = false,
            terminal = {
              keymaps = {
                ["<C-q>"] = { mode = "t", action = builtins.teardown },
              },
            },
            keymaps = {
              ["<F7>"] = { mode = "n", action = function() end, desc = "Setup1 F7" },
              ["<F8>"] = { mode = "n", action = function() end, desc = "Setup1 F8" },
            },
          },
          work = {},
        },
        _deps = { providers = stub_providers },
      })

      codex.session.open(false)
      local term_buf = stub_provider.get_bufnr(codex.session)
      -- Retrieve bufnr from buf list since created_bufs tracks it
      local buf = created_bufs[#created_bufs]
      assert.is_nil(term_buf)
      assert.is_not_nil(find_buf_map(buf, "t", "<C-q>"))

      assert.has_error(function()
        codex.setup({ profiles = { default = {}, work = { auto_start = "yes" } } })
      end, "codex: profiles.work.auto_start: expected boolean, got string")
      assert.equal("default", codex.get_profile().profile_identifier)
      assert.equal("Setup1 F7", find_global_map("n", "<F7>").desc)
      assert.equal("Setup1 F8", find_global_map("n", "<F8>").desc)

      -- Switching profiles leaves terminal-local map untouched
      assert.is_true(codex.set_profile("work"))
      assert.is_not_nil(find_buf_map(buf, "t", "<C-q>"))
      assert.equal("Preexisting F7", find_global_map("n", "<F7>").desc)
      assert.is_nil(find_global_map("n", "<F8>"))

      -- Repeated setup removes prior setup maps and installs new default maps
      codex.setup({
        profiles = {
          default = {
            auto_start = false,
            keymaps = {
              ["<F9>"] = { mode = "n", action = function() end, desc = "Setup2 F9" },
            },
          },
        },
        _deps = { providers = stub_providers },
      })
      assert.equal("Preexisting F7", find_global_map("n", "<F7>").desc)
      assert.is_nil(find_global_map("n", "<F8>"))
      assert.equal("Setup2 F9", find_global_map("n", "<F9>").desc)

      -- Deactivate removes Setup2 F9
      codex.deactivate()
      assert.is_nil(find_global_map("n", "<F9>"))
    end
  )
end)
