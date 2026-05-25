local stub = require("luassert.stub")
local builtins = require("codex.keymaps").builtins

-- Register luassert cleanup, then keep a plain function for type checks.
local function stub_real_function(target, key, replacement)
  stub(target, key)
  target[key] = replacement
end

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
  local original_get_option_value = vim.api.nvim_get_option_value
  local autocmds = {}
  local keymap_set_calls = {}
  local cmd_calls = {}
  local state = {
    current_buf = 1,
    current_win = 1,
    win_buf = { [1] = 1 },
    win_valid = { [1] = true },
    buf_valid = { [1] = true },
    buf_names = {},
    buf_vars = {},
    buf_channels = {},
    jobstop_calls = {},
    set_current_win_calls = {},
  }

  stub_real_function(vim.api, "nvim_create_autocmd", function(event, spec)
    table.insert(autocmds, { event = event, spec = spec })
    return #autocmds
  end)
  stub(vim.api, "nvim_get_current_buf", function()
    return state.current_buf
  end)
  stub_real_function(vim.api, "nvim_list_bufs", function()
    local bufs = {}
    for bufnr, valid in pairs(state.buf_valid) do
      if valid then
        table.insert(bufs, bufnr)
      end
    end
    table.sort(bufs)
    return bufs
  end)
  stub_real_function(vim.api, "nvim_list_wins", function()
    local wins = {}
    for winid, valid in pairs(state.win_valid) do
      if valid then
        table.insert(wins, winid)
      end
    end
    table.sort(wins)
    return wins
  end)
  stub_real_function(vim.api, "nvim_win_get_buf", function(winid)
    return state.win_buf[winid]
  end)
  stub(vim.api, "nvim_set_current_win", function(winid)
    table.insert(state.set_current_win_calls, winid)
    state.current_win = winid
    if state.win_buf[winid] then
      state.current_buf = state.win_buf[winid]
    end
  end)
  stub(vim.api, "nvim_win_is_valid", function(winid)
    return state.win_valid[winid] == true
  end)
  stub(vim.api, "nvim_win_close", function(winid)
    state.win_valid[winid] = false
  end)
  stub_real_function(vim.api, "nvim_buf_is_valid", function(bufnr)
    return state.buf_valid[bufnr] == true
  end)
  stub(vim.api, "nvim_buf_delete", function(bufnr)
    state.buf_valid[bufnr] = false
  end)
  stub_real_function(vim.api, "nvim_buf_get_name", function(bufnr)
    return state.buf_names[bufnr] or ""
  end)
  stub_real_function(vim.api, "nvim_buf_get_var", function(bufnr, name)
    local vars = state.buf_vars[bufnr] or {}
    local value = vars[name]
    if value == nil then
      error("missing buffer var")
    end
    return value
  end)
  stub_real_function(vim.api, "nvim_buf_set_var", function(bufnr, name, value)
    state.buf_vars[bufnr] = state.buf_vars[bufnr] or {}
    state.buf_vars[bufnr][name] = value
  end)
  stub(vim.api, "nvim_get_option_value", function(name, opts)
    if name ~= "channel" then
      if type(original_get_option_value) == "function" then
        return original_get_option_value(name, opts)
      end
      return 0
    end
    return state.buf_channels[opts.buf] or 0
  end)
  stub(vim.keymap, "set", function(mode, lhs, rhs, opts)
    table.insert(keymap_set_calls, {
      mode = mode,
      lhs = lhs,
      rhs = rhs,
      opts = opts,
    })
  end)
  stub(vim, "cmd", function(cmd)
    table.insert(cmd_calls, cmd)
  end)
  stub(vim.fn, "jobstop", function(jobid)
    table.insert(state.jobstop_calls, jobid)
  end)

  run(autocmds, keymap_set_calls, cmd_calls, state)
end

