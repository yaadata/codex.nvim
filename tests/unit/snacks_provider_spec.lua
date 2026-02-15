local function with_stubbed_vim_api(run)
  local original_create_autocmd = vim.api.nvim_create_autocmd
  local original_keymap_set = vim.keymap.set
  local original_cmd = vim.cmd
  local autocmds = {}
  local keymap_set_calls = {}
  local cmd_calls = {}

  vim.api.nvim_create_autocmd = function(event, spec)
    table.insert(autocmds, { event = event, spec = spec })
    return #autocmds
  end
  vim.keymap.set = function(mode, lhs, rhs, opts)
    table.insert(keymap_set_calls, {
      mode = mode,
      lhs = lhs,
      rhs = rhs,
      opts = opts,
    })
  end
  vim.cmd = function(cmd)
    table.insert(cmd_calls, cmd)
  end

  local ok, err = pcall(run, autocmds, keymap_set_calls, cmd_calls)
  vim.api.nvim_create_autocmd = original_create_autocmd
  vim.keymap.set = original_keymap_set
  vim.cmd = original_cmd

  if not ok then
    error(err)
  end
end

local function with_stubbed_send_env(run)
  local original_buf_is_valid = vim.api.nvim_buf_is_valid
  local original_buf_get_var = vim.api.nvim_buf_get_var
  local original_get_option_value = vim.api.nvim_get_option_value
  local original_chansend = vim.fn.chansend
  local chansend_calls = {}
  local buf_valid = {}
  local buf_vars = {}
  local buf_channels = {}

  vim.api.nvim_buf_is_valid = function(bufnr)
    return buf_valid[bufnr] == true
  end
  vim.api.nvim_buf_get_var = function(bufnr, name)
    local vars = buf_vars[bufnr] or {}
    local value = vars[name]
    if value == nil then
      error("missing buffer var")
    end
    return value
  end
  vim.api.nvim_get_option_value = function(name, opts)
    if name ~= "channel" then
      error("unsupported option")
    end
    return buf_channels[opts.buf] or 0
  end
  vim.fn.chansend = function(jobid, text)
    table.insert(chansend_calls, { jobid = jobid, text = text })
  end

  local ok, err = pcall(run, {
    chansend_calls = chansend_calls,
    buf_valid = buf_valid,
    buf_vars = buf_vars,
    buf_channels = buf_channels,
  })

  vim.api.nvim_buf_is_valid = original_buf_is_valid
  vim.api.nvim_buf_get_var = original_buf_get_var
  vim.api.nvim_get_option_value = original_get_option_value
  vim.fn.chansend = original_chansend

  if not ok then
    error(err)
  end
end

