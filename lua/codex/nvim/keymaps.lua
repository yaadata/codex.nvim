local actions = require("codex.builtin.keymaps")
local M = {}

local descriptions = {
  [actions.toggle] = "Codex: Toggle terminal",
  [actions.clear_input] = "Codex: Clear input",
  [actions.unfocus] = "Codex: Return to previous buffer",
  [actions.teardown] = "Codex: Teardown / quit terminal",
  [actions.nav_left] = "Codex: Move to left window",
  [actions.nav_down] = "Codex: Move to below window",
  [actions.nav_up] = "Codex: Move to above window",
  [actions.nav_right] = "Codex: Move to right window",
}

local MODE_EXPANSIONS = {
  [""] = { "n", "x", "s", "o" },
  v = { "x", "s" },
  ["!"] = { "i", "c" },
  n = { "n" },
  x = { "x" },
  s = { "s" },
  o = { "o" },
  i = { "i" },
  c = { "c" },
  t = { "t" },
  l = { "l" },
}

---@param action function
---@return boolean
function M.is_builtin_action(action)
  return descriptions[action] ~= nil
end

---@param action function
---@return string|nil
function M.get_builtin_desc(action)
  return descriptions[action]
end

---@param bufnr integer
---@param keymaps codex.TerminalKeymapConfig|nil
---@param profile_name? string
---@return nil
function M.apply_terminal(bufnr, keymaps, profile_name)
  if type(keymaps) ~= "table" then
    return
  end

  for lhs, binding in pairs(keymaps) do
    local action = binding.action
    if
      profile_name
      and (action == actions.toggle or action == actions.clear_input or action == actions.teardown)
    then
      local function is_owner_selected()
        return require("codex").get_profile() == profile_name
      end
      local builtin = action
      action = function()
        if is_owner_selected() then
          builtin(is_owner_selected)
        end
      end
    end
    vim.keymap.set(binding.mode, lhs, action, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = binding.desc or M.get_builtin_desc(binding.action),
    })
  end
end

---@param mode_spec string|string[]
---@return string[]|nil concrete_modes
---@return string|nil err
local function expand_modes(mode_spec)
  local mode_list = type(mode_spec) == "string" and { mode_spec } or mode_spec

  local concrete = {}
  for _, mode in ipairs(mode_list) do
    local expanded = MODE_EXPANSIONS[mode]
    if not expanded then
      return nil, string.format("invalid keymap mode %q", tostring(mode))
    end
    for _, single in ipairs(expanded) do
      table.insert(concrete, single)
    end
  end
  return concrete, nil
end

---@param maps table[]
---@param termcoded string
---@param canonical_lhs string
---@return table|nil
local function find_global_map_entry(maps, termcoded, canonical_lhs)
  for _, entry in ipairs(maps) do
    if entry.lhsraw ~= nil then
      if entry.lhsraw == termcoded or entry.lhsrawalt == termcoded then
        return entry
      end
    elseif entry.lhs == canonical_lhs then
      return entry
    end
  end
  return nil
end

---@param slot table
---@return table|nil removed
local function restore_or_delete_slot(slot)
  local current_maps = vim.api.nvim_get_keymap(slot.mode)
  local current = find_global_map_entry(current_maps, slot.termcoded, slot.canonical_lhs)
  if not current or current.callback ~= slot.wrapper then
    return
  end

  local ok
  if slot.displaced ~= nil then
    ok = pcall(vim.fn.mapset, vim.deepcopy(slot.displaced))
  else
    ok = pcall(vim.api.nvim_del_keymap, slot.mode, current.lhs or slot.lhs)
  end
  return ok and current or nil
end

local function plan_global_slots(bindings)
  local api = vim.api
  local plan = {}
  local seen_slots = {}

  for lhs, binding in pairs(bindings) do
    local desc = binding.desc or M.get_builtin_desc(binding.action)

    local ok_tc, termcoded = pcall(api.nvim_replace_termcodes, lhs, true, true, true)
    if not ok_tc or type(termcoded) ~= "string" or termcoded == "" then
      return nil, string.format("invalid global keymap lhs %q", lhs)
    end

    local canonical_lhs = lhs
    if vim.fn and type(vim.fn.keytrans) == "function" then
      local ok_kt, kt = pcall(vim.fn.keytrans, termcoded)
      if ok_kt and type(kt) == "string" and kt ~= "" then
        canonical_lhs = kt
      end
    end

    local concrete_modes, mode_err = expand_modes(binding.mode)
    if not concrete_modes then
      return nil, string.format("global keymap %q: %s", lhs, mode_err)
    end

    for _, concrete_mode in ipairs(concrete_modes) do
      local slot_key = concrete_mode .. "\0" .. canonical_lhs
      if seen_slots[slot_key] then
        return nil,
          string.format(
            "overlapping global keymap slot for mode %q and lhs %q",
            concrete_mode,
            canonical_lhs
          )
      end
      seen_slots[slot_key] = true
      table.insert(plan, {
        mode = concrete_mode,
        lhs = lhs,
        termcoded = termcoded,
        canonical_lhs = canonical_lhs,
        action = binding.action,
        desc = desc,
      })
    end
  end

  return plan
end

---@param bindings codex.GlobalKeymapConfig|nil
---@return { stop: fun(self): (fun()|nil) }|nil handle
---@return string|nil err
function M.apply_global(bindings)
  if type(bindings) ~= "table" or next(bindings) == nil then
    return { stop = function() end }, nil
  end

  local plan, plan_err = plan_global_slots(bindings)
  if not plan then
    return nil, plan_err
  end

  local api = vim.api
  local initial_maps_by_mode = {}
  local installed = {}

  local function rollback()
    for index = #installed, 1, -1 do
      restore_or_delete_slot(installed[index])
    end
  end

  for _, entry in ipairs(plan) do
    local mode_maps = initial_maps_by_mode[entry.mode]
    if not mode_maps then
      mode_maps = api.nvim_get_keymap(entry.mode)
      initial_maps_by_mode[entry.mode] = mode_maps
    end

    local existing = find_global_map_entry(mode_maps, entry.termcoded, entry.canonical_lhs)
    local displaced = nil
    if existing ~= nil then
      displaced = vim.deepcopy(existing)
      displaced.mode = entry.mode
      displaced.mode_bits = nil
    end

    local wrapper = function()
      return entry.action()
    end

    local ok_set, set_err = pcall(vim.keymap.set, entry.mode, entry.lhs, wrapper, {
      silent = true,
      desc = entry.desc,
    })
    if not ok_set then
      rollback()
      return nil, tostring(set_err)
    end

    table.insert(installed, {
      mode = entry.mode,
      lhs = entry.lhs,
      termcoded = entry.termcoded,
      canonical_lhs = entry.canonical_lhs,
      wrapper = wrapper,
      displaced = displaced,
    })
  end

  local stopped = false
  return {
    stop = function()
      if stopped then
        return
      end
      stopped = true
      local removed = {}
      for index = #installed, 1, -1 do
        local map = restore_or_delete_slot(installed[index])
        if map then
          removed[#removed + 1] = map
        end
      end
      return function()
        for _, map in ipairs(removed) do
          vim.fn.mapset(map)
        end
        stopped = false
      end
    end,
  },
    nil
end

return M
