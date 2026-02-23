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
    focus_ok = true,
    focus_err = nil,
    focus_sequence = nil,
    toggle_return_new = nil,
    on_exit_callbacks = {},
    is_alive_fn = nil,
    is_ready_fn = nil,
    send_fn = nil,
    get_bufnr_fn = nil,
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
    if provider.send_fn then
      return provider.send_fn(handle, text)
    end
    return provider.send_ok, provider.send_err
  end

  function provider.focus(handle)
    table.insert(provider.focus_calls, handle)
    if provider.focus_sequence and #provider.focus_sequence > 0 then
      local next_focus = table.remove(provider.focus_sequence, 1)
      if type(next_focus) == "table" then
        return next_focus.ok, next_focus.err
      end
      return next_focus
    end

    return provider.focus_ok, provider.focus_err
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
    if provider.is_alive_fn then
      return provider.is_alive_fn(handle)
    end
    return handle and handle.alive ~= false
  end

  function provider.is_ready(handle)
    if provider.is_ready_fn then
      return provider.is_ready_fn(handle)
    end
    return provider.is_alive(handle)
  end

  function provider.get_bufnr(handle)
    if provider.get_bufnr_fn then
      return provider.get_bufnr_fn(handle)
    end
    return nil
  end

  return provider
end

local function make_logger()
  local logger = {
    set_levels = {},
    errors = {},
    debugs = {},
    warns = {},
  }

  function logger.set_level(level)
    table.insert(logger.set_levels, level)
  end

  function logger.debug(msg, ...)
    table.insert(logger.debugs, string.format(msg, ...))
  end

  function logger.info() end
  function logger.warn(msg, ...)
    table.insert(logger.warns, string.format(msg, ...))
  end

  function logger.error(msg, ...)
    table.insert(logger.errors, string.format(msg, ...))
  end

  return logger
end

local function make_formatter()
  local formatter = {
    selection_specs = {},
    mention_paths = {},
    selection_payload = "[selection]",
  }

  function formatter.format_selection(spec)
    table.insert(formatter.selection_specs, spec)
    return formatter.selection_payload
  end

  function formatter.format_mention(path)
    table.insert(formatter.mention_paths, path)
    return "/mention " .. path
  end

  return formatter
end