local function with_stubbed_send_env(run)
  local chansend_calls = {}
  local buf_valid = {}
  local buf_vars = {}
  local buf_channels = {}

  stub_real_function(vim.api, "nvim_buf_is_valid", function(bufnr)
    return buf_valid[bufnr] == true
  end)
  stub_real_function(vim.api, "nvim_buf_get_var", function(bufnr, name)
    local vars = buf_vars[bufnr] or {}
    local value = vars[name]
    if value == nil then
      error("missing buffer var")
    end
    return value
  end)
  stub(vim.api, "nvim_get_option_value", function(name, opts)
    if name ~= "channel" then
      error("unsupported option")
    end
    return buf_channels[opts.buf] or 0
  end)
  stub(vim.fn, "chansend", function(jobid, text)
    table.insert(chansend_calls, { jobid = jobid, text = text })
  end)

  run({
    chansend_calls = chansend_calls,
    buf_valid = buf_valid,
    buf_vars = buf_vars,
    buf_channels = buf_channels,
  })
end

describe("codex.providers.snacks", function()
  local stub_snapshot

  before_each(function()
    stub_snapshot = assert:snapshot()
    package.loaded["snacks"] = nil
    package.loaded["codex"] = nil
    package.loaded["codex.providers.snacks"] = nil
  end)

  after_each(function()
    stub_snapshot:revert()
    package.loaded["snacks"] = nil
    package.loaded["codex"] = nil
  end)

  it("registers a TermClose autocmd and keymaps when on_exit callback is provided", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls)
      -- ========= [A]rrange =========
      local terminal = { buf = 42 }
      package.loaded["snacks"] = {
        terminal = function()
          return terminal
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, {
        terminal = {
          keymaps = default_terminal_keymaps(),
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, function() end)

      -- ========= [A]ssert  =========
      assert.equals(1, #autocmds)
      assert.equals("TermClose", autocmds[1].event)
      assert.equals(42, autocmds[1].spec.buffer)
      assert.is_true(autocmds[1].spec.once)
      assert.equals(6, #keymap_set_calls)
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-c>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<M-BS>"))
    end)
  end)

  it("fires on_exit callback on TermClose", function()
    with_stubbed_vim_api(function(autocmds)
      -- ========= [A]rrange =========
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

      -- ========= [A]ct     =========
      autocmds[1].spec.callback()

      -- ========= [A]ssert  =========
      assert.equals(1, #exited)
      assert.same(handle, exited[1])
    end)
  end)

  it("does not register terminal keymaps by default", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      provider.open(
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } },
        true,
        nil
      )

      -- ========= [A]ssert  =========
      assert.equals(0, #keymap_set_calls)
    end)
  end)

  it("registers configured builtin terminal keymaps", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, {
        terminal = {
          keymaps = default_terminal_keymaps(),
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, true, nil)

      -- ========= [A]ssert  =========
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
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
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

      -- ========= [A]ssert  =========
      assert.equals(4, #keymap_set_calls)
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-h>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-j>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-k>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-l>"))
    end)
  end)

  it("registers custom terminal keymap keys for builtin actions", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
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

      -- ========= [A]ssert  =========
      assert.equals(3, #keymap_set_calls)
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-t>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-x>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<M-BS>"))
    end)
  end)

  it("close keymap defers via vim.schedule", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local scheduled = {}
      stub(vim, "schedule", function(cb)
        table.insert(scheduled, cb)
      end)
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

      -- ========= [A]ct     =========
      close_map.rhs()

      -- ========= [A]ssert  =========
      assert.equals(1, #scheduled)
      assert.is_function(scheduled[1])
    end)
  end)

  it("clear input keymap calls codex.clear_input directly", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local scheduled = {}
      stub(vim, "schedule", function(cb)
        table.insert(scheduled, cb)
      end)
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

      -- ========= [A]ct     =========
      clear_map.rhs()

      -- ========= [A]ssert  =========
      assert.equals(1, clear_input_calls)
      assert.equals(0, #scheduled)
    end)
  end)

  it("does not register TermClose autocmd when on_exit callback is missing", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls)
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      provider.open(
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } },
        true,
        nil
      )

      -- ========= [A]ssert  =========
      assert.equals(0, #autocmds)
      assert.equals(0, #keymap_set_calls)
    end)
  end)

  it("does not register terminal keymap when snacks terminal has no numeric buffer", function()
    with_stubbed_vim_api(function(_, keymap_set_calls)
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return {}
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      provider.open(
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } },
        true,
        nil
      )

      -- ========= [A]ssert  =========
      assert.equals(0, #keymap_set_calls)
    end)
  end)

  it("focuses snacks terminal and enters insert mode", function()
    with_stubbed_vim_api(function(_, _, cmd_calls, state)
      -- ========= [A]rrange =========
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

      -- ========= [A]ct     =========
      local ok, err = provider.focus({ terminal = terminal })

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, shown)
      assert.equals(1, focused)
      assert.same({ "startinsert" }, cmd_calls)
    end)
  end)

  it("returns an error when snacks terminal focus does not land on terminal buffer", function()
    with_stubbed_vim_api(function(_, _, cmd_calls, state)
      -- ========= [A]rrange =========
      local terminal = {
        buf = 42,
        show = function() end,
        focus = function()
          state.current_buf = 1
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local ok, err = provider.focus({ terminal = terminal })

      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.equals("terminal window not focused", err)
      assert.equals(0, #cmd_calls)
    end)
  end)

  it("uses snacks terminal window fallback to recover focus before insert", function()
    with_stubbed_vim_api(function(_, _, cmd_calls, state)
      -- ========= [A]rrange =========
      state.current_buf = 1
      state.win_valid[9] = true
      state.win_buf[9] = 42
      local terminal = {
        buf = 42,
        win = 9,
        show = function() end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local ok, err = provider.focus({ terminal = terminal })

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.same({ 9 }, state.set_current_win_calls)
      assert.same({ "startinsert" }, cmd_calls)
    end)
  end)

  it("sends text using terminal.jobid when available", function()
    with_stubbed_send_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local ok, err = provider.send({ terminal = { jobid = 77 } }, "hello")

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, #state.chansend_calls)
      assert.same({ jobid = 77, text = "hello" }, state.chansend_calls[1])
    end)
  end)

  it("falls back to b:terminal_job_id when terminal.jobid is missing", function()
    with_stubbed_send_env(function(state)
      -- ========= [A]rrange =========
      state.buf_valid[42] = true
      state.buf_vars[42] = { terminal_job_id = 88 }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local ok, err = provider.send({ terminal = { buf = 42 } }, "hello")

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, #state.chansend_calls)
      assert.same({ jobid = 88, text = "hello" }, state.chansend_calls[1])
    end)
  end)

  it("uses terminal channel option when available", function()
    with_stubbed_send_env(function(state)
      -- ========= [A]rrange =========
      state.buf_valid[42] = true
      state.buf_channels[42] = 99
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local ok, err = provider.send({ terminal = { buf = 42 } }, "hello")

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, #state.chansend_calls)
      assert.same({ jobid = 99, text = "hello" }, state.chansend_calls[1])
    end)
  end)

  it("reports not alive when terminal has no active job channel", function()
    with_stubbed_send_env(function(state)
      -- ========= [A]rrange =========
      state.buf_valid[42] = true
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local alive = provider.is_alive({ terminal = { buf = 42 } })

      -- ========= [A]ssert  =========
      assert.is_false(alive)
    end)
  end)

  it("reports alive when terminal has an active job channel", function()
    with_stubbed_send_env(function(state)
      -- ========= [A]rrange =========
      state.buf_valid[42] = true
      state.buf_vars[42] = { terminal_job_id = 33 }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local alive = provider.is_alive({ terminal = { buf = 42 } })

      -- ========= [A]ssert  =========
      assert.is_true(alive)
    end)
  end)

  it("returns an error when no terminal job id is available", function()
    with_stubbed_send_env(function(state)
      -- ========= [A]rrange =========
      state.buf_valid[42] = true
      state.buf_vars[42] = {}
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local ok, err = provider.send({ terminal = { buf = 42 } }, "hello")

      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.equals("terminal has no job", err)
      assert.equals(0, #state.chansend_calls)
    end)
  end)

  it("toggle opens a new terminal when the existing terminal has no job", function()
    with_stubbed_vim_api(function()
      -- ========= [A]rrange =========
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

      -- ========= [A]ct     =========
      local handle = provider.toggle(
        { terminal = stale_terminal },
        "codex",
        {},
        {},
        { terminal = { startup = { grace_ms = 0 }, provider_opts = {} } }
      )

      -- ========= [A]ssert  =========
      assert.equals(0, stale_toggle_calls)
      assert.same(fresh_terminal, handle.terminal)
    end)
  end)

  it("passes command and options separately to snacks.terminal", function()
    with_stubbed_vim_api(function()
      -- ========= [A]rrange =========
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

      -- ========= [A]ct     =========
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

      -- ========= [A]ssert  =========
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
      -- ========= [A]rrange =========
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, {
        terminal = {
          auto_close = true,
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      -- ========= [A]ssert  =========
      assert.is_false(captured_opts.auto_close)
      assert.equals(1, #autocmds)
      assert.equals("TermClose", autocmds[1].event)
    end)
  end)

  it("runs on_exit on TermClose when auto_close=true", function()
    with_stubbed_vim_api(function(autocmds)
      -- ========= [A]rrange =========
      local terminal = {
        buf = 42,
        close = function() end,
      }
      package.loaded["snacks"] = {
        terminal = function()
          return terminal
        end,
      }
      local scheduled = {}
      stub(vim, "schedule", function(cb)
        table.insert(scheduled, cb)
      end)
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

      -- ========= [A]ct     =========
      autocmds[1].spec.callback()

      -- ========= [A]ssert  =========
      assert.equals(1, on_exit_calls)
      assert.equals(1, #scheduled)
    end)
  end)

  it("closes terminal after TermClose when auto_close=true", function()
    with_stubbed_vim_api(function(autocmds, _, cmd_calls)
      -- ========= [A]rrange =========
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
      stub(vim, "schedule", function(cb)
        table.insert(scheduled, cb)
      end)
      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, {
        terminal = {
          auto_close = true,
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, function() end)
      autocmds[1].spec.callback()

      -- ========= [A]ct     =========
      scheduled[1]()

      -- ========= [A]ssert  =========
      assert.equals(1, close_calls)
      assert.same({ "checktime" }, cmd_calls)
    end)
  end)

  it("passes snacks win options through provider_opts", function()
    with_stubbed_vim_api(function()
      -- ========= [A]rrange =========
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
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

      -- ========= [A]ssert  =========
      assert.equals("left", captured_opts.win.position)
      assert.equals(0.4, captured_opts.win.width)
    end)
  end)

  it("passes snacks horizontal win options through provider_opts", function()
    with_stubbed_vim_api(function()
      -- ========= [A]rrange =========
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
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

      -- ========= [A]ssert  =========
      assert.equals("bottom", captured_opts.win.position)
      assert.equals(0.3, captured_opts.win.height)
    end)
  end)

  it("passes snacks float win options through provider_opts", function()
    with_stubbed_vim_api(function()
      -- ========= [A]rrange =========
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
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

      -- ========= [A]ssert  =========
      assert.equals("float", captured_opts.win.position)
      assert.equals("rounded", captured_opts.win.border)
    end)
  end)

  it("handles missing terminal.startup without error", function()
    with_stubbed_vim_api(function()
      -- ========= [A]rrange =========
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local handle = provider.open("codex", {}, {}, {
        terminal = {
          provider_opts = {},
        },
      }, false, nil)

      -- ========= [A]ssert  =========
      assert.is_not_nil(handle)
      assert.is_number(handle.ready_at_ms)
      local uv = vim.uv or vim.loop
      local expected = (uv and type(uv.now) == "function") and uv.now() or 0
      assert.equals(expected, handle.ready_at_ms)
    end)
  end)

  it("does not set opts.win when snacks win options are omitted", function()
    with_stubbed_vim_api(function()
      -- ========= [A]rrange =========
      local captured_opts = nil
      package.loaded["snacks"] = {
        terminal = function(_, opts)
          captured_opts = opts
          return { buf = 42 }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, {
        terminal = {
          startup = { grace_ms = 0 },
          provider_opts = {},
        },
      }, false, nil)

      -- ========= [A]ssert  =========
      assert.is_nil(captured_opts.win)
    end)
  end)

  it("discover_restorable matches snacks terminal metadata with extra Codex args", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls, _, state)
      -- ========= [A]rrange =========
      state.buf_valid[42] = true
      state.buf_channels[42] = 55
      state.buf_vars[42] = {
        snacks_terminal = {
          cmd = "codex --model o3",
          cwd = "/tmp/snacks",
        },
      }
      state.win_valid[8] = true
      state.win_buf[8] = 42
      state.current_win = 8
      state.current_buf = 42

      package.loaded["snacks"] = {
        terminal = {},
        win = function(opts)
          return {
            buf = opts.buf,
            show = function(self)
              self.win = 10
              state.win_valid[10] = true
              state.win_buf[10] = self.buf
            end,
          }
        end,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local restored = provider.discover_restorable({
        launch = { cmd = "codex", cwd = nil },
        terminal = {
          auto_close = false,
          startup = { grace_ms = 0 },
          keymaps = {},
          provider_opts = {},
        },
      }, nil)

      -- ========= [A]ssert  =========
      assert.equals(1, #restored)
      assert.equals(42, restored[1].bufnr)
      assert.equals(8, restored[1].winid)
      assert.equals("codex --model o3", restored[1].cmd)
      assert.equals("/tmp/snacks", restored[1].cwd)
      assert.equals(42, provider.get_bufnr(restored[1].handle))
      assert.is_true(provider.is_alive(restored[1].handle))
      assert.equals(0, #autocmds)
      assert.equals(0, #keymap_set_calls)
    end)
  end)

  it("discover_restorable accepts callable snacks.win modules", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls, _, state)
      -- ========= [A]rrange =========
      state.buf_valid[42] = true
      state.buf_channels[42] = 55
      state.buf_vars[42] = {
        snacks_terminal = {
          cmd = "codex --model o3",
          cwd = "/tmp/snacks",
        },
      }
      state.win_valid[8] = true
      state.win_buf[8] = 42
      state.current_win = 8
      state.current_buf = 42

      local win_module = setmetatable({}, {
        __call = function(_, opts)
          return {
            buf = opts.buf,
            show = function(self)
              self.win = 10
              state.win_valid[10] = true
              state.win_buf[10] = self.buf
            end,
          }
        end,
      })

      package.loaded["snacks"] = {
        terminal = {},
        win = win_module,
      }
      local provider = require("codex.providers.snacks")

      -- ========= [A]ct     =========
      local restored = provider.discover_restorable({
        launch = { cmd = "codex", cwd = nil },
        terminal = {
          auto_close = false,
          startup = { grace_ms = 0 },
          keymaps = {},
          provider_opts = {},
        },
      }, nil)

      -- ========= [A]ssert  =========
      assert.equals(1, #restored)
      assert.equals(42, restored[1].bufnr)
      assert.equals(8, restored[1].winid)
      assert.equals("codex --model o3", restored[1].cmd)
      assert.equals(42, provider.get_bufnr(restored[1].handle))
      assert.is_true(provider.is_alive(restored[1].handle))
      assert.equals(0, #autocmds)
      assert.equals(0, #keymap_set_calls)
    end)
  end)

  it("attach_restored registers TermClose autocmd and terminal keymaps", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.snacks")
      local handle = {
        terminal = {
          buf = 42,
        },
      }

      -- ========= [A]ct     =========
      local ok, err = provider.attach_restored(handle, {
        terminal = {
          auto_close = false,
          keymaps = default_terminal_keymaps(),
        },
      }, function() end)

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, #autocmds)
      assert.equals("TermClose", autocmds[1].event)
      assert.equals(42, autocmds[1].spec.buffer)
      assert.equals(6, #keymap_set_calls)
      assert.is_not_nil(find_keymap(keymap_set_calls, "<C-c>"))
      assert.is_not_nil(find_keymap(keymap_set_calls, "<M-BS>"))
    end)
  end)
end)
