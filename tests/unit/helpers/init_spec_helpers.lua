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
    discover_restorable_calls = {},
    discover_restorable_result = {},
    attach_restored_calls = {},
    attach_restored_ok = true,
    attach_restored_err = nil,
    is_alive_fn = nil,
    is_ready_fn = nil,
    send_fn = nil,
    close_fn = nil,
    open_fn = nil,
    focus_fn = nil,
    get_bufnr_fn = nil,
    discover_restorable_fn = nil,
    attach_restored_fn = nil,
    next_open_handle = nil,
  }

  function provider.is_available()
    return true
  end

  function provider.open(cmd, args, env, config, focus, on_exit)
    local call = {
      cmd = cmd,
      args = args,
      env = env,
      config = config,
      focus = focus,
      on_exit = on_exit,
    }
    table.insert(provider.open_calls, call)
    local handle = provider.next_open_handle
      or {
        id = "handle_" .. #provider.open_calls,
        alive = true,
      }
    provider.next_open_handle = nil
    table.insert(provider.on_exit_callbacks, function()
      handle.alive = false
      if on_exit then
        on_exit(handle)
      end
    end)
    if provider.open_fn then
      provider.open_fn(call, handle)
    end
    return handle
  end

  function provider.close(handle)
    table.insert(provider.close_calls, handle)
    if provider.close_fn then
      return provider.close_fn(handle)
    end
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
    if provider.focus_fn then
      return provider.focus_fn(handle)
    end
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
    if handle and type(handle.bufnr) == "number" then
      return handle.bufnr
    end
    return nil
  end

  function provider.discover_restorable(config)
    table.insert(provider.discover_restorable_calls, {
      config = config,
    })
    if provider.discover_restorable_fn then
      return provider.discover_restorable_fn(config)
    end
    return vim.deepcopy(provider.discover_restorable_result)
  end

  function provider.attach_restored(handle, config, on_exit)
    table.insert(provider.attach_restored_calls, {
      handle = handle,
      config = config,
      on_exit = on_exit,
    })
    if provider.attach_restored_fn then
      return provider.attach_restored_fn(handle, config, on_exit)
    end
    return provider.attach_restored_ok, provider.attach_restored_err
  end

  return provider
end

local function make_logger()
  local logger = {
    set_levels = {},
    set_verboses = {},
    errors = {},
    debugs = {},
    infos = {},
    warns = {},
    vdebugs = {},
    entries = {},
  }

  local entry_counter = 0

  local function append_entry(level, message, verbose)
    entry_counter = entry_counter + 1
    table.insert(logger.entries, {
      timestamp = entry_counter,
      level = level,
      message = message,
      verbose = verbose,
    })
  end

  function logger.set_level(level)
    table.insert(logger.set_levels, level)
  end

  function logger.set_verbose(verbose)
    table.insert(logger.set_verboses, verbose)
  end

  function logger.debug(msg, ...)
    local formatted = string.format(msg, ...)
    table.insert(logger.debugs, formatted)
    append_entry("debug", formatted, false)
  end

  function logger.info(msg, ...)
    local formatted = string.format(msg, ...)
    table.insert(logger.infos, formatted)
    append_entry("info", formatted, false)
  end
  function logger.warn(msg, ...)
    local formatted = string.format(msg, ...)
    table.insert(logger.warns, formatted)
    append_entry("warn", formatted, false)
  end

  function logger.error(msg, ...)
    local formatted = string.format(msg, ...)
    table.insert(logger.errors, formatted)
    append_entry("error", formatted, false)
  end

  function logger.vdebug(msg, ...)
    local formatted = string.format(msg, ...)
    table.insert(logger.vdebugs, formatted)
    append_entry("debug", formatted, true)
  end

  function logger.get_logs()
    return vim.deepcopy(logger.entries)
  end

  function logger.clear_logs()
    logger.entries = {}
  end

  return logger
end

local function make_formatter()
  local formatter = {
    selection_specs = {},
    mention_paths = {},
    selection_payload = "[selection]\n",
    buffer_paths = {},
    buffer_payload = "[@buffer] ",
  }

  function formatter.format_selection(spec)
    table.insert(formatter.selection_specs, spec)
    return formatter.selection_payload
  end

  function formatter.format_mention(path)
    table.insert(formatter.mention_paths, path)
    return "/mention " .. path
  end

  function formatter.format_buffer_ref(path)
    table.insert(formatter.buffer_paths, path)
    return formatter.buffer_payload
  end

  return formatter
end

