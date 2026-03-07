local builtins = require("codex.keymaps").builtins

local function default_terminal_keymaps()
  return {
    ["<C-c>"] = { mode = "t", action = builtins.toggle },
    ["<M-BS>"] = { mode = "t", action = builtins.clear_input },
    ["<C-h>"] = { mode = "t", action = builtins.nav_left },
    ["<C-j>"] = { mode = "t", action = builtins.nav_down },
    ["<C-k>"] = { mode = "t", action = builtins.nav_up },
    ["<C-l>"] = { mode = "t", action = builtins.nav_right },
  }
end

local function find_keymap(calls, lhs)
  for _, call in ipairs(calls) do
    if call.lhs == lhs then
      return call
    end
  end
  return nil
end

local function with_stubbed_vim_api(run)
  local original_create_autocmd = vim.api.nvim_create_autocmd
  local original_get_current_buf = vim.api.nvim_get_current_buf
  local original_set_current_win = vim.api.nvim_set_current_win
  local original_win_is_valid = vim.api.nvim_win_is_valid
  local original_keymap_set = vim.keymap.set
  local original_cmd = vim.cmd
  local autocmds = {}
  local keymap_set_calls = {}
  local cmd_calls = {}
  local state = {
    current_buf = 1,
    current_win = 1,
    win_buf = { [1] = 1 },
    win_valid = { [1] = true },
    set_current_win_calls = {},
  }

  vim.api.nvim_create_autocmd = function(event, spec)
    table.insert(autocmds, { event = event, spec = spec })
    return #autocmds
  end
  vim.api.nvim_get_current_buf = function()
    return state.current_buf
  end
  vim.api.nvim_set_current_win = function(winid)
    table.insert(state.set_current_win_calls, winid)
    state.current_win = winid
    if state.win_buf[winid] then
      state.current_buf = state.win_buf[winid]
    end
  end
  vim.api.nvim_win_is_valid = function(winid)
    return state.win_valid[winid] == true
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

  local ok, err = pcall(run, autocmds, keymap_set_calls, cmd_calls, state)
  vim.api.nvim_create_autocmd = original_create_autocmd
  vim.api.nvim_get_current_buf = original_get_current_buf
  vim.api.nvim_set_current_win = original_set_current_win
  vim.api.nvim_win_is_valid = original_win_is_valid
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
        {
          terminal = {
            keymaps = default_terminal_keymaps(),
            startup = { grace_ms = 0 },
            provider_opts = {},
          },
        },
        true,
        function(cb_handle)
          table.insert(exited, cb_handle)
        end
      )

      assert.equals(1, #autocmds)
      assert.equals("TermClose", autocmds[1].event)
      assert.equals(42, autocmds[1].spec.buffer)
      assert.is_true(autocmds[1].spec.once)
      assert.equals(6, #keymap_set_calls)
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-c>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<M-BS>"))

      autocmds[1].spec.callback()
      assert.equals(1, #exited)
      assert.same(handle, exited[1])
    end)
  end)

  it("does not register terminal keymaps by default", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
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

      assert.equals(0, #keymap_set_calls)
    end)
  end)

  it("registers configured builtin terminal keymaps", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          keymaps = default_terminal_keymaps(),
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      assert.equals(6, #keymap_set_calls)
      local toggle_map = find_keymap(keymap_set_calls, "<C-c>")
      local clear_map = find_keymap(keymap_set_calls, "<M-BS>")
      assert.is_not_nil(toggle_map)
      assert.equals("Codex: Toggle terminal", toggle_map.opts.desc)
      assert.is_not_nil(clear_map)
      assert.equals("Codex: Clear input", clear_map.opts.desc)
    end)
  end)

  it("registers directional navigation keymaps even for float win.position", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          provider_opts = {
            snacks = {
              win = { position = "float", border = "rounded" },
            },
          },
          keymaps = {
            ["<C-h>"] = { mode = "t", action = builtins.nav_left },
            ["<C-j>"] = { mode = "t", action = builtins.nav_down },
            ["<C-k>"] = { mode = "t", action = builtins.nav_up },
            ["<C-l>"] = { mode = "t", action = builtins.nav_right },
          },
          startup = { grace_ms = 0 },
        },
      }, true, nil)

      assert.equals(4, #keymap_set_calls)
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-h>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-j>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-k>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-l>"))
    end)
  end)

  it("registers custom terminal keymap keys for builtin actions", function()
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
            ["<C-t>"] = { mode = "t", action = builtins.toggle },
            ["<C-x>"] = { mode = "t", action = builtins.close },
            ["<M-BS>"] = { mode = "t", action = builtins.clear_input },
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      assert.equals(3, #keymap_set_calls)
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-t>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-x>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<M-BS>"))
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
            ["<C-x>"] = { mode = "t", action = builtins.close },
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      local close_map = find_keymap(keymap_set_calls, "<C-x>")
      close_map.rhs()

      assert.equals(1, #scheduled)
      assert.is_function(scheduled[1])

      vim.schedule = original_schedule
    end)
  end)

  it("clear input keymap calls codex.clear_input directly", function()
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
      local clear_input_calls = 0
      package.loaded["codex"] = {
        clear_input = function()
          clear_input_calls = clear_input_calls + 1
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          keymaps = {
            ["<M-BS>"] = { mode = "t", action = builtins.clear_input },
          },
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      local clear_map = find_keymap(keymap_set_calls, "<M-BS>")
      clear_map.rhs()

      assert.equals(1, clear_input_calls)
      assert.equals(0, #scheduled)

      vim.schedule = original_schedule
      package.loaded["codex"] = nil
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
      assert.equals(0, #keymap_set_calls)
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
    with_stubbed_vim_api(function(_, _, cmd_calls, state)
      local shown = 0
      local focused = 0
      local terminal = {
        buf = 42,
        show = function()
          shown = shown + 1
        end,
        focus = function()
          focused = focused + 1
          state.current_buf = 42
        end,
      }

      local provider = require("codex.providers.snacks")
      local ok, err = provider.focus({ terminal = terminal })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, shown)
      assert.equals(1, focused)
      assert.same({ "startinsert" }, cmd_calls)
    end)
  end)

  it("returns an error when snacks terminal focus does not land on terminal buffer", function()
    with_stubbed_vim_api(function(_, _, cmd_calls, state)
      local terminal = {
        buf = 42,
        show = function() end,
        focus = function()
          state.current_buf = 1
        end,
      }

      local provider = require("codex.providers.snacks")
      local ok, err = provider.focus({ terminal = terminal })

      assert.is_false(ok)
      assert.equals("terminal window not focused", err)
      assert.equals(0, #cmd_calls)
    end)
  end)

  it("uses snacks terminal window fallback to recover focus before insert", function()
    with_stubbed_vim_api(function(_, _, cmd_calls, state)
      state.current_buf = 1
      state.win_valid[9] = true
      state.win_buf[9] = 42

      local terminal = {
        buf = 42,
        win = 9,
        show = function() end,
      }

      local provider = require("codex.providers.snacks")
      local ok, err = provider.focus({ terminal = terminal })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.same({ 9 }, state.set_current_win_calls)
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
        launch = {
          cwd = "/tmp/work",
        },
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

  it("disables snacks auto_close even when codex auto_close=true", function()
    with_stubbed_vim_api(function(autocmds)
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

      assert.is_false(captured_opts.auto_close)
      assert.equals(1, #autocmds)
      assert.equals("TermClose", autocmds[1].event)
    end)
  end)

  it("runs on_exit and closes terminal on TermClose when auto_close=true", function()
    with_stubbed_vim_api(function(autocmds, _, cmd_calls)
      local close_calls = 0
      local terminal = {
        buf = 42,
        close = function()
          close_calls = close_calls + 1
        end,
      }
      package.loaded["snacks"] = {
        terminal = function()
          return terminal
        end,
      }

      local scheduled = {}
      local original_schedule = vim.schedule
      vim.schedule = function(cb)
        table.insert(scheduled, cb)
      end

      local on_exit_calls = 0
      local provider = require("codex.providers.snacks")
      provider.open(
        "codex",
        {},
        {},
        {
          terminal = {
            auto_close = true,
            startup = { grace_ms = 0 },
            provider_opts = {},
          },
        },
        false,
        function()
          on_exit_calls = on_exit_calls + 1
        end
      )

      assert.equals(1, #autocmds)
      autocmds[1].spec.callback()

      assert.equals(1, on_exit_calls)
      assert.equals(1, #scheduled)
      assert.equals(0, close_calls)
      assert.equals(0, #cmd_calls)

      scheduled[1]()

      assert.equals(1, close_calls)
      assert.same({ "checktime" }, cmd_calls)

      vim.schedule = original_schedule
    end)
  end)

  it("passes snacks win options through provider_opts", function()
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
          startup = { grace_ms = 0 },
          provider_opts = {
            snacks = {
              win = {
                position = "left",
                width = 0.4,
              },
            },
          },
        },
      }, false, nil)

      assert.equals("left", captured_opts.win.position)
      assert.equals(0.4, captured_opts.win.width)
    end)
  end)

  it("passes snacks horizontal win options through provider_opts", function()
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
          startup = { grace_ms = 0 },
          provider_opts = {
            snacks = {
              win = {
                position = "bottom",
                height = 0.3,
              },
            },
          },
        },
      }, false, nil)

      assert.equals("bottom", captured_opts.win.position)
      assert.equals(0.3, captured_opts.win.height)
    end)
  end)

  it("passes snacks float win options through provider_opts", function()
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
          startup = { grace_ms = 0 },
          provider_opts = {
            snacks = {
              win = {
                position = "float",
                border = "rounded",
              },
            },
          },
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

  it("does not set opts.win when snacks win options are omitted", function()
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
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      assert.is_nil(captured_opts.win)
    end)
  end)
end)