describe("codex.providers.snacks", function()
  before_each(function()
    package.loaded["snacks"] = nil
    package.loaded["codex.providers.snacks"] = nil
  end)

  it("registers a TermClose autocmd when on_exit callback is provided", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls)
      local terminal = { buf = 42 }
      package.loaded["snacks"] = {
        terminal = function()
          return terminal
        end,
      }

      local provider = require("codex.providers.snacks")
      local exited = {}
      local handle = provider.open(
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } },
        true,
        function(cb_handle)
          table.insert(exited, cb_handle)
        end
      )

      assert.equals(1, #autocmds)
      assert.equals("TermClose", autocmds[1].event)
      assert.equals(42, autocmds[1].spec.buffer)
      assert.is_true(autocmds[1].spec.once)
      assert.equals(1, #keymap_set_calls)
      assert.equals("t", keymap_set_calls[1].mode)
      assert.equals("<C-c>", keymap_set_calls[1].lhs)
      assert.is_function(keymap_set_calls[1].rhs)
      assert.equals(42, keymap_set_calls[1].opts.buffer)
      assert.is_true(keymap_set_calls[1].opts.silent)
      assert.is_true(keymap_set_calls[1].opts.nowait)
      assert.equals("Codex: Toggle terminal", keymap_set_calls[1].opts.desc)

      autocmds[1].spec.callback()
      assert.equals(1, #exited)
      assert.same(handle, exited[1])
    end)
  end)

  it("registers directional split navigation keymaps for vsplit", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "vsplit",
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      assert.equals(5, #keymap_set_calls)
      assert.equals("<C-h>", keymap_set_calls[2].lhs)
      assert.equals("<C-\\><C-n><C-w>h", keymap_set_calls[2].rhs)
      assert.equals("<C-j>", keymap_set_calls[3].lhs)
      assert.equals("<C-\\><C-n><C-w>j", keymap_set_calls[3].rhs)
      assert.equals("<C-k>", keymap_set_calls[4].lhs)
      assert.equals("<C-\\><C-n><C-w>k", keymap_set_calls[4].rhs)
      assert.equals("<C-l>", keymap_set_calls[5].lhs)
      assert.equals("<C-\\><C-n><C-w>l", keymap_set_calls[5].rhs)
    end)
  end)

  it("does not register directional split navigation keymaps for float", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "float",
          float = {
            border = "rounded",
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      assert.equals(1, #keymap_set_calls)
      assert.equals("<C-c>", keymap_set_calls[1].lhs)

      local forbidden = { ["<C-h>"] = true, ["<C-j>"] = true, ["<C-k>"] = true, ["<C-l>"] = true }
      for _, map in ipairs(keymap_set_calls) do
        assert.is_nil(forbidden[map.lhs])
      end
    end)
  end)

  it("registers configured terminal toggle and close keymaps", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          keymaps = {
            toggle = "<C-t>",
            close = "<C-x>",
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      assert.equals(2, #keymap_set_calls)
      assert.equals("t", keymap_set_calls[1].mode)
      assert.equals("<C-t>", keymap_set_calls[1].lhs)
      assert.equals("Codex: Toggle terminal", keymap_set_calls[1].opts.desc)
      assert.equals("t", keymap_set_calls[2].mode)
      assert.equals("<C-x>", keymap_set_calls[2].lhs)
      assert.equals("Codex: Close terminal", keymap_set_calls[2].opts.desc)
    end)
  end)

  it("uses configured directional split navigation keymaps", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "vsplit",
          vsplit = { side = "right", size_pct = 40 },
          keymaps = {
            nav = {
              left = "<A-h>",
              down = "<A-j>",
              up = "<A-k>",
              right = "<A-l>",
            },
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      assert.equals(5, #keymap_set_calls)
      assert.equals("<A-h>", keymap_set_calls[2].lhs)
      assert.equals("<A-j>", keymap_set_calls[3].lhs)
      assert.equals("<A-k>", keymap_set_calls[4].lhs)
      assert.equals("<A-l>", keymap_set_calls[5].lhs)
    end)
  end)

  it("allows disabling directional split navigation keymaps", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "vsplit",
          vsplit = { side = "right", size_pct = 40 },
          keymaps = {
            nav = false,
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      assert.equals(1, #keymap_set_calls)
      assert.equals("<C-c>", keymap_set_calls[1].lhs)
    end)
  end)

  it("close keymap defers via vim.schedule", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local scheduled = {}
      local original_schedule = vim.schedule
      vim.schedule = function(cb)
        table.insert(scheduled, cb)
      end

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          keymaps = {
            toggle = "<C-t>",
            close = "<C-x>",
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      local close_map = keymap_set_calls[2]
      close_map.rhs()

      assert.equals(1, #scheduled)
      assert.is_function(scheduled[1])

      vim.schedule = original_schedule
    end)
  end)

  it("does not register TermClose autocmd when on_exit callback is missing", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open(
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } },
        true,
        nil
      )

      assert.equals(0, #autocmds)
      assert.equals(1, #keymap_set_calls)
    end)
  end)

  it("does not register terminal keymap when snacks terminal has no numeric buffer", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return {}
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open(
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } },
        true,
        nil
      )

      assert.equals(0, #keymap_set_calls)
    end)
  end)

  it("focuses snacks terminal and enters insert mode", function()
    with_stubbed_vim_api(function(_, _, cmd_calls)
      local shown = 0
      local terminal = {
        show = function()
          shown = shown + 1
        end,
      }

      local provider = require("codex.providers.snacks")
      local ok, err = provider.focus({ terminal = terminal })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, shown)
      assert.same({ "startinsert" }, cmd_calls)
    end)
  end)

  it("sends text using terminal.jobid when available", function()
    with_stubbed_send_env(function(state)
      local provider = require("codex.providers.snacks")
      local ok, err = provider.send({ terminal = { jobid = 77 } }, "hello")

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, #state.chansend_calls)
      assert.same({ jobid = 77, text = "hello" }, state.chansend_calls[1])
    end)
  end)

  it("falls back to b:terminal_job_id when terminal.jobid is missing", function()
    with_stubbed_send_env(function(state)
      state.buf_valid[42] = true
      state.buf_vars[42] = { terminal_job_id = 88 }

      local provider = require("codex.providers.snacks")
      local ok, err = provider.send({ terminal = { buf = 42 } }, "hello")

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, #state.chansend_calls)
      assert.same({ jobid = 88, text = "hello" }, state.chansend_calls[1])
    end)
  end)

  it("uses terminal channel option when available", function()
    with_stubbed_send_env(function(state)
      state.buf_valid[42] = true
      state.buf_channels[42] = 99

      local provider = require("codex.providers.snacks")
      local ok, err = provider.send({ terminal = { buf = 42 } }, "hello")

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, #state.chansend_calls)
      assert.same({ jobid = 99, text = "hello" }, state.chansend_calls[1])
    end)
  end)

  it("reports alive only when terminal has an active job channel", function()
    with_stubbed_send_env(function(state)
      state.buf_valid[42] = true
      local provider = require("codex.providers.snacks")
      assert.is_false(provider.is_alive({ terminal = { buf = 42 } }))

      state.buf_vars[42] = { terminal_job_id = 33 }
      assert.is_true(provider.is_alive({ terminal = { buf = 42 } }))
    end)
  end)

  it("returns an error when no terminal job id is available", function()
    with_stubbed_send_env(function(state)
      state.buf_valid[42] = true
      state.buf_vars[42] = {}

      local provider = require("codex.providers.snacks")
      local ok, err = provider.send({ terminal = { buf = 42 } }, "hello")

      assert.is_false(ok)
      assert.equals("terminal has no job", err)
      assert.equals(0, #state.chansend_calls)
    end)
  end)

  it("toggle opens a new terminal when the existing terminal has no job", function()
    with_stubbed_vim_api(function()
      local stale_toggle_calls = 0
      local stale_terminal = {
        toggle = function()
          stale_toggle_calls = stale_toggle_calls + 1
        end,
      }
      local fresh_terminal = { buf = 55 }

      package.loaded["snacks"] = {
        terminal = function()
          return fresh_terminal
        end,
      }

      local provider = require("codex.providers.snacks")
      local handle = provider.toggle(
        { terminal = stale_terminal },
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } }
      )

      assert.equals(0, stale_toggle_calls)
      assert.same(fresh_terminal, handle.terminal)
    end)
  end)

  it("passes command and options separately to snacks.terminal", function()
    with_stubbed_vim_api(function()
      local captured_cmd = nil
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(cmd, opts)
          captured_cmd = cmd
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", { "--foo", "bar" }, { CODEX_TEST = "1" }, {
        cwd = "/tmp/work",
        terminal = {
          startup = { grace_ms = 0 },
          provider_opts = {
            snacks = {
              win = { position = "float" },
            },
          },
        },
      }, false, nil)

      assert.equals("codex --foo bar", captured_cmd)
      assert.equals("/tmp/work", captured_opts.cwd)
      assert.equals("1", captured_opts.env.CODEX_TEST)
      assert.is_true(captured_opts.interactive)
      assert.is_false(captured_opts.auto_close)
      assert.equals("float", captured_opts.win.position)
    end)
  end)

  it("passes auto_close=true when configured", function()
    with_stubbed_vim_api(function()
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          auto_close = true,
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.is_true(captured_opts.auto_close)
    end)
  end)

  it("passes vsplit config to snacks when window is vsplit", function()
    with_stubbed_vim_api(function()
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "vsplit",
          vsplit = {
            side = "left",
            size_pct = 40,
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.equals("left", captured_opts.win.position)
      assert.equals(0.4, captured_opts.win.width)
    end)
  end)

  it("passes hsplit config to snacks when window is hsplit", function()
    with_stubbed_vim_api(function()
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "hsplit",
          hsplit = {
            side = "bottom",
            size_pct = 30,
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.equals("bottom", captured_opts.win.position)
      assert.equals(0.3, captured_opts.win.height)
    end)
  end)

  it("passes float border config to snacks when window is float", function()
    with_stubbed_vim_api(function()
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "float",
          float = {
            border = "rounded",
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.equals("float", captured_opts.win.position)
      assert.equals("rounded", captured_opts.win.border)
    end)
  end)

  it("handles missing terminal.startup without error", function()
    with_stubbed_vim_api(function()
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      local handle = provider.open("codex", {}, {}, {
        terminal = {
          provider_opts = {},
        },
      }, false, nil)

      assert.is_not_nil(handle)
      assert.is_number(handle.ready_at_ms)

      local uv = vim.uv or vim.loop
      local expected = (uv and type(uv.now) == "function") and uv.now() or 0
      assert.equals(expected, handle.ready_at_ms)
    end)
  end)

  it("uses default vsplit win config when vsplit sub-table is nil", function()
    with_stubbed_vim_api(function()
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "vsplit",
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.equals("right", captured_opts.win.position)
      assert.equals(0.4, captured_opts.win.width)
    end)
  end)

  it("uses default hsplit win config when hsplit sub-table is nil", function()
    with_stubbed_vim_api(function()
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "hsplit",
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.equals("bottom", captured_opts.win.position)
      assert.equals(0.3, captured_opts.win.height)
    end)
  end)

  it("uses default float win config when float sub-table is nil", function()
    with_stubbed_vim_api(function()
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          window = "float",
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.equals("float", captured_opts.win.position)
      assert.equals("rounded", captured_opts.win.border)
    end)
  end)
end)
