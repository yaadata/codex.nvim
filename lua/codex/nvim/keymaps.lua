local M = {}
local CTRL_V = string.char(22)

---@class codex.RegisteredKeymap
---@field mode string
---@field lhs string

---@type codex.RegisteredKeymap[]
local registered = {}

--- Return true if a mapping already exists for the given mode and lhs.
---@param vim_api table
---@param mode string
---@param lhs string
---@return boolean
local function mapping_exists(vim_api, mode, lhs)
  local existing = vim_api.fn.maparg(lhs, mode)
  if type(existing) == "string" then
    return existing ~= ""
  end
  if type(existing) == "table" then
    return next(existing) ~= nil
  end
  return existing ~= nil and existing ~= false
end

--- Record a mapping so it can be removed later by unregister.
---@param mode string
---@param lhs string
---@return nil
local function remember_mapping(mode, lhs)
  table.insert(registered, { mode = mode, lhs = lhs })
end

--- Remove all previously registered keymaps and clear the tracking list.
---@param vim_api table
---@return nil
function M.unregister(vim_api)
  vim_api = vim_api or vim
  for _, map in ipairs(registered) do
    pcall(vim_api.keymap.del, map.mode, map.lhs)
  end
  registered = {}
end

--- Create a single keymap unless disabled or already taken (and not forced).
---@param vim_api table
---@param mode string
---@param lhs string|false
---@param rhs string|function
---@param desc string
---@param force boolean
---@return nil
local function set_mapping(vim_api, mode, lhs, rhs, desc, force)
  if lhs == false then
    return
  end
  if not force and mapping_exists(vim_api, mode, lhs) then
    return
  end
  vim_api.keymap.set(mode, lhs, rhs, { silent = true, desc = desc })
  remember_mapping(mode, lhs)
end

--- Register all global Codex keymaps from the user config.
---@param config codex.Config
---@param vim_api? table
---@return nil
function M.register(config, vim_api)
  vim_api = vim_api or vim
  M.unregister(vim_api)

  if config.keymaps == false then
    return
  end

  local maps = config.keymaps
  local force = config.keymaps_force

  set_mapping(vim_api, "n", maps.toggle, "<Cmd>Codex<CR>", "Codex: Toggle terminal", force)
  set_mapping(vim_api, "n", maps.open, "<Cmd>Codex!<CR>", "Codex: Open and focus", force)
  set_mapping(vim_api, "n", maps.focus, "<Cmd>CodexFocus<CR>", "Codex: Focus terminal", force)
  set_mapping(vim_api, "n", maps.close, "<Cmd>CodexClose<CR>", "Codex: Close session", force)
  set_mapping(vim_api, "n", maps.add, "<Cmd>CodexAdd<CR>", "Codex: Add current file", force)
  set_mapping(vim_api, "n", maps.resume, "<Cmd>CodexResume<CR>", "Codex: Resume session", force)
  set_mapping(vim_api, "n", maps.model, "<Cmd>CodexModel<CR>", "Codex: Set model", force)
  set_mapping(vim_api, "n", maps.status, "<Cmd>CodexStatus<CR>", "Codex: Show status", force)
  set_mapping(
    vim_api,
    "n",
    maps.permissions,
    "<Cmd>CodexPermissions<CR>",
    "Codex: Permissions",
    force
  )
  set_mapping(vim_api, "n", maps.compact, "<Cmd>CodexCompact<CR>", "Codex: Compact context", force)
  set_mapping(vim_api, "n", maps.review, "<Cmd>CodexReview<CR>", "Codex: Review changes", force)
  set_mapping(vim_api, "n", maps.diff, "<Cmd>CodexDiff<CR>", "Codex: Show diff", force)

  if maps.send ~= false then
    set_mapping(vim_api, "n", maps.send, "<Cmd>CodexSend<CR>", "Codex: Send current line", force)
    set_mapping(vim_api, "x", maps.send, function()
      local mode = vim_api.fn.visualmode and vim_api.fn.visualmode(1) or nil
      if mode ~= "v" and mode ~= "V" and mode ~= CTRL_V then
        mode = nil
      end

      local line1 = vim_api.fn.line("v")
      local line2 = vim_api.fn.line(".")
      local start_col = vim_api.fn.col("v")
      local end_col = vim_api.fn.col(".")

      if type(start_col) == "number" and start_col > 0 then
        start_col = start_col - 1
      else
        start_col = nil
      end
      if type(end_col) == "number" and end_col > 0 then
        end_col = end_col - 1
      else
        end_col = nil
      end

      require("codex").send_selection({
        line1 = line1,
        line2 = line2,
        start_col = start_col,
        end_col = end_col,
        visual_mode = mode,
      })
    end, "Codex: Send selection", force)
  end
end

return M