local function make_selection()
  local selection = {
    calls = {},
    buffer_calls = {},
    errors = {
      BUFFER_NOT_FOUND = "buffer does not exist",
      NO_FILEPATH = "current buffer has no file path",
      INVALID_FILEPATH = "current buffer path is not a regular file",
      NO_SELECTION = "no visual selection range found",
    },
    result = {
      filepath = "test/current.lua",
      start_line = 1,
      end_line = 2,
      filetype = "lua",
      lines = { "line 1", "line 2" },
    },
    err = nil,
    buffer_filepath = "test/current.lua",
    buffer_err = nil,
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

  function selection.get_current_buffer_filepath(vim_api, opts)
    table.insert(selection.buffer_calls, {
      vim_api = vim_api,
      opts = opts,
    })
    if selection.buffer_err then
      return nil, selection.buffer_err
    end
    return selection.buffer_filepath
  end

  return selection
end

local function make_fake_vim()
  local augroups = {}
  local autocmds = {}
  local replace_termcodes_calls = {}
  local input_calls = {}
  local feedkeys_calls = {}
  local setreg_calls = {}
  local notify_calls = {}
  local buf_lines = {}
  local buf_winids = {}
  local win_cursors = {}
  local win_bufs = { [1] = 1 }
  local win_valid = { [1] = true }
  local buf_valid = { [1] = true }
  local current_win = 1
  local scheduled = {}
  local deferred = {}
  local runtime = { now = 0 }

  local function fire_autocmd(event)
    for _, autocmd in ipairs(autocmds) do
      local registered = autocmd.event
      local matches = false
      if registered == event then
        matches = true
      elseif type(registered) == "table" then
        for _, item in ipairs(registered) do
          if item == event then
            matches = true
            break
          end
        end
      end

      if matches and autocmd.spec and type(autocmd.spec.callback) == "function" then
        autocmd.spec.callback()
      end
    end
  end

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
        return buf_valid[bufnr] == true or buf_lines[bufnr] ~= nil
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
      nvim_get_current_win = function()
        return current_win
      end,
      nvim_get_current_buf = function()
        return win_bufs[current_win] or -1
      end,
      nvim_set_current_win = function(winid)
        if win_valid[winid] ~= true then
          error("invalid window")
        end
        local prev_win = current_win
        local prev_buf = win_bufs[current_win]
        current_win = winid
        if prev_win ~= winid then
          fire_autocmd("WinEnter")
        end
        if prev_buf ~= win_bufs[winid] then
          fire_autocmd("BufEnter")
        end
      end,
      nvim_win_is_valid = function(winid)
        return win_valid[winid] == true
      end,
      nvim_list_wins = function()
        local wins = {}
        for winid, valid in pairs(win_valid) do
          if valid then
            table.insert(wins, winid)
          end
        end
        table.sort(wins)
        return wins
      end,
      nvim_win_get_buf = function(winid)
        return win_bufs[winid]
      end,
    },
    notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end,
    fn = {
      getcwd = function()
        return "/test/cwd"
      end,
      expand = function(expr)
        if expr == "%:p" then
          return "/test/current-buffer.lua"
        end
        if expr == "%:p:h" then
          return "/test"
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
        if filepath == "/test" then
          return ".."
        end
        if filepath == "/tmp/" then
          return "../../tmp/"
        end
        if filepath == "/tmp" then
          return "../../tmp"
        end
        return filepath
      end,
      bufwinid = function(bufnr)
        return buf_winids[bufnr] or -1
      end,
      setreg = function(reg, value)
        table.insert(setreg_calls, { reg = reg, value = value })
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
    _setreg_calls = setreg_calls,
    _notify_calls = notify_calls,
    _scheduled = scheduled,
    _deferred = deferred,
    _runtime = runtime,
    _fire_autocmd = fire_autocmd,
    _run_next_deferred = run_next_deferred,
    _run_all_deferred = run_all_deferred,
    _set_buf_lines = function(bufnr, lines)
      buf_valid[bufnr] = true
      buf_lines[bufnr] = vim.deepcopy(lines)
    end,
    _set_buf_cursor = function(bufnr, winid, row, col)
      buf_valid[bufnr] = true
      buf_winids[bufnr] = winid
      win_bufs[winid] = bufnr
      win_valid[winid] = true
      win_cursors[winid] = { row, col }
    end,
    _set_window_buf = function(winid, bufnr)
      win_valid[winid] = true
      win_bufs[winid] = bufnr
      buf_valid[bufnr] = true
    end,
    _set_current_win = function(winid)
      win_valid[winid] = true
      local prev_win = current_win
      local prev_buf = win_bufs[current_win]
      current_win = winid
      if prev_win ~= winid then
        fire_autocmd("WinEnter")
      end
      if prev_buf ~= win_bufs[winid] then
        fire_autocmd("BufEnter")
      end
    end,
    _set_win_valid = function(winid, valid)
      win_valid[winid] = valid
      if not valid and current_win == winid then
        current_win = 1
      end
    end,
    _set_buf_valid = function(bufnr, valid)
      buf_valid[bufnr] = valid
    end,
    _get_current_win = function()
      return current_win
    end,
    _get_current_buf = function()
      return win_bufs[current_win] or -1
    end,
  }
end

local function setup_with_deps(overrides)
  package.loaded["codex"] = nil

  overrides = overrides or {}

  local provider = make_provider()
  local store = make_session_store()
  local logger = make_logger()
  local fake_vim = make_fake_vim()
  local formatter = make_formatter()
  local selection = make_selection()
  local call_order = {}

  if type(overrides._provider) == "function" then
    overrides._provider(provider, fake_vim, store, logger)
  end

  local commands = { register_calls = 0 }
  function commands.register()
    commands.register_calls = commands.register_calls + 1
    table.insert(call_order, "commands")
  end

  local providers = { resolve_calls = {} }
  function providers.resolve(name)
    table.insert(providers.resolve_calls, name)
    return provider, "native"
  end

  local codex = require("codex")
  local setup_overrides = vim.deepcopy(overrides)
  setup_overrides._provider = nil
  codex.setup(vim.tbl_deep_extend("force", {
    launch = {
      cmd = "codex-test",
      args = { "--flag" },
      env = { CODEX_TEST = "1" },
    },
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
  }, setup_overrides))

  return {
    codex = codex,
    provider = provider,
    store = store,
    logger = logger,
    fake_vim = fake_vim,
    formatter = formatter,
    selection = selection,
    commands = commands,
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

return {
  make_session_store = make_session_store,
  make_provider = make_provider,
  make_logger = make_logger,
  make_formatter = make_formatter,
  make_selection = make_selection,
  make_fake_vim = make_fake_vim,
  setup_with_deps = setup_with_deps,
  run_deferred = run_deferred,
}
