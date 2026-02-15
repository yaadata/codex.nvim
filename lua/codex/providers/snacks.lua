local log = require("codex.logger")

local M = {}

---@return boolean
function M.is_available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks ~= nil and snacks.terminal ~= nil
end

---@return integer
local function now_ms()
  local uv = vim.uv or vim.loop
  if not uv or type(uv.now) ~= "function" then
    return 0
  end
  return uv.now()
end

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

---@param bufnr integer
---@param keymaps codex.TerminalKeymapConfig|nil
---@param window_type codex.WindowType|nil
---@return nil
local function set_terminal_keymaps(bufnr, keymaps, window_type)
  local maps = vim.tbl_deep_extend("force", {
    toggle = "<C-c>",
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
  local cwd = config.cwd or vim.fn.getcwd()
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

---@param handle codex.ProviderHandle|nil
---@return boolean ok
---@return string|nil err
function M.focus(handle)
  if not handle or not handle.terminal then
    return false, "no active terminal"
  end

  if handle.terminal.show then
    handle.terminal:show()
    vim.cmd("startinsert")
    return true
  end

  return false, "cannot focus terminal"
end

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

---@param handle codex.ProviderHandle|nil
---@return boolean
function M.is_alive(handle)
  if not handle or not handle.terminal then
    return false
  end

  local term = handle.terminal
  return resolve_jobid(term) ~= nil
end

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

---@param handle codex.ProviderHandle|nil
---@return integer|nil bufnr
function M.get_bufnr(handle)
  if handle and handle.terminal then
    return handle.terminal.buf
  end
  return nil
end

return M
