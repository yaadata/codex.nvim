local function make_session_store()
  local sessions = {}
  local active_id = nil
  local counter = 0

  local store = {}

  function store.create(spec)
    counter = counter + 1
    local id = "session_" .. counter
    sessions[id] = {
      id = id,
      handle = spec.handle,
      cmd = spec.cmd,
      cwd = spec.cwd,
      provider_name = spec.provider_name,
      alive = true,
    }
    active_id = id
    return id
  end

  function store.get(id)
    return sessions[id]
  end

  function store.get_active()
    if active_id then
      return sessions[active_id]
    end
    return nil
  end

  function store.set_active(id)
    active_id = id
  end

  function store.mark_dead(id)
    if sessions[id] then
      sessions[id].alive = false
    end
    if active_id == id then
      active_id = nil
    end
  end

  function store.remove(id)
    sessions[id] = nil
    if active_id == id then
      active_id = nil
    end
  end

  function store.list()
    local result = {}
    for _, session in pairs(sessions) do
      table.insert(result, session)
    end
    return result
  end

  function store.reset()
    sessions = {}
    active_id = nil
    counter = 0
  end

  return store
end

local function make_provider()
  local provider = {
    open_calls = {},
    close_calls = {},
    send_calls = {},
    focus_calls = {},
    toggle_calls = {},
    send_ok = true,
    send_err = nil,
    toggle_return_new = nil,
    on_exit_callbacks = {},
  }

  function provider.is_available()
    return true
  end

  function provider.open(cmd, args, env, config, focus, on_exit)
    table.insert(provider.open_calls, {
      cmd = cmd,
      args = args,
      env = env,
      config = config,
      focus = focus,
      on_exit = on_exit,
    })
    local handle = {
      id = "handle_" .. #provider.open_calls,
      alive = true,
    }
    table.insert(provider.on_exit_callbacks, function()
      handle.alive = false
      if on_exit then
        on_exit(handle)
      end
    end)
    return handle
  end

  function provider.close(handle)
    table.insert(provider.close_calls, handle)
    return true
  end

  function provider.send(handle, text)
    table.insert(provider.send_calls, { handle = handle, text = text })
    return provider.send_ok, provider.send_err
  end

  function provider.focus(handle)
    table.insert(provider.focus_calls, handle)
    return true
  end

  function provider.toggle(handle, cmd, args, env, config)
    table.insert(provider.toggle_calls, {
      handle = handle,
      cmd = cmd,
      args = args,
      env = env,
      config = config,
    })
    return provider.toggle_return_new
  end

  function provider.is_alive(handle)
    return handle and handle.alive ~= false
  end

  function provider.get_bufnr()
    return nil
  end

  return provider
end

local function make_logger()
  local logger = {
    set_levels = {},
    errors = {},
    debugs = {},
  }

  function logger.set_level(level)
    table.insert(logger.set_levels, level)
  end

  function logger.debug(msg, ...)
    table.insert(logger.debugs, string.format(msg, ...))
  end

  function logger.info() end
  function logger.warn() end

  function logger.error(msg, ...)
    table.insert(logger.errors, string.format(msg, ...))
  end

  return logger
end

local function make_formatter()
  local formatter = {
    selection_specs = {},
    mention_paths = {},
    selection_payload = "[selection]\n",
  }

  function formatter.format_selection(spec)
    table.insert(formatter.selection_specs, spec)
    return formatter.selection_payload
  end

  function formatter.format_mention(path)
    table.insert(formatter.mention_paths, path)
    return "/mention " .. path .. "\n"
  end

  return formatter
end

local function make_selection()
  local selection = {
    calls = {},
    result = {
      filepath = "/test/current.lua",
      start_line = 1,
      end_line = 2,
      filetype = "lua",
      lines = { "line 1", "line 2" },
    },
    err = nil,
  }

  function selection.get_visual_selection(vim_api, opts)
    table.insert(selection.calls, {
      vim_api = vim_api,
      opts = opts,
    })
    if selection.err then
      return nil, selection.err
    end
    return selection.result
  end

  return selection
