local actions = require("codex.builtin.keymaps")
local M = {}

local descriptions = {
  [actions.toggle] = "Codex: Toggle terminal",
  [actions.clear_input] = "Codex: Clear input",
  [actions.unfocus] = "Codex: Return to previous buffer",
  [actions.close] = "Codex: Close terminal",
  [actions.nav_left] = "Codex: Move to left window",
  [actions.nav_down] = "Codex: Move to below window",
  [actions.nav_up] = "Codex: Move to above window",
  [actions.nav_right] = "Codex: Move to right window",
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
---@return nil
function M.apply_terminal(bufnr, keymaps)
  if type(keymaps) ~= "table" then
    return
  end

  for lhs, binding in pairs(keymaps) do
    vim.keymap.set(binding.mode, lhs, binding.action, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = binding.desc or M.get_builtin_desc(binding.action),
    })
  end
end

return M
