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

local function make_config(overrides)
  local base = {
    launch = {
      cwd = nil,
    },
    terminal = {
      auto_close = false,
      startup = {
        timeout_ms = 2000,
        retry_interval_ms = 50,
        grace_ms = 700,
      },
      keymaps = {},
      provider_opts = {
        native = {
          window = "vsplit",
          vsplit = {
            side = "right",
            size_pct = 40,
          },
          hsplit = {
            side = "bottom",
            size_pct = 30,
          },
          float = {
            width_pct = 80,
            height_pct = 80,
            border = "rounded",
            title = " Codex ",
            title_pos = "center",
          },
        },
      },
    },
  }

  return vim.tbl_deep_extend("force", base, overrides or {})
end

local function with_stubbed_native_env(run)
  local api_methods = {
    "nvim_list_wins",
    "nvim_win_get_buf",
    "nvim_get_current_win",
    "nvim_get_current_buf",
    "nvim_create_buf",
    "nvim_win_set_buf",
    "nvim_win_set_width",
    "nvim_win_set_height",
    "nvim_open_win",
    "nvim_win_is_valid",
    "nvim_set_current_win",
    "nvim_win_close",
    "nvim_buf_is_valid",
    "nvim_buf_delete",
  }
  local fn_methods = { "getcwd", "termopen", "chansend", "jobstop" }

  local original_api = {}
  local original_fn = {}
  local original_cmd = vim.cmd
  local original_bo = vim.bo
  local original_keymap_set = vim.keymap.set
  local original_columns = vim.o.columns
  local original_lines = vim.o.lines

  for _, method in ipairs(api_methods) do
    original_api[method] = vim.api[method]
  end
  for _, method in ipairs(fn_methods) do
    original_fn[method] = vim.fn[method]
  end

  local state = {
    next_buf = 2,
    next_win = 2,
    next_jobid = 100,
    current_win = 1,
    wins = { [1] = { bufnr = 1, valid = true } },
    buf_valid = { [1] = true },
    cmd_calls = {},
    win_width_calls = {},
    win_height_calls = {},
    open_win_calls = {},
    win_close_calls = {},
    set_current_win_calls = {},
    termopen_calls = {},
    chansend_calls = {},
    jobstop_calls = {},
    keymap_set_calls = {},
    startinsert_calls = 0,
    set_current_win_error = nil,
  }

  local function create_split_window()
    local winid = state.next_win
    state.next_win = state.next_win + 1
    local current = state.wins[state.current_win]
    state.wins[winid] = {
      bufnr = current and current.bufnr or 1,
      valid = true,
    }
    state.current_win = winid
    return winid
  end

  local function nvim_list_wins()
    local wins = {}
    for winid, win in pairs(state.wins) do
      if win.valid then
        table.insert(wins, winid)
      end
    end
    table.sort(wins)
    return wins
  end

  local function nvim_win_get_buf(winid)
    return state.wins[winid].bufnr
  end

  local function nvim_get_current_win()
    return state.current_win
  end

  local function nvim_get_current_buf()
    local win = state.wins[state.current_win]
    return win and win.bufnr or -1
  end

  local function nvim_create_buf()
    local bufnr = state.next_buf
    state.next_buf = state.next_buf + 1
    state.buf_valid[bufnr] = true
    return bufnr
  end

  local function nvim_win_set_buf(winid, bufnr)
    state.wins[winid].bufnr = bufnr
  end

  local function nvim_win_set_width(winid, width)
    table.insert(state.win_width_calls, { winid = winid, width = width })
  end

  local function nvim_win_set_height(winid, height)
    table.insert(state.win_height_calls, { winid = winid, height = height })
  end

  local function nvim_open_win(bufnr, enter, opts)
    local winid = state.next_win
    state.next_win = state.next_win + 1
    state.wins[winid] = { bufnr = bufnr, valid = true }
    table.insert(state.open_win_calls, { bufnr = bufnr, enter = enter, opts = opts, winid = winid })
    if enter then
      state.current_win = winid
    end
    return winid
  end

  local function nvim_win_is_valid(winid)
    return state.wins[winid] and state.wins[winid].valid or false
  end

  local function nvim_set_current_win(winid)
    if state.set_current_win_error then
      error(state.set_current_win_error)
    end
    state.current_win = winid
    table.insert(state.set_current_win_calls, winid)
  end

  local function nvim_win_close(winid, force)
    table.insert(state.win_close_calls, { winid = winid, force = force })
    if state.wins[winid] then
      state.wins[winid].valid = false
    end
  end

  local function nvim_buf_is_valid(bufnr)
    return state.buf_valid[bufnr] == true
  end

  local function nvim_buf_delete(bufnr)
    state.buf_valid[bufnr] = false
  end

  local function getcwd()
    return "/test/cwd"
  end

  local function termopen(cmd, opts)
    table.insert(state.termopen_calls, { cmd = cmd, opts = opts })
    local jobid = state.next_jobid
    state.next_jobid = state.next_jobid + 1
    return jobid
  end

  local function chansend(jobid, text)
    table.insert(state.chansend_calls, { jobid = jobid, text = text })
  end

  local function jobstop(jobid)
    table.insert(state.jobstop_calls, jobid)
  end

  local fake_bo = setmetatable({}, {
    __index = function(tbl, bufnr)
      local value = {}
      rawset(tbl, bufnr, value)
      return value
    end,
  })

  local function fake_cmd(cmd)
    table.insert(state.cmd_calls, cmd)
    if cmd == "startinsert" then
      state.startinsert_calls = state.startinsert_calls + 1
      return
    end

    if
      cmd == "topleft vsplit"
      or cmd == "botright vsplit"
      or cmd == "topleft split"
      or cmd == "botright split"
    then
      create_split_window()
    end
  end

  local function keymap_set(mode, lhs, rhs, opts)
    table.insert(state.keymap_set_calls, {
      mode = mode,
      lhs = lhs,
      rhs = rhs,
      opts = opts,
    })
  end

  vim.api.nvim_list_wins = nvim_list_wins
  vim.api.nvim_win_get_buf = nvim_win_get_buf
  vim.api.nvim_get_current_win = nvim_get_current_win
  vim.api.nvim_get_current_buf = nvim_get_current_buf
  vim.api.nvim_create_buf = nvim_create_buf
  vim.api.nvim_win_set_buf = nvim_win_set_buf
  vim.api.nvim_win_set_width = nvim_win_set_width
  vim.api.nvim_win_set_height = nvim_win_set_height
  vim.api.nvim_open_win = nvim_open_win
  vim.api.nvim_win_is_valid = nvim_win_is_valid
  vim.api.nvim_set_current_win = nvim_set_current_win
  vim.api.nvim_win_close = nvim_win_close
  vim.api.nvim_buf_is_valid = nvim_buf_is_valid
  vim.api.nvim_buf_delete = nvim_buf_delete
  vim.fn.getcwd = getcwd
  vim.fn.termopen = termopen
  vim.fn.chansend = chansend
  vim.fn.jobstop = jobstop
  vim.cmd = fake_cmd
  vim.bo = fake_bo
  vim.keymap.set = keymap_set
  vim.o.columns = 120
  vim.o.lines = 50

  local ok, err = pcall(run, state)

  for _, method in ipairs(api_methods) do
    vim.api[method] = original_api[method]
  end
  for _, method in ipairs(fn_methods) do
    vim.fn[method] = original_fn[method]
  end
  vim.cmd = original_cmd
  vim.bo = original_bo
  vim.keymap.set = original_keymap_set
  vim.o.columns = original_columns
  vim.o.lines = original_lines

  if not ok then
    error(err)
  end
