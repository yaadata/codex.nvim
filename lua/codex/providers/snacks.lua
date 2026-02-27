local log = require("codex.logger")

local M = {}

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

--- Join the command and its arguments into a single shell string.
---@param cmd string
---@param args string[]
---@return string
local function build_cmd(cmd, args)
  local parts = { cmd }
  for _, arg in ipairs(args) do
    table.insert(parts, arg)
  end
  return table.concat(parts, " ")
end

--- Register buffer-local terminal-mode keymaps for toggle, close, and navigation.
---@param bufnr integer
---@param keymaps codex.TerminalKeymapConfig|nil
---@param window_type codex.WindowType|nil
---@return nil
local function set_terminal_keymaps(bufnr, keymaps, window_type)
  local maps = vim.tbl_deep_extend("force", {
    toggle = "<C-c>",
    clear_input = "<M-BS>",
    close = false,
    nav = {
      left = "<C-h>",
      down = "<C-j>",
      up = "<C-k>",
      right = "<C-l>",
    },
  }, keymaps or {})

  if maps.toggle then
    vim.keymap.set("t", maps.toggle, function()
      require("codex").toggle()
    end, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = "Codex: Toggle terminal",
    })
  end

  if maps.clear_input then
    vim.keymap.set("t", maps.clear_input, function()
      require("codex").clear_input()
    end, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = "Codex: Clear input",
    })
  end

  if maps.close then
    vim.keymap.set("t", maps.close, function()
      vim.schedule(function()
        require("codex").close()
      end)
    end, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = "Codex: Close terminal",
    })
  end

  if (window_type == "vsplit" or window_type == "hsplit") and maps.nav then
    local nav = {
      { maps.nav.left, "<C-\\><C-n><C-w>h", "Codex: Move to left window" },
      { maps.nav.down, "<C-\\><C-n><C-w>j", "Codex: Move to below window" },
      { maps.nav.up, "<C-\\><C-n><C-w>k", "Codex: Move to above window" },
      { maps.nav.right, "<C-\\><C-n><C-w>l", "Codex: Move to right window" },
    }

    for _, map in ipairs(nav) do
      if map[1] then
        vim.keymap.set("t", map[1], map[2], {
          buffer = bufnr,
          silent = true,
          nowait = true,
          desc = map[3],
        })
      end
    end
  end
end

--- Open a terminal via snacks.terminal and return its handle.
---@param cmd string
---@param args string[]
---@param env table<string, string>
---@param config codex.Config
---@param focus boolean
---@param on_exit? fun(handle: codex.ProviderHandle): nil
---@return codex.ProviderHandle handle
function M.open(cmd, args, env, config, focus, on_exit)
  local snacks = require("snacks")
  local full_cmd = build_cmd(cmd, args)
  local launch = config.launch or {}
  local cwd = launch.cwd or vim.fn.getcwd()
  local snacks_opts = config.terminal.provider_opts.snacks or {}

  local base_opts = {
    cmd = full_cmd,
    cwd = cwd,
    interactive = true,
    auto_close = config.terminal.auto_close == true,
  }
  if config.terminal.window == "float" then
    local float = config.terminal.float or {}
    base_opts.win = {
      position = "float",
      border = float.border or "rounded",
    }
  elseif config.terminal.window == "vsplit" then
    local vsplit = config.terminal.vsplit or {}
    base_opts.win = {
      position = vsplit.side or "right",
      width = (vsplit.size_pct or 40) / 100,
    }
  elseif config.terminal.window == "hsplit" then
    local hsplit = config.terminal.hsplit or {}
    base_opts.win = {
      position = hsplit.side or "bottom",
      height = (hsplit.size_pct or 30) / 100,
    }
  end
  if next(env) ~= nil then
    base_opts.env = env
  end

  local opts = vim.tbl_deep_extend("force", base_opts, snacks_opts)

  local terminal = snacks.terminal(full_cmd, opts)

  if focus and terminal.show then
    terminal:show()
  end

  local startup = config.terminal.startup or {}
  local handle = {
    terminal = terminal,
    provider = "snacks",
    ready_at_ms = now_ms() + (startup.grace_ms or 0),
  }

  if type(terminal.buf) == "number" then
    set_terminal_keymaps(terminal.buf, config.terminal.keymaps, config.terminal.window)
  end

  if on_exit and terminal.buf then
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = terminal.buf,
      once = true,
      callback = function()
        on_exit(handle)
      end,
    })
  end

  log.debug("snacks: opened terminal")
  return handle
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
---@param config codex.Config
---@return codex.ProviderHandle|nil new_handle
---@return string|nil err
function M.toggle(handle, cmd, args, env, config)
  if not handle or not M.is_alive(handle) then
    return M.open(cmd, args, env, config, true)
  end

  if handle.terminal.toggle then
    handle.terminal:toggle()
  end

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
