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

  local function setup(auto_start, schedule)
    local codex = require("codex")
    codex.setup({
      launch = { auto_start = auto_start },
      hooks = {
        on_terminal_close = function()
          close_hooks = close_hooks + 1
        end,
      },
      _deps = {
        providers = providers,
        vim = schedule and vim.tbl_extend("force", vim, { schedule = schedule }) or vim,
      },
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

  it("deactivate closes the session and removes commands and autocmds", function()
    -- ========= [A]rrange =========
    ---@type codex.Api
    local codex = setup(false)
    codex.session.open(false)
    assert.is_not_nil(vim.api.nvim_get_commands({ builtin = false }).Codex)
    assert.is_true(#vim.api.nvim_get_autocmds({ group = "codex_focus_tracking" }) > 0)
    assert.is_true(#vim.api.nvim_get_autocmds({ group = "codex_session_restore" }) > 0)

    -- ========= [A]ct     =========
    codex.deactivate()

    -- ========= [A]ssert  =========
    assert.equal(1, closes)
    assert.equal(1, close_hooks)
    assert.same(baseline_commands, vim.api.nvim_get_commands({ builtin = false }))
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
      assert.is_not.equal("codex_focus_tracking", autocmd.group_name)
      assert.is_not.equal("codex_session_restore", autocmd.group_name)
    end
  end)

  it("reload restores commands and ignores stale auto_start work", function()
    -- ========= [A]rrange =========
    local scheduled = {}
    local first = setup(true, function(callback)
      table.insert(scheduled, callback)
    end)
    first.session.open(false)
    first.deactivate()
    assert.equal(1, #scheduled)

    -- ========= [A]ct     =========
    reload()
    scheduled[1]()

    -- ========= [A]ssert  =========
    assert.equal(1, opens)
    assert.is_not_nil(vim.api.nvim_get_commands({ builtin = false }).Codex)
    assert.equal(2, #vim.api.nvim_get_autocmds({ group = "codex_focus_tracking" }))
    assert.equal(2, #vim.api.nvim_get_autocmds({ group = "codex_session_restore" }))
  end)

  it("supports consecutive reload cycles without duplicate close hooks or registrations", function()
    -- ========= [A]rrange =========
    local first = setup(false)
    first.session.open(false)
    first.deactivate()

    -- ========= [A]ct     =========
    local second = reload()
    second.session.open(false)
    second.deactivate()
    local third = reload()
    third.session.open(false)
    third.deactivate()

    -- ========= [A]ssert  =========
    assert.equal(3, opens)
    assert.equal(3, closes)
    assert.equal(3, close_hooks)
    assert.same(baseline_commands, vim.api.nvim_get_commands({ builtin = false }))
  end)
end)