end

describe("codex.providers.native", function()
  before_each(function()
    package.loaded["codex.providers.native"] = nil
  end)

  it("opens vsplit windows and restores previous window when focus=false", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "vsplit",
              vsplit = { side = "right", size_pct = 40 },
            },
          },
        },
      })

      -- ========= [A]ct     =========
      local handle = provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.equals(2, handle.bufnr)
      assert.equals(2, handle.winid)
      assert.equals(1, state.current_win)
      assert.equals(48, state.win_width_calls[1].width)
      assert.equals(1, state.set_current_win_calls[1])
      assert.equals(0, state.startinsert_calls)
    end)
  end)

  it("omits termopen env when config env is empty", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.is_nil(state.termopen_calls[1].opts.env)
    end)
  end)

  it("passes termopen env when config env has values", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local env = { CODEX_TEST = "1" }

      -- ========= [A]ct     =========
      provider.open("codex", {}, env, cfg, false)

      -- ========= [A]ssert  =========
      assert.same(env, state.termopen_calls[1].opts.env)
    end)
  end)

  it("does not register terminal keymaps by default", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, make_config(), false)

      -- ========= [A]ssert  =========
      assert.equals(0, #state.keymap_set_calls)
    end)
  end)

  it("registers configured builtin terminal keymaps", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          keymaps = default_terminal_keymaps(),
        },
      })

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.equals(6, #state.keymap_set_calls)
      local toggle_map = find_keymap(state.keymap_set_calls, "<C-c>")
      local clear_map = find_keymap(state.keymap_set_calls, "<M-BS>")
      local nav_left = find_keymap(state.keymap_set_calls, "<C-h>")

      assert.is_not_nil(toggle_map)
      assert.equals("t", toggle_map.mode)
      assert.is_function(toggle_map.rhs)
      assert.equals(2, toggle_map.opts.buffer)
      assert.is_true(toggle_map.opts.silent)
      assert.is_true(toggle_map.opts.nowait)
      assert.equals("Codex: Toggle terminal", toggle_map.opts.desc)

      assert.is_not_nil(clear_map)
      assert.equals("Codex: Clear input", clear_map.opts.desc)
      assert.is_not_nil(nav_left)
      assert.equals("Codex: Move to left window", nav_left.opts.desc)
    end)
  end)

  it("registers custom terminal keymap keys for builtin actions", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          keymaps = {
            ["<C-t>"] = { mode = "t", action = builtins.toggle },
            ["<C-x>"] = { mode = "t", action = builtins.close },
            ["<M-BS>"] = { mode = "t", action = builtins.clear_input },
          },
        },
      })

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.equals(3, #state.keymap_set_calls)
      assert.is_not_nil(find_keymap(state.keymap_set_calls, "<C-t>"))
      assert.is_not_nil(find_keymap(state.keymap_set_calls, "<C-x>"))
      assert.is_not_nil(find_keymap(state.keymap_set_calls, "<M-BS>"))
    end)
  end)

  it("close keymap defers via vim.schedule", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local scheduled = {}
      local original_schedule = vim.schedule
      vim.schedule = function(cb)
        table.insert(scheduled, cb)
      end
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          keymaps = {
            ["<C-x>"] = { mode = "t", action = builtins.close },
          },
        },
      })
      provider.open("codex", {}, {}, cfg, false)
      local close_map = find_keymap(state.keymap_set_calls, "<C-x>")

      -- ========= [A]ct     =========
      close_map.rhs()

      vim.schedule = original_schedule

      -- ========= [A]ssert  =========
      assert.equals(1, #scheduled)
      assert.is_function(scheduled[1])
    end)
  end)

  it("clear input keymap calls codex.clear_input directly", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
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
      local provider = require("codex.providers.native")
      provider.open(
        "codex",
        {},
        {},
        make_config({
          terminal = {
            keymaps = {
              ["<M-BS>"] = { mode = "t", action = builtins.clear_input },
            },
          },
        }),
        false
      )
      local clear_map = find_keymap(state.keymap_set_calls, "<M-BS>")

      -- ========= [A]ct     =========
      clear_map.rhs()

      vim.schedule = original_schedule
      package.loaded["codex"] = nil

      -- ========= [A]ssert  =========
      assert.equals(1, clear_input_calls)
      assert.equals(0, #scheduled)
    end)
  end)

  it("registers directional navigation keymaps even for float windows", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "float",
            },
          },
          keymaps = {
            ["<C-h>"] = { mode = "t", action = builtins.nav_left },
            ["<C-j>"] = { mode = "t", action = builtins.nav_down },
            ["<C-k>"] = { mode = "t", action = builtins.nav_up },
            ["<C-l>"] = { mode = "t", action = builtins.nav_right },
          },
        },
      })

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.equals(4, #state.keymap_set_calls)
      assert.is_not_nil(find_keymap(state.keymap_set_calls, "<C-h>"))
      assert.is_not_nil(find_keymap(state.keymap_set_calls, "<C-j>"))
      assert.is_not_nil(find_keymap(state.keymap_set_calls, "<C-k>"))
      assert.is_not_nil(find_keymap(state.keymap_set_calls, "<C-l>"))
    end)
  end)

  it("opens hsplit windows and focuses insert mode when focus=true", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "hsplit",
              hsplit = { side = "bottom", size_pct = 30 },
            },
          },
        },
      })

      -- ========= [A]ct     =========
      local handle = provider.open("codex", {}, {}, cfg, true)

      -- ========= [A]ssert  =========
      assert.equals(2, handle.winid)
      assert.equals(15, state.win_height_calls[1].height)
      assert.equals(2, state.current_win)
      assert.equals(1, state.startinsert_calls)
    end)
  end)

  it("opens float windows with configured options", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "float",
              float = {
                width_pct = 80,
                height_pct = 60,
                border = "single",
                title = " Codex Test ",
                title_pos = "left",
              },
            },
          },
        },
      })

      -- ========= [A]ct     =========
      local handle = provider.open("codex", {}, {}, cfg, true)

      -- ========= [A]ssert  =========
      assert.equals(2, handle.winid)
      assert.equals(1, #state.open_win_calls)

      local open_call = state.open_win_calls[1]
      assert.equals(2, open_call.bufnr)
      assert.equals(96, open_call.opts.width)
      assert.equals(30, open_call.opts.height)
      assert.equals(10, open_call.opts.row)
      assert.equals(12, open_call.opts.col)
      assert.equals("single", open_call.opts.border)
      assert.equals(" Codex Test ", open_call.opts.title)
      assert.equals("left", open_call.opts.title_pos)
      assert.equals("minimal", open_call.opts.style)
    end)
  end)

  it("clamps split dimensions to at least one", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "vsplit",
              vsplit = { side = "left", size_pct = 0 },
            },
          },
        },
      })

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, cfg, true)

      -- ========= [A]ssert  =========
      assert.equals(1, state.win_width_calls[1].width)
    end)
  end)

  it("clamps float dimensions to at least one", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "float",
              float = {
                width_pct = 0,
                height_pct = 0,
                border = "rounded",
                title = " Codex ",
                title_pos = "center",
              },
            },
          },
        },
      })

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, cfg, true)

      -- ========= [A]ssert  =========
      local open_call = state.open_win_calls[1]
      assert.equals(1, open_call.opts.width)
      assert.equals(1, open_call.opts.height)
    end)
  end)

  it("does not auto-close native terminal window on exit when auto_close=false", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          auto_close = false,
        },
      })
      local handle = provider.open("codex", {}, {}, cfg, true)
      local bufnr = handle.bufnr

      -- ========= [A]ct     =========
      state.termopen_calls[1].opts.on_exit(nil, 0)

      -- ========= [A]ssert  =========
      assert.equals(0, #state.win_close_calls)
      assert.is_true(state.buf_valid[bufnr])
      assert.is_nil(handle.jobid)
    end)
  end)

  it("auto-closes native terminal window on exit when auto_close=true", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          auto_close = true,
        },
      })
      local handle = provider.open("codex", {}, {}, cfg, true)
      local winid = handle.winid
      local bufnr = handle.bufnr

      -- ========= [A]ct     =========
      state.termopen_calls[1].opts.on_exit(nil, 0)

      -- ========= [A]ssert  =========
      assert.equals(1, #state.win_close_calls)
      assert.equals(winid, state.win_close_calls[1].winid)
      assert.is_false(state.buf_valid[bufnr])
      assert.is_nil(handle.jobid)
      assert.is_nil(handle.winid)
      assert.is_nil(handle.bufnr)
    end)
  end)

  it("does not notify on non-zero exit and still runs on_exit callback", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          auto_close = true,
        },
      })
      local notify_calls = 0
      local original_notify = vim.notify
      vim.notify = function()
        notify_calls = notify_calls + 1
      end
      local exited_handle = nil
      local handle = provider.open("codex", {}, {}, cfg, true, function(cb_handle)
        exited_handle = cb_handle
      end)
      local winid = handle.winid

      -- ========= [A]ct     =========
      state.termopen_calls[1].opts.on_exit(nil, -1)

      vim.notify = original_notify

      -- ========= [A]ssert  =========
      assert.same(handle, exited_handle)
      assert.equals(1, #state.win_close_calls)
      assert.equals(winid, state.win_close_calls[1].winid)
      assert.equals(0, notify_calls)
    end)
  end)

  it("focuses terminal window and enters insert mode", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local handle = provider.open("codex", {}, {}, cfg, true)
      state.current_win = 1
      state.startinsert_calls = 0

      -- ========= [A]ct     =========
      local ok, err = provider.focus(handle)

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(handle.winid, state.current_win)
      assert.equals(1, state.startinsert_calls)
    end)
  end)

  it("focus recovers a stale window id by searching for the terminal buffer", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local handle = provider.open("codex", {}, {}, cfg, true)
      local expected_winid = handle.winid
      handle.winid = 999
      state.current_win = 1
      state.startinsert_calls = 0

      -- ========= [A]ct     =========
      local ok, err = provider.focus(handle)

      -- ========= [A]ssert  =========
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(expected_winid, handle.winid)
      assert.equals(expected_winid, state.current_win)
      assert.equals(1, state.startinsert_calls)
    end)
  end)

  it("focus returns terminal window mismatch when selected window buffer is wrong", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local handle = provider.open("codex", {}, {}, cfg, true)
      state.wins[handle.winid].bufnr = 1
      state.current_win = 1
      state.startinsert_calls = 0

      -- ========= [A]ct     =========
      local ok, err = provider.focus(handle)

      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.equals("terminal window mismatch", err)
      assert.equals(0, state.startinsert_calls)
    end)
  end)

  it("focus returns an error when setting the terminal window fails", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local handle = provider.open("codex", {}, {}, cfg, true)
      state.set_current_win_error = "boom"
      state.startinsert_calls = 0

      -- ========= [A]ct     =========
      local ok, err = provider.focus(handle)

      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.matches("^failed to focus terminal window:", err)
      assert.equals(0, state.startinsert_calls)
    end)
  end)

  it("focus returns terminal window not found when no visible terminal window exists", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local handle = provider.open("codex", {}, {}, cfg, true)
      state.wins[handle.winid].valid = false
      handle.winid = nil
      state.startinsert_calls = 0

      -- ========= [A]ct     =========
      local ok, err = provider.focus(handle)

      -- ========= [A]ssert  =========
      assert.is_false(ok)
      assert.equals("terminal window not found", err)
      assert.equals(0, state.startinsert_calls)
    end)
  end)

  it("toggle closes the window when already focused", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local handle = provider.open("codex", {}, {}, cfg, true)
      state.startinsert_calls = 0

      -- ========= [A]ct     =========
      provider.toggle(handle, "codex", {}, {}, cfg)

      -- ========= [A]ssert  =========
      assert.equals(1, #state.win_close_calls)
      assert.equals(2, state.win_close_calls[1].winid)
      assert.is_false(state.win_close_calls[1].force)
      assert.is_nil(handle.winid)
      assert.equals(0, state.startinsert_calls)
    end)
  end)

  it("toggle focuses existing terminal window from another window", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      local handle = provider.open("codex", {}, {}, cfg, true)
      state.current_win = 1
      state.startinsert_calls = 0

      -- ========= [A]ct     =========
      provider.toggle(handle, "codex", {}, {}, cfg)

      -- ========= [A]ssert  =========
      assert.equals(2, state.current_win)
      assert.equals(1, state.startinsert_calls)
    end)
  end)

  it("toggle re-shows buffer using current configured window type", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local initial_cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "vsplit",
              vsplit = { side = "right", size_pct = 40 },
            },
          },
        },
      })
      local handle = provider.open("codex", {}, {}, initial_cfg, true)
      state.wins[handle.winid].valid = false
      handle.winid = nil
      state.current_win = 1
      state.startinsert_calls = 0
      local float_cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "float",
              float = {
                width_pct = 80,
                height_pct = 80,
                border = "double",
                title = " Reopen ",
                title_pos = "right",
              },
            },
          },
        },
      })

      -- ========= [A]ct     =========
      provider.toggle(handle, "codex", {}, {}, float_cfg)

      -- ========= [A]ssert  =========
      assert.equals(1, #state.open_win_calls)
      assert.equals(handle.bufnr, state.open_win_calls[1].bufnr)
      assert.equals("double", state.open_win_calls[1].opts.border)
      assert.equals(" Reopen ", state.open_win_calls[1].opts.title)
      assert.equals("right", state.open_win_calls[1].opts.title_pos)
      assert.equals(state.open_win_calls[1].winid, handle.winid)
      assert.equals(handle.winid, state.current_win)
      assert.equals(1, state.startinsert_calls)
    end)
  end)

  it("handles missing terminal.startup without error", function()
    with_stubbed_native_env(function()
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config()
      cfg.terminal.startup = nil

      -- ========= [A]ct     =========
      local handle = provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.is_not_nil(handle)
      assert.is_number(handle.ready_at_ms)
      local uv = vim.uv or vim.loop
      local expected = (uv and type(uv.now) == "function") and uv.now() or 0
      assert.equals(expected, handle.ready_at_ms)
    end)
  end)

  it("uses default vsplit config when vsplit sub-table is nil", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "vsplit",
              vsplit = vim.NIL,
            },
          },
        },
      })
      cfg.terminal.provider_opts.native.vsplit = nil

      -- ========= [A]ct     =========
      local handle = provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.equals(2, handle.bufnr)
      assert.equals(2, handle.winid)
      assert.equals("botright vsplit", state.cmd_calls[1])
      assert.equals(48, state.win_width_calls[1].width)
    end)
  end)

  it("uses default hsplit config when hsplit sub-table is nil", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "hsplit",
              hsplit = vim.NIL,
            },
          },
        },
      })
      cfg.terminal.provider_opts.native.hsplit = nil

      -- ========= [A]ct     =========
      local handle = provider.open("codex", {}, {}, cfg, false)

      -- ========= [A]ssert  =========
      assert.equals(2, handle.bufnr)
      assert.equals(2, handle.winid)
      assert.equals("botright split", state.cmd_calls[1])
      assert.equals(15, state.win_height_calls[1].height)
    end)
  end)

  it("uses default float config when float sub-table is nil", function()
    with_stubbed_native_env(function(state)
      -- ========= [A]rrange =========
      local provider = require("codex.providers.native")
      local cfg = make_config({
        terminal = {
          provider_opts = {
            native = {
              window = "float",
              float = vim.NIL,
            },
          },
        },
      })
      cfg.terminal.provider_opts.native.float = nil

      -- ========= [A]ct     =========
      provider.open("codex", {}, {}, cfg, true)

      -- ========= [A]ssert  =========
      assert.equals(1, #state.open_win_calls)
      local open_call = state.open_win_calls[1]
      assert.equals(96, open_call.opts.width)
      assert.equals(40, open_call.opts.height)
      assert.equals("rounded", open_call.opts.border)
      assert.equals(" Codex ", open_call.opts.title)
      assert.equals("center", open_call.opts.title_pos)
    end)
  end)
end)
