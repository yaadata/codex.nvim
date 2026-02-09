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
  local original_chansend = vim.fn.chansend
  local chansend_calls = {}
  local buf_valid = {}
  local buf_vars = {}

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
  vim.fn.chansend = function(jobid, text)
    table.insert(chansend_calls, { jobid = jobid, text = text })
  end

  local ok, err = pcall(run, {
    chansend_calls = chansend_calls,
    buf_valid = buf_valid,
    buf_vars = buf_vars,
  })

  vim.api.nvim_buf_is_valid = original_buf_is_valid
  vim.api.nvim_buf_get_var = original_buf_get_var
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
        { terminal = { provider_opts = {} } },
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

  it("does not register TermClose autocmd when on_exit callback is missing", function()
    with_stubbed_vim_api(function(autocmds, keymap_set_calls)
      package.loaded["snacks"] = {
        terminal = function()
          return { buf = 42 }
        end,
      }

      local provider = require("codex.providers.snacks")
      provider.open("codex", {}, {}, { terminal = { provider_opts = {} } }, true, nil)

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
      provider.open("codex", {}, {}, { terminal = { provider_opts = {} } }, true, nil)

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
      assert.equals("float", captured_opts.win.position)
    end)
  end)
end)
