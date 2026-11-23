local log = require("codex.logger")
local keymaps = require("codex.nvim.keymaps")
local terminal_utils = require("codex.providers.terminal_utils")

local M = {}

---Apply the shared split size to a visible Snacks terminal.
---@param handle codex.ProviderHandle
local function maintain_size(handle)
  local term = handle.terminal
  if not term or type(term.buf) ~= "number" then
    return
  end
  local position = (term.opts and term.opts.position) or handle.codex_split_position
  local vertical = position == "left" or position == "right"
  local horizontal = position == "top" or position == "bottom"
  if not vertical and not horizontal then
    return
  end
  local winid = terminal_utils.find_win_for_buf(term.buf)
  if winid then
    local direction = vertical and "vertical" or "horizontal"
    local size_pct = vertical and (handle.codex_split_width_pct or 40)
      or (handle.codex_split_height_pct or 30)
    terminal_utils.maintain_split_size(winid, term.buf, direction, size_pct)
  end
end

local function configure_size(handle, config)
  local provider_opts = config.terminal.provider_opts or {}
  local native = provider_opts.native or {}
  local snacks = provider_opts.snacks or {}
  handle.codex_split_width_pct = (native.vsplit or {}).size_pct or 40
  handle.codex_split_height_pct = (native.hsplit or {}).size_pct or 30
  handle.codex_split_position = (snacks.win or {}).position
end

--- Return true if the snacks.nvim terminal module is loadable.
---@return boolean
function M.is_available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks ~= nil and snacks.terminal ~= nil
end

--- Return the current monotonic time in milliseconds.
---@return integer
local function now_ms()
  local uv = vim.uv or vim.loop
  if not uv or type(uv.now) ~= "function" then
    return 0
  end
  return uv.now()
end

--- Resolve the job channel id from a snacks terminal object.
---@param term table
---@return integer|nil
local function resolve_jobid(term)
  if type(term.jobid) == "number" and term.jobid > 0 then
    return term.jobid
  end

  local bufnr = term.buf
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local ok_channel, channel = pcall(vim.api.nvim_get_option_value, "channel", { buf = bufnr })
  if ok_channel and type(channel) == "number" and channel > 0 then
    return channel
  end

  local ok, jobid = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if not ok then
    return nil
  end

  if type(jobid) == "number" and jobid > 0 then
    return jobid
  end

  return nil
end

---Build an attached terminal wrapper around an already-running terminal buffer.
---@param snacks table
---@param config codex.ProfileConfig
---@param bufnr integer
---@return table|nil
local function create_attached_terminal(snacks, config, bufnr, restored_winid)
  local win_factory = snacks.win
  if type(win_factory) == "table" then
    local mt = getmetatable(win_factory)
    if type(mt) == "table" and type(mt.__call) == "function" then
      win_factory = function(...)
        return snacks.win(...)
      end
    end
  end

  if type(win_factory) ~= "function" then
    return nil
  end

  local provider_opts = config.terminal.provider_opts or {}
  local snacks_opts = provider_opts.snacks or {}
  local win_obj = nil
  local terminal = {
    buf = bufnr,
    win = restored_winid,
  }

  local function sync_win()
    if
      terminal.win
      and vim.api.nvim_win_is_valid(terminal.win)
      and vim.api.nvim_win_get_buf(terminal.win) == terminal.buf
    then
      return terminal.win
    end
    terminal.win = terminal_utils.find_win_for_buf(terminal.buf)
    return terminal.win
  end

  local function ensure_win_obj()
    if win_obj then
      return win_obj
    end
    win_obj = win_factory(vim.tbl_deep_extend("force", snacks_opts.win or {}, {
      buf = terminal.buf,
      show = false,
    }))
    return win_obj
  end

  function terminal:show()
    local existing = sync_win()
    if existing then
      self.win = existing
      return
    end
    local win = ensure_win_obj()
    if win and win.show then
      win:show()
      self.win = win.win or terminal_utils.find_win_for_buf(self.buf)
    end
  end

  function terminal:focus()
    self:show()
    local winid = sync_win()
    if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_set_current_win(winid)
      self.win = winid
    end
  end

  function terminal:toggle()
    local winid = sync_win()
    if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, false)
      self.win = nil
      return self
    end
    self:show()
    return self
  end

  function terminal:close()
    local jobid = resolve_jobid(self)
    if jobid then
      pcall(vim.fn.jobstop, jobid)
      self.jobid = nil
    end
    local winid = sync_win()
    if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
      pcall(vim.api.nvim_win_close, winid, true)
    end
    if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
      pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
    end
    self.buf = nil
    self.win = nil
  end

  return terminal
