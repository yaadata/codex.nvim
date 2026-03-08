local helpers = require("tests.unit.helpers.init_spec_helpers")

local function make_config()
  return {
    launch = {
      cmd = "codex-test",
      args = { "--flag" },
      env = { CODEX_TEST = "1" },
    },
    terminal = {
      provider = "native",
      startup = {
        timeout_ms = 200,
        retry_interval_ms = 50,
      },
    },
  }
end

---@param opts? { dispatch_send?: fun(text: string, send_opts?: codex.DispatchSendOpts, dispatch_calls: table): codex.SendResult, string|nil }
local function make_env(opts)
  opts = opts or {}
  local provider = helpers.make_provider()
  local session_store = helpers.make_session_store()
  local logger = helpers.make_logger()
  local formatter = helpers.make_formatter()
  local selection = helpers.make_selection()
  local fake_vim = helpers.make_fake_vim()
  local config = make_config()

  local handle = { id = "selection-handle", alive = true }
  local session_id = session_store.create({
    handle = handle,
    cmd = config.launch.cmd,
    cwd = "/test/cwd",
    provider_name = "native",
  })

  local providers = {}
  function providers.resolve()
    return provider, "native"
  end

  local deps = {
    formatter = formatter,
    logger = logger,
    nvim_visual = require("codex.nvim.visual"),
    providers = providers,
    selection = selection,
    session_store = session_store,
    vim = fake_vim,
  }

  local dispatch_calls = {}
  local selection_send = require("codex.context.selection_send").create({
    get_deps = function()
      return deps
    end,
    get_config = function()
      return config
    end,
    dispatch_send = function(text, send_opts)
      if opts.dispatch_send then
        return opts.dispatch_send(text, send_opts, dispatch_calls)
      end
      table.insert(dispatch_calls, { text = text, opts = send_opts })
      if send_opts and send_opts.on_sent then
        send_opts.on_sent()
      end
      return true
    end,
  })

  return {
    config = config,
    deps = deps,
    dispatch_calls = dispatch_calls,
    fake_vim = fake_vim,
    formatter = formatter,
    provider = provider,
    selection = selection,
    selection_send = selection_send,
    session_id = session_id,
    session_store = session_store,
  }
end

describe("codex.context.selection_send", function()
  before_each(function()
    package.loaded["codex.context.selection_send"] = nil
  end)

  it("falls back to immediate focus when vim.schedule is unavailable", function()
    -- ========= [A]rrange =========
    local env = make_env()
    env.fake_vim.schedule = nil

    -- ========= [A]ct     =========
    local ok = env.selection_send.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.dispatch_calls)
    assert.equals(1, #env.provider.focus_calls)
  end)

  it("falls back to immediate focus when vim.schedule errors", function()
    -- ========= [A]rrange =========
    local env = make_env()
    env.fake_vim.schedule = function()
      error("schedule boom")
    end

    -- ========= [A]ct     =========
    local ok = env.selection_send.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.dispatch_calls)
    assert.equals(1, #env.provider.focus_calls)
  end)

  it("does not re-focus when the active session dies before the scheduled callback runs", function()
    -- ========= [A]rrange =========
    local env = make_env({
      dispatch_send = function(text, opts, calls)
        table.insert(calls, { text = text, opts = opts })
        if opts and opts.on_sent then
          opts.on_sent()
        end
        return true
      end,
    })

    -- ========= [A]ct     =========
    local ok = env.selection_send.send_selection()

    -- ========= [A]ssert  =========
    assert.is_true(ok)
    assert.equals(1, #env.dispatch_calls)
    assert.equals(1, #env.fake_vim._scheduled)
    assert.equals(0, #env.provider.focus_calls)

    env.session_store.mark_dead(env.session_id)
    env.fake_vim._scheduled[1]()

    assert.equals(0, #env.provider.focus_calls)
  end)
end)