end

local function make_fake_vim()
  local augroups = {}
  local autocmds = {}
  local scheduled = {}

  return {
    api = {
      nvim_create_augroup = function(name, opts)
        table.insert(augroups, { name = name, opts = opts })
        return #augroups
      end,
      nvim_create_autocmd = function(event, spec)
        table.insert(autocmds, { event = event, spec = spec })
      end,
    },
    fn = {
      getcwd = function()
        return "/test/cwd"
      end,
      expand = function(expr)
        if expr == "%:p" then
          return "/test/current-buffer.lua"
        end
        return ""
      end,
    },
    schedule = function(cb)
      table.insert(scheduled, cb)
    end,
    deepcopy = vim.deepcopy,
    _augroups = augroups,
    _autocmds = autocmds,
    _scheduled = scheduled,
  }
end

local function setup_with_deps(overrides)
  package.loaded["codex"] = nil

  local provider = make_provider()
  local store = make_session_store()
  local logger = make_logger()
  local fake_vim = make_fake_vim()
  local formatter = make_formatter()
  local selection = make_selection()

  local commands = { register_calls = 0 }
  function commands.register()
    commands.register_calls = commands.register_calls + 1
  end

  local providers = { resolve_calls = {} }
  function providers.resolve(name)
    table.insert(providers.resolve_calls, name)
    return provider, "native"
  end

  local codex = require("codex")
  codex.setup(vim.tbl_deep_extend("force", {
    cmd = "codex-test",
    args = { "--flag" },
    env = { CODEX_TEST = "1" },
    terminal = { provider = "native" },
    _deps = {
      providers = providers,
      session_store = store,
      logger = logger,
      commands = commands,
      formatter = formatter,
      selection = selection,
      vim = fake_vim,
    },
  }, overrides or {}))

  return {
    codex = codex,
    provider = provider,
    store = store,
    logger = logger,
    fake_vim = fake_vim,
    formatter = formatter,
    selection = selection,
    commands = commands,
    providers = providers,
  }
end