end

---Register TermClose handling for a restored terminal buffer.
---@param handle codex.ProviderHandle
---@param auto_close boolean
---@param on_exit? fun(handle: codex.ProviderHandle): nil
---@return nil
local function register_restored_exit_autocmd(handle, auto_close, on_exit)
  local api = vim.api
  local term = handle.terminal
  if type(term) ~= "table" or type(term.buf) ~= "number" then
    return
  end

  api.nvim_create_autocmd("TermClose", {
    buffer = term.buf,
    once = true,
    callback = function()
      if on_exit then
        on_exit(handle)
      end

      if auto_close and handle.terminal and handle.terminal.close then
        vim.schedule(function()
          local ok, err = pcall(function()
            handle.terminal:close()
          end)
          if not ok then
            log.debug("snacks: failed to auto-close recovered terminal: %s", tostring(err))
          end
          pcall(vim.cmd, "checktime")
        end)
      end
    end,
  })
end

--- Open a terminal via snacks.terminal and return its handle.
---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.ProfileConfig
---@param focus boolean
---@param on_exit? fun(handle: codex.ProviderHandle): nil
---@return codex.ProviderHandle handle
function M.open(cmd, args, env, config, focus, on_exit)
  local snacks = require("snacks")
  local argv = terminal_utils.command_argv(cmd, args)
  local launch = config.launch or {}
  local cwd = launch.cwd or vim.fn.getcwd()
  local provider_opts = config.terminal.provider_opts or {}
  local snacks_opts = provider_opts.snacks or {}
  local auto_close = config.terminal.auto_close == true

  local base_opts = {
    interactive = true,
    -- Keep Snacks auto_close disabled so codex controls TermClose behavior and
    -- avoids Snacks non-zero exit notifications for intentional closes.
    auto_close = false,
  }

  local opts = vim.tbl_deep_extend("force", base_opts, snacks_opts)
  opts.cmd = argv
  opts.cwd = cwd
  if next(env) ~= nil then
    opts.env = vim.deepcopy(env)
  else
    opts.env = nil
  end
  if config.snacks_count ~= nil then
    opts.count = config.snacks_count
  end

  local terminal = snacks.terminal(argv, opts)

  if focus and terminal.show then
    terminal:show()
  end

  local startup = config.terminal.startup or {}
  local handle = {
    terminal = terminal,
    provider = "snacks",
    ready_at_ms = now_ms() + (startup.grace_ms or 0),
  }

  configure_size(handle, config)
  maintain_size(handle)

  if type(terminal.buf) == "number" then
    terminal_utils.set_codex_terminal_marker(
      terminal.buf,
      "snacks",
      table.concat(argv, " "),
      cwd,
      config.profile_name
    )
    keymaps.apply_terminal(terminal.buf, config.terminal.keymaps, config.profile_name)
  end

  if terminal.buf and (on_exit or auto_close) then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = terminal.buf,
      once = true,
      callback = function()
        if on_exit then
          on_exit(handle)
        end

        if auto_close and handle.terminal and handle.terminal.close then
          vim.schedule(function()
            local ok, err = pcall(function()
              handle.terminal:close()
            end)
            if not ok then
              log.debug("snacks: failed to auto-close terminal on TermClose: %s", tostring(err))
            end
            pcall(vim.cmd, "checktime")
          end)
        end
      end,
    })
  end

  log.debug("snacks: opened terminal")
  return handle
end

---Discover live Codex terminal buffers that can be reattached.
---@param config codex.ProfileConfig
---@return codex.RestoredSessionSpec[]
function M.discover_restorable(config)
  if not M.is_available() then
    return {}
  end

  local api = vim.api

  local snacks = require("snacks")
  local launch = config.launch or {}
  local cwd_fallback = launch.cwd or vim.fn.getcwd()
  ---@type codex.RestoredSessionSpec[]
  local restored = {}

  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(bufnr) then
      local jobid = resolve_jobid({ buf = bufnr })
      if terminal_utils.is_live_job(jobid) then
        local marker = terminal_utils.get_buffer_var(bufnr, "codex_terminal")
        local snacks_term = terminal_utils.get_buffer_var(bufnr, "snacks_terminal")
        local name = api.nvim_buf_get_name(bufnr)
        local metadata = type(marker) == "table" and marker or {}
        local snacks_metadata = type(snacks_term) == "table" and snacks_term or {}
        local winid = terminal_utils.find_win_for_buf(bufnr)
        local candidate = {
          cmd = metadata.cmd or snacks_metadata.cmd or terminal_utils.extract_terminal_command(
            name
          ),
          cwd = metadata.cwd or snacks_metadata.cwd or terminal_utils.extract_terminal_cwd(name),
          split = terminal_utils.window_split_type(winid),
        }

        if terminal_utils.matches_restorable_owner(marker, "snacks", config, candidate) then
          local terminal = create_attached_terminal(snacks, config, bufnr, winid)
          if terminal then
            local cmd = candidate.cmd
            local handle = {
              terminal = terminal,
              provider = "snacks",
              ready_at_ms = now_ms(),
              cmd = type(cmd) == "table" and table.concat(cmd, " ") or cmd or "",
              cwd = candidate.cwd or cwd_fallback,
            }
            table.insert(restored, {
              handle = handle,
              cmd = handle.cmd,
              cwd = handle.cwd,
              bufnr = bufnr,
              winid = terminal.win,
            })
          end
        end
      end
    end
  end

  return restored