local function make_selection()
  local selection = {
    calls = {},
    result = {
      filepath = "test/current.lua",
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
  local replace_termcodes_calls = {}
  local input_calls = {}
  local feedkeys_calls = {}
  local buf_lines = {}
  local buf_winids = {}
  local win_cursors = {}
  local scheduled = {}
  local deferred = {}
  local runtime = { now = 0 }

  local function run_next_deferred()
    if #deferred == 0 then
      return false
    end
    local next_timer = table.remove(deferred, 1)
    runtime.now = runtime.now + next_timer.delay_ms
    next_timer.cb()
    return true
  end

  local function run_all_deferred(limit)
    local max_runs = limit or 100
    local runs = 0
    while runs < max_runs and run_next_deferred() do
      runs = runs + 1
    end
    return runs
  end

  return {
    api = {
      nvim_create_augroup = function(name, opts)
        table.insert(augroups, { name = name, opts = opts })
        return #augroups
      end,
      nvim_create_autocmd = function(event, spec)
        table.insert(autocmds, { event = event, spec = spec })
      end,
      nvim_replace_termcodes = function(str, from_part, do_lt, special)
        table.insert(replace_termcodes_calls, {
          str = str,
          from_part = from_part,
          do_lt = do_lt,
          special = special,
        })
        return "<termcoded:" .. str .. ">"
      end,
      nvim_input = function(keys)
        table.insert(input_calls, { keys = keys })
        return #keys
      end,
      nvim_feedkeys = function(keys, mode, escape_ks)
        table.insert(feedkeys_calls, {
          keys = keys,
          mode = mode,
          escape_ks = escape_ks,
        })
      end,
      nvim_buf_is_valid = function(bufnr)
        return buf_lines[bufnr] ~= nil
      end,
      nvim_buf_line_count = function(bufnr)
        local lines = buf_lines[bufnr] or {}
        return #lines
      end,
      nvim_buf_get_lines = function(bufnr, start_idx, end_idx, _strict)
        local lines = buf_lines[bufnr] or {}
        local out = {}
        for idx = start_idx + 1, math.min(end_idx, #lines) do
          table.insert(out, lines[idx])
        end
        return out
      end,
      nvim_win_get_cursor = function(winid)
        return win_cursors[winid] or { 1, 0 }
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
      fnamemodify = function(filepath, modifier)
        assert.equals(":.", modifier)
        if filepath == "/tmp/example.lua" then
          return "../../tmp/example.lua"
        end
        if filepath == "/test/current-buffer.lua" then
          return "../current-buffer.lua"
        end
        return filepath
      end,
      bufwinid = function(bufnr)
        return buf_winids[bufnr] or -1
      end,
    },
    schedule = function(cb)
      table.insert(scheduled, cb)
    end,
    defer_fn = function(cb, delay_ms)
      table.insert(deferred, { cb = cb, delay_ms = delay_ms })
    end,
    uv = {
      now = function()
        return runtime.now
      end,
    },
    deepcopy = vim.deepcopy,
    _augroups = augroups,
    _autocmds = autocmds,
    _replace_termcodes_calls = replace_termcodes_calls,
    _input_calls = input_calls,
    _feedkeys_calls = feedkeys_calls,
    _scheduled = scheduled,
    _deferred = deferred,
    _runtime = runtime,
    _run_next_deferred = run_next_deferred,
    _run_all_deferred = run_all_deferred,
    _set_buf_lines = function(bufnr, lines)
      buf_lines[bufnr] = vim.deepcopy(lines)
    end,
    _set_buf_cursor = function(bufnr, winid, row, col)
      buf_winids[bufnr] = winid
      win_cursors[winid] = { row, col }
    end,
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
  local call_order = {}

  local commands = { register_calls = 0 }
  function commands.register()
    commands.register_calls = commands.register_calls + 1
    table.insert(call_order, "commands")
  end

  local keymaps = { register_calls = 0 }
  function keymaps.register()
    keymaps.register_calls = keymaps.register_calls + 1
    table.insert(call_order, "keymaps")
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
      keymaps = keymaps,
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
    keymaps = keymaps,
    call_order = call_order,
    providers = providers,
  }
end

---@param fake_vim table
---@param runs integer
---@return nil
local function run_deferred(fake_vim, runs)
  for _ = 1, runs do
    if not fake_vim._run_next_deferred() then
      return
    end
  end
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

  it("requires setup before clear_input", function()
    local codex = require("codex")
    assert.has_error(function()
      codex.clear_input()
    end, "codex.nvim: call require('codex').setup() first")
  end)

  it("setup uses injected dependencies and strips _deps from config", function()
    local env = setup_with_deps({ log_level = "info" })

    assert.equals(1, env.commands.register_calls)
    assert.equals(1, env.keymaps.register_calls)
    assert.same({ "commands", "keymaps" }, env.call_order)
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

  it("toggle opens a fresh session when active handle is stale", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    env.codex.toggle()

    assert.equals(2, #env.provider.open_calls)
    assert.equals(0, #env.provider.toggle_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
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
    assert.equals(0, #env.provider.focus_calls)
    assert.matches("failed to send text: boom", env.logger.errors[1])
  end)

  it("send focuses active terminal after successful send", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    env.codex.send("hello")

    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
  end)

  it("send reopens session when active handle is stale", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    env.codex.send("hello")

    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals("hello", env.provider.send_calls[1].text)
  end)

  it("send toggles and re-focuses when initial focus fails", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle
    local replacement_handle = { id = "replacement", alive = true }
    env.provider.focus_sequence = {
      { ok = false, err = "terminal window not found" },
      { ok = true },
    }
    env.provider.toggle_return_new = replacement_handle

    env.codex.send("hello")

    assert.equals(1, #env.provider.send_calls)
    assert.equals(2, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.same(replacement_handle, env.provider.focus_calls[2])
    assert.equals(1, #env.provider.toggle_calls)
    assert.same(active_handle, env.provider.toggle_calls[1].handle)
    assert.same(replacement_handle, env.store.get_active().handle)
  end)

  it("clear_input sends a translated Ctrl-C sequence to the active session", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    local ok, err = env.codex.clear_input()

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(1, #env.fake_vim._replace_termcodes_calls)
    assert.same({
      str = "<C-c>",
      from_part = true,
      do_lt = false,
      special = true,
    }, env.fake_vim._replace_termcodes_calls[1])
    assert.equals(1, #env.provider.send_calls)
    assert.same(active_handle, env.provider.send_calls[1].handle)
    assert.equals("<termcoded:<C-c>>", env.provider.send_calls[1].text)
  end)

  it("clear_input returns false when there is no active session", function()
    local env = setup_with_deps()

    local ok, err = env.codex.clear_input()

    assert.is_false(ok)
    assert.equals("no active Codex session", err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("clear_input returns false when the active session handle is stale", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.store.get_active().handle.alive = false

    local ok, err = env.codex.clear_input()

    assert.is_false(ok)
    assert.equals("no active Codex session", err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
  end)

  it("clear_input returns provider send errors", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    local ok, err = env.codex.clear_input()

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("<termcoded:<C-c>>", env.provider.send_calls[1].text)
  end)

  it("send_command opens with focus when no active session", function()
    local env = setup_with_deps()

    local ok = env.codex.send_command("status")

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("/status\n", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
  end)

  it("send_command focuses existing session and sends slash command", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    local ok = env.codex.send_command("model")

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.equals("/model\n", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
  end)

  it("send_command normalizes slash prefix and logs send failures", function()
    local env = setup_with_deps()
    env.provider.send_ok = false
    env.provider.send_err = "boom"

    local ok, err = env.codex.send_command("/compact")

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.equals("/compact\n", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.matches("failed to send command /compact: boom", env.logger.errors[1])
  end)

  it("send_command queues when terminal is starting and flushes later", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    local ok, err = env.codex.send_command("status")

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("/status\n", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.equals(1, #env.provider.focus_calls)
  end)

  it("send_command waits for provider readiness even when process is alive", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 300, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and true
    end
    env.provider.is_ready_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 150
    end

    local ok, err = env.codex.send_command("status")

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 2)
    assert.equals(0, #env.provider.send_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("/status\n", env.provider.send_calls[1].text)
    assert.equals(0, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
  end)

  it("set_model dispatches /model", function()
    local env = setup_with_deps()

    local ok = env.codex.set_model()

    assert.is_true(ok)
    assert.equals("/model\n", env.provider.send_calls[1].text)
  end)

  it("show_status dispatches /status", function()
    local env = setup_with_deps()

    local ok = env.codex.show_status()

    assert.is_true(ok)
    assert.equals("/status\n", env.provider.send_calls[1].text)
  end)

  it("show_permissions dispatches /permissions", function()
    local env = setup_with_deps()

    local ok = env.codex.show_permissions()

    assert.is_true(ok)
    assert.equals("/permissions\n", env.provider.send_calls[1].text)
  end)

  it("compact dispatches /compact", function()
    local env = setup_with_deps()

    local ok = env.codex.compact()

    assert.is_true(ok)
    assert.equals("/compact\n", env.provider.send_calls[1].text)
  end)

  it("review dispatches /review when no instructions are provided", function()
    local env = setup_with_deps()

    local ok = env.codex.review()

    assert.is_true(ok)
    assert.equals("/review\n", env.provider.send_calls[1].text)
  end)

  it("review dispatches /review with inline instructions", function()
    local env = setup_with_deps()

    local ok = env.codex.review("focus on security")

    assert.is_true(ok)
    assert.equals("/review focus on security\n", env.provider.send_calls[1].text)
  end)

  it("review treats empty instructions as plain /review", function()
    local env = setup_with_deps()

    local ok = env.codex.review("")

    assert.is_true(ok)
    assert.equals("/review\n", env.provider.send_calls[1].text)
  end)

  it("review opens with focus when no active session exists", function()
    local env = setup_with_deps()

    local ok = env.codex.review()

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals("/review\n", env.provider.send_calls[1].text)
  end)

  it("show_diff dispatches /diff", function()
    local env = setup_with_deps()

    local ok = env.codex.show_diff()

    assert.is_true(ok)
    assert.equals("/diff\n", env.provider.send_calls[1].text)
  end)

  it("resume sends /resume when an active session exists", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local active_handle = env.store.get_active().handle

    local ok = env.codex.resume()

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals(1, #env.provider.focus_calls)
    assert.same(active_handle, env.provider.focus_calls[1])
    assert.equals("/resume\n", env.provider.send_calls[1].text)
  end)

  it("resume opens `codex resume` when no active session exists", function()
    local env = setup_with_deps()

    local ok = env.codex.resume()

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.same({ "resume" }, env.provider.open_calls[1].args)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(0, #env.provider.send_calls)
  end)

  it("resume opens `codex resume --last` when last=true and no active session exists", function()
    local env = setup_with_deps()

    local ok = env.codex.resume({ last = true })

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.same({ "resume", "--last" }, env.provider.open_calls[1].args)
    assert.equals(0, #env.provider.send_calls)
  end)

  it("resume ignores last flag when dispatching to active session slash command", function()
    local env = setup_with_deps()
    env.codex.open(false)

    local ok = env.codex.resume({ last = true })

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals("/resume\n", env.provider.send_calls[1].text)
  end)

  it("resume closes stale session before opening resume process", function()
    local env = setup_with_deps()
    env.codex.open(false)
    local stale_handle = env.store.get_active().handle
    stale_handle.alive = false

    local ok = env.codex.resume()

    assert.is_true(ok)
    assert.equals(2, #env.provider.open_calls)
    assert.equals(1, #env.provider.close_calls)
    assert.same(stale_handle, env.provider.close_calls[1])
    assert.same({ "resume" }, env.provider.open_calls[2].args)
    assert.equals(0, #env.provider.send_calls)
  end)

  it("send_selection formats and sends the visual payload", function()
    local env = setup_with_deps()

    local ok = env.codex.send_selection()

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(1, #env.selection.calls)
    assert.equals(env.fake_vim, env.selection.calls[1].vim_api)
    assert.equals(1, #env.formatter.selection_specs)
    assert.equals("test/current.lua", env.formatter.selection_specs[1].filepath)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~[selection]\27[201~", env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)
  end)

  it("send_selection wraps real formatter output in bracketed paste", function()
    local real_formatter = require("codex.context.formatter")
    local env = setup_with_deps({
      _deps = {
        formatter = real_formatter,
      },
    })
    env.selection.result = {
      filepath = "justfile",
      start_line = 12,
      end_line = 14,
      filetype = "",
      lines = { "```", "test-unit:" },
    }

    local ok = env.codex.send_selection()
    local expected_payload = real_formatter.format_selection(env.selection.result)

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~" .. expected_payload .. "\27[201~", env.provider.send_calls[1].text)
  end)

  it("send_selection waits for startup readiness before sending", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    local ok = env.codex.send_selection()

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 2)
    assert.equals(1, #env.provider.send_calls)
    assert.equals("\27[200~[selection]\27[201~", env.provider.send_calls[1].text)
  end)

  it("send_selection drops queued payload after startup timeout", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 120, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function()
      return false
    end

    local ok = env.codex.send_selection()

    assert.is_true(ok)
    assert.equals(0, #env.provider.send_calls)
    run_deferred(env.fake_vim, 3)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to send text: timed out waiting for terminal readiness",
      env.logger.errors[1]
    )
  end)

  it("send_selection logs and returns false when selection fails", function()
    local env = setup_with_deps()
    env.selection.err = "no visual selection range found"

    local ok, err = env.codex.send_selection()

    assert.is_false(ok)
    assert.equals("no visual selection range found", err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to collect selection: no visual selection range found",
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
    local mention_payload_expected =
      "<termcoded:<C-e>><termcoded:<C-u>>/mention ../../tmp/example.lua"

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.is_true(env.provider.open_calls[1].focus)
    assert.equals("../../tmp/example.lua", env.formatter.mention_paths[1])
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<C-e>", env.fake_vim._replace_termcodes_calls[1].str)
    assert.equals("<C-u>", env.fake_vim._replace_termcodes_calls[2].str)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.equals(1, #env.fake_vim._deferred)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
    assert.equals(1, #env.provider.focus_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equals("nt", env.fake_vim._feedkeys_calls[1].mode)
    assert.is_false(env.fake_vim._feedkeys_calls[1].escape_ks)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(2, #env.provider.focus_calls)
  end)

  it("queued payloads flush in FIFO order once startup readiness is reached", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    env.codex.send("first")
    env.codex.send("second")

    assert.equals(0, #env.provider.send_calls)
    run_deferred(env.fake_vim, 2)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("first", env.provider.send_calls[1].text)
    assert.equals("second", env.provider.send_calls[2].text)
  end)

  it("add_file waits for startup readiness before sending", function()
    local env = setup_with_deps({
      terminal = {
        startup = { timeout_ms = 200, retry_interval_ms = 50 },
      },
    })
    env.provider.is_alive_fn = function(handle)
      return handle and env.fake_vim._runtime.now >= 100
    end

    local ok = env.codex.add_file("/tmp/example.lua")
    local mention_payload_expected =
      "<termcoded:<C-e>><termcoded:<C-u>>/mention ../../tmp/example.lua"

    assert.is_true(ok)
    assert.equals(1, #env.provider.open_calls)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(0, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equals(1, #env.provider.send_calls)
  end)

  it("add_file resolves current buffer path when argument is nil", function()
    local env = setup_with_deps()

    local ok = env.codex.add_file(nil)
    local mention_payload_expected =
      "<termcoded:<C-e>><termcoded:<C-u>>/mention ../current-buffer.lua"

    assert.is_true(ok)
    assert.equals("../current-buffer.lua", env.formatter.mention_paths[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals(mention_payload_expected, env.provider.send_calls[1].text)
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)

    run_deferred(env.fake_vim, 1)
    assert.equals(3, #env.fake_vim._replace_termcodes_calls)
    assert.equals("<CR>", env.fake_vim._replace_termcodes_calls[3].str)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals("<termcoded:<CR>>", env.fake_vim._feedkeys_calls[1].keys)
    assert.equals(1, #env.provider.send_calls)
  end)

  it("add_file restores previously typed prompt text after submit", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> asdfadsfadsf" })

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("asdfadsfadsf", env.provider.send_calls[2].text)
  end)

  it("add_file skips ghost prompt text when cursor is at input start", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> Run /review on my current changes" })
    env.fake_vim._set_buf_cursor(77, 1701, 1, 2)

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.fake_vim._feedkeys_calls)
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.provider.send_calls)
  end)

  it("add_file falls back to channel submit when feedkeys throws", function()
    local env = setup_with_deps()
    env.fake_vim.api.nvim_feedkeys = function()
      error("feedkeys boom")
    end

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("\r\n", env.provider.send_calls[2].text)
    assert.matches("feedkeys submit failed, falling back to channel send", env.logger.warns[1])
  end)

  it("add_file logs submit failure when session dies before deferred submit", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> keep me" })

    local ok = env.codex.add_file("/tmp/example.lua")
    env.store.get_active().handle.alive = false

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(1, #env.fake_vim._deferred)

    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
    assert.matches("failed to submit /mention: no active Codex session", env.logger.errors[1])
  end)

  it("add_file propagates on_sent callback errors through command failure logging", function()
    local env = setup_with_deps()
    env.fake_vim.defer_fn = function()
      error("defer callback boom")
    end

    local ok, err = env.codex.add_file("/tmp/example.lua")

    assert.is_false(ok)
    assert.matches("defer callback boom", err)
    assert.matches("failed to send command /mention: .*defer callback boom", env.logger.errors[1])
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("add_file logs restore dispatch failure without crashing", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "> asdfadsfadsf" })
    env.provider.send_fn = function(_, text)
      if text == "asdfadsfadsf" then
        return false, "restore boom"
      end
      return true
    end

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)

    assert.equals(2, #env.provider.send_calls)
    assert.equals("asdfadsfadsf", env.provider.send_calls[2].text)
    local saw_restore_log = false
    for _, err in ipairs(env.logger.errors) do
      if err:match("failed to restore terminal input after /mention: restore boom") then
        saw_restore_log = true
        break
      end
    end
    assert.is_true(saw_restore_log)
  end)

  it("add_file captures prompt text from a non-last line within lookback window", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "line 1",
      "line 2",
      "line 3",
      "> within-lookback",
      "line 5",
      "line 6",
      "line 7",
      "line 8",
      "line 9",
      "line 10",
      "line 11",
      "line 12",
    })

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)

    assert.equals(2, #env.provider.send_calls)
    assert.equals("within-lookback", env.provider.send_calls[2].text)
  end)

  it("add_file does not capture prompt text beyond lookback window", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "> too-far",
      "line 2",
      "line 3",
      "line 4",
      "line 5",
      "line 6",
      "line 7",
      "line 8",
      "line 9",
      "line 10",
      "line 11",
      "line 12",
      "line 13",
      "line 14",
      "line 15",
      "line 16",
      "line 17",
      "line 18",
      "line 19",
      "line 20",
    })

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("add_file captures prompt text when cursor is on a different line", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "> draft-from-line-one",
      "non-prompt cursor line",
    })
    env.fake_vim._set_buf_cursor(77, 1702, 2, 0)

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("draft-from-line-one", env.provider.send_calls[2].text)
  end)

  it("add_file skips restore when active terminal buffer is empty", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {})

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    assert.equals(1, #env.provider.send_calls)
    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("add_file parses normalized prompt tails and strips ANSI escapes", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, {
      "\27[32m> old\27[0m\r\27[33m> final-colored-draft\27[0m",
    })

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    run_deferred(env.fake_vim, 1)
    assert.equals(2, #env.provider.send_calls)
    assert.equals("final-colored-draft", env.provider.send_calls[2].text)
  end)

  it("add_file rejects prompt tokens that contain word characters", function()
    local env = setup_with_deps()
    env.codex.open(false)
    env.provider.get_bufnr_fn = function()
      return 77
    end
    env.fake_vim._set_buf_lines(77, { "gpt-5 > should-not-restore" })

    local ok = env.codex.add_file("/tmp/example.lua")

    assert.is_true(ok)
    run_deferred(env.fake_vim, 1)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(0, #env.fake_vim._deferred)
  end)

  it("add_file captures indented prompt input and skips empty prompt input", function()
    local capture_env = setup_with_deps()
    capture_env.codex.open(false)
    capture_env.provider.get_bufnr_fn = function()
      return 77
    end
    capture_env.fake_vim._set_buf_lines(77, { "   › indented-draft" })

    local ok_capture = capture_env.codex.add_file("/tmp/example.lua")
    assert.is_true(ok_capture)
    run_deferred(capture_env.fake_vim, 1)
    run_deferred(capture_env.fake_vim, 1)
    assert.equals("indented-draft", capture_env.provider.send_calls[2].text)

    local skip_env = setup_with_deps()
    skip_env.codex.open(false)
    skip_env.provider.get_bufnr_fn = function()
      return 77
    end
    skip_env.fake_vim._set_buf_lines(77, { "> " })

    local ok_skip = skip_env.codex.add_file("/tmp/example.lua")
    assert.is_true(ok_skip)
    run_deferred(skip_env.fake_vim, 1)
    assert.equals(1, #skip_env.provider.send_calls)
    assert.equals(0, #skip_env.fake_vim._deferred)
  end)

  it("add_file returns provider send errors with command context", function()
    local env = setup_with_deps()
    env.provider.send_fn = function(_, text)
      if text:match("/mention ") then
        return false, "boom"
      end
      return true
    end

    local ok, err = env.codex.add_file("/tmp/example.lua")

    assert.is_false(ok)
    assert.equals("boom", err)
    assert.matches("failed to send command /mention: boom", env.logger.errors[1])
    assert.equals(0, #env.fake_vim._deferred)
    assert.equals(1, #env.provider.send_calls)
    assert.equals(2, #env.fake_vim._replace_termcodes_calls)
    assert.equals(0, #env.fake_vim._input_calls)
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
    assert.equals("current buffer has no file path", err)
    assert.equals(0, #env.provider.send_calls)
    assert.matches(
      "failed to add file context: current buffer has no file path",
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
