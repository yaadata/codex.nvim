local function unload_codex_modules()
  for name in pairs(package.loaded) do
    if name == "codex" or name:match("^codex%.") then
      package.loaded[name] = nil
    end
  end
end

describe("codex.nvim lazy reload lifecycle", function()
  local baseline_commands
  local opens
  local closes
  local close_hooks
  local provider
  local providers

  local function setup(auto_start)
    local codex = require("codex")
    codex.setup({
      launch = { auto_start = auto_start },
      hooks = {
        on_terminal_close = function()
          close_hooks = close_hooks + 1
        end,
      },
      _deps = { providers = providers },
    })
    return codex
  end

  local function reload()
    unload_codex_modules()
    vim.g.loaded_codex = nil
    vim.cmd.runtime("plugin/codex.lua")
    return setup(false)
  end

  before_each(function()
    baseline_commands = vim.api.nvim_get_commands({ builtin = false })
    opens = 0
    closes = 0
    close_hooks = 0
    provider = {}

    function provider.is_available()
      return true
    end

    function provider.open()
      opens = opens + 1
      return { alive = true }
    end

    function provider.close(handle)
      closes = closes + 1
      handle.alive = false
      return true
    end

    function provider.is_alive(handle)
      return handle ~= nil and handle.alive == true
    end

    function provider.is_ready(handle)
      return provider.is_alive(handle)
    end

    function provider.discover_restorable()
      return {}
    end

    providers = {
      resolve = function()
        return provider, "native"
      end,
    }
  end)

  after_each(function()
    local codex = package.loaded.codex
    if codex and type(codex.deactivate) == "function" then
      codex.deactivate()
    end
    unload_codex_modules()
    vim.g.loaded_codex = nil
  end)

  it("deactivate closes the active session and removes runtime registrations", function()
    -- ========= [A]rrange =========
    local codex = setup(false)
    codex.open(false)
    assert.is_true(codex.is_running())
    assert.is_not_nil(vim.api.nvim_get_commands({ builtin = false }).Codex)

    -- ========= [A]ct     =========
    codex.deactivate()

    -- ========= [A]ssert  =========
    assert.equals(1, closes)
    assert.equals(1, close_hooks)
    assert.same(baseline_commands, vim.api.nvim_get_commands({ builtin = false }))
    assert.is_true(pcall(vim.api.nvim_exec_autocmds, "WinEnter", {}))
    assert.is_true(pcall(vim.api.nvim_exec_autocmds, "SessionLoadPost", {}))
  end)

  it("reload restores commands without running stale auto_start work", function()
    -- ========= [A]rrange =========
    local first = setup(true)
    first.open(false)
    first.deactivate()

    -- ========= [A]ct     =========
    local second = reload()
    vim.wait(10)

    -- ========= [A]ssert  =========
    assert.equals(1, opens)
    assert.is_not_nil(vim.api.nvim_get_commands({ builtin = false }).Codex)
    second.open(false)
    assert.is_true(second.is_running())
  end)

  it("supports consecutive reload cycles", function()
    -- ========= [A]rrange =========
    local first = setup(false)
    first.open(false)
    first.deactivate()

    -- ========= [A]ct     =========
    local second = reload()
    second.open(false)
    second.deactivate()
    local third = reload()
    third.open(false)
    third.deactivate()

    -- ========= [A]ssert  =========
    assert.equals(3, opens)
    assert.equals(3, closes)
    assert.equals(3, close_hooks)
    assert.same(baseline_commands, vim.api.nvim_get_commands({ builtin = false }))
  end)
end)