end

---Apply post-selection setup for a restored snacks terminal handle.
---@param handle codex.ProviderHandle
---@param config codex.ProfileConfig
---@param on_exit? fun(handle: codex.ProviderHandle): nil
---@return boolean ok
---@return string|nil err
function M.attach_restored(handle, config, on_exit)
  local term = type(handle) == "table" and handle.terminal or nil
  if type(term) ~= "table" or type(term.buf) ~= "number" then
    return false, "invalid restored terminal handle"
  end

  configure_size(handle, config)
  maintain_size(handle)
  register_restored_exit_autocmd(handle, config.terminal.auto_close == true, on_exit)
  keymaps.apply_terminal(term.buf, config.terminal.keymaps, config.profile_name)
  terminal_utils.set_codex_terminal_marker(
    term.buf,
    "snacks",
    handle.cmd,
    handle.cwd,
    config.profile_name
  )
  return true
end

--- Close the snacks terminal session.
---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.close(handle)
  if not handle or not handle.terminal then
    return true
  end

  if handle.terminal.close then
    handle.terminal:close()
  end

  return true
end

--- Send text to the snacks terminal job channel.
---@param handle codex.ProviderHandle|nil
---@param text string
---@return boolean ok
---@return string|nil err
function M.send(handle, text)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  local term = handle.terminal
  local jobid = resolve_jobid(term)
  if jobid then
    vim.fn.chansend(jobid, text)
    return true
  end

  return false, "terminal has no job"
end

--- Show the snacks terminal and enter insert mode.
---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.focus(handle)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  local term = handle.terminal
  if term.show then
    term:show()
  end

  if term.focus then
    term:focus()
  elseif not term.show then
    return false, "cannot focus terminal"
  end

  maintain_size(handle)
  local term_buf = type(term.buf) == "number" and term.buf or nil
  if term_buf then
    local current_buf = vim.api.nvim_get_current_buf()
    if current_buf ~= term_buf then
      if
        type(term.win) == "number"
        and vim.api.nvim_win_is_valid(term.win)
        and pcall(vim.api.nvim_set_current_win, term.win)
      then
        current_buf = vim.api.nvim_get_current_buf()
      end
      if current_buf ~= term_buf then
        return false, "terminal window not focused"
      end
    end
  end

  local ok, err = pcall(vim.cmd, "startinsert")
  if not ok then
    return false, err
  end
  return true
end

--- Toggle the snacks terminal visibility, opening a new one if needed.
---@param handle codex.ProviderHandle|nil
---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.ProfileConfig
---@return codex.ProviderHandle|nil new_handle
---@return string|nil err
function M.toggle(handle, cmd, args, env, config)
  if not handle or not M.is_alive(handle) then
    return M.open(cmd, args, env, config, true)
  end

  if handle.terminal.toggle then
    handle.terminal:toggle()
  end
  maintain_size(handle)

  return handle
end

--- Return true if the snacks terminal has an active job channel.
---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_alive(handle)
  if not handle or not handle.terminal then
    return false
  end

  local term = handle.terminal
  return resolve_jobid(term) ~= nil
end

--- Return true if the terminal is alive and the startup grace period has elapsed.
---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_ready(handle)
  if not M.is_alive(handle) then
    return false
  end

  if type(handle.ready_at_ms) ~= "number" then
    return true
  end

  return now_ms() >= handle.ready_at_ms
end

--- Return the buffer number from a snacks terminal handle, or nil.
---@param handle codex.ProviderHandle|nil
---@return integer|nil bufnr
function M.get_bufnr(handle)
  if handle and handle.terminal then
    return handle.terminal.buf
  end
  return nil
end

return M