describe("codex.init public api", function()
  before_each(function()
    package.loaded["codex"] = nil
  end)

  it("requires setup before open", function()
    local codex = require("codex")
    assert.has_error(function()
      codex.open()
    end, "codex.nvim: call require('codex').setup() first")
  end)

  it("setup uses injected dependencies and strips _deps from config", function()
    local env = setup_with_deps({ log_level = "info" })

    assert.equals(1, env.commands.register_calls)
    assert.equals("info", env.logger.set_levels[1])
    assert.equals(1, #env.fake_vim._autocmds)
    assert.equals("VimLeavePre", env.fake_vim._autocmds[1].event)

    local cfg = env.codex.get_config()
    assert.equals("codex-test", cfg.cmd)
    assert.is_nil(cfg._deps)
  end)

  it("open creates a new session when none exists", function()
    local env = setup_with_deps()
    env.codex.open(false)

    local session = env.store.get_active()
    assert.is_not_nil(session)
    assert.equals("native", session.provider_name)
    assert.equals("codex-test", session.cmd)
    assert.equals("/test/cwd", session.cwd)
    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
  end)

  it("open reuses live session and focuses when requested", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local first_handle = env.store.get_active().handle

    env.codex.open(true)

    assert.equals(1, #env.provider.open_calls)
    assert.equals(1, #env.provider.focus_calls)
    assert.equals(first_handle, env.provider.focus_calls[1])
  end)

  it("open closes and replaces stale session", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    env.codex.open(false)

    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.equals(stale_handle, env.provider.close_calls[1])
    assert.equals("handle_2", env.store.get_active().handle.id)
  end)

  it("toggle updates handle when provider returns replacement", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local replacement = { id = "replacement", alive = true }
    env.provider.toggle_return_new = replacement

    env.codex.toggle()

    assert.equals(1, #env.provider.toggle_calls)
    assert.equals(replacement, env.store.get_active().handle)
  end)

  it("focus opens a session when none exists", function()
    local env = setup_with_deps()

    env.codex.focus()

    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
  end)

  it("send auto-opens when missing and logs provider errors", function()
    local env = setup_with_deps()
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    env.codex.send("hello")

    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
    assert.matches("failed to send text: boom", env.logger.errors[1])
  end)

  it("send_selection formats and sends the visual payload", function()
    local env = setup_with_deps()

    local ok = env.codex.send_selection()

    assert.is_true(ok)
    assert.equals(1, #env.selection.calls)
    assert.equals(env.fake_vim, env.selection.calls[1].vim_api)
    assert.equals(1, #env.formatter.selection_specs)
    assert.equals("/test/current.lua", env.formatter.selection_specs[1].filepath)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("[selection]\n", env.provider.send_calls[1].text)
  end)

  it("send_selection logs and returns false when selection fails", function()
    local env = setup_with_deps()
    env.selection.err = "codex: no visual selection range found"

    local ok, err = env.codex.send_selection()

    assert.is_false(ok)
    assert.equals("codex: no visual selection range found", err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "codex: failed to collect selection: codex: no visual selection range found",
      env.logger.errors[1]
    )
  end)

  it("send_selection forwards explicit range options to selection extractor", function()
    local env = setup_with_deps()

    env.codex.send_selection({ line1 = 3, line2 = 5 })

    assert.same({ line1 = 3, line2 = 5 }, env.selection.calls[1].opts)
  end)

  it("add_file sends /mention with explicit path", function()
    local env = setup_with_deps()

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals("/tmp/example.lua", env.formatter.mention_paths[1])
    assert.equals("/mention /tmp/example.lua\n", env.provider.send_calls[1].text)
  end)

  it("add_file resolves current buffer path when argument is nil", function()
    local env = setup_with_deps()

    local ok = env.codex.add_file(nil)

    assert.is_true(ok)
    assert.equals("/test/current-buffer.lua", env.formatter.mention_paths[1])
  end)

  it("add_file returns error when path is unavailable", function()
    local env = setup_with_deps({
      _deps = {
        vim = vim.tbl_deep_extend("force", make_fake_vim(), {
          fn = {
            expand = function()
              return ""
            end,
          },
        }),
      },
    })

    local ok, err = env.codex.add_file(nil)

    assert.is_false(ok)
    assert.equals("codex: current buffer has no file path", err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "codex: failed to add file context: codex: current buffer has no file path",
      env.logger.errors[1]
    )
  end)

  it("close removes session and is_running reflects alive state", function()
    local env = setup_with_deps()
    env.codex.open(false)
    assert.is_true(env.codex.is_running())

    env.codex.close()

    assert.equals(1, #env.provider.close_calls)
    assert.is_nil(env.store.get_active())
    assert.is_false(env.codex.is_running())
  end)

  it("auto_start schedules open(false)", function()
    local env = setup_with_deps({ auto_start = true })

    assert.equals(1, #env.fake_vim._scheduled)
    assert.equals(0, #env.provider.open_calls)

    env.fake_vim._scheduled[1]()

    assert.equals(1, #env.provider.open_calls)
    assert.is_false(env.provider.open_calls[1].focus)
  end)

  it("marks active session dead when provider exit callback fires", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local session = env.store.get_active()

    assert.is_true(env.codex.is_running())
    assert.equals(1, #env.provider.on_exit_callbacks)

    env.provider.on_exit_callbacks[1]()

    assert.is_nil(env.store.get_active())
    assert.is_false(env.codex.is_running())
    assert.is_false(session.alive)
  end)

  it("marks session dead when opened via toggle and exit callback fires", function()
    local env = setup_with_deps()
    env.codex.toggle()
    local session = env.store.get_active()

    assert.is_not_nil(session)
    assert.equals(1, #env.provider.on_exit_callbacks)

    env.provider.on_exit_callbacks[1]()

    assert.is_nil(env.store.get_active())
    assert.is_false(session.alive)
  end)
end)
