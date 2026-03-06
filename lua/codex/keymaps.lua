local M = {}

local builtin_desc_by_action = setmetatable({}, { __mode = "k" })

local function feed_terminal_keys(keys)
  local encoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(encoded, "n", false)
end

local builtins = {}

local function register_builtin(name, action, desc)
  builtins[name] = action
  builtin_desc_by_action[action] = desc
end

register_builtin("toggle", function()
  require("codex").toggle()
end, "Codex: Toggle terminal")

register_builtin("clear_input", function()
  require("codex").clear_input()
end, "Codex: Clear input")

register_builtin("close", function()
  vim.schedule(function()
    require("codex").close()
  end)
end, "Codex: Close terminal")

register_builtin("nav_left", function()
  feed_terminal_keys("<C-\\><C-n><C-w>h")
end, "Codex: Move to left window")

register_builtin("nav_down", function()
  feed_terminal_keys("<C-\\><C-n><C-w>j")
end, "Codex: Move to below window")

register_builtin("nav_up", function()
  feed_terminal_keys("<C-\\><C-n><C-w>k")
end, "Codex: Move to above window")

register_builtin("nav_right", function()
  feed_terminal_keys("<C-\\><C-n><C-w>l")
end, "Codex: Move to right window")

M.builtins = builtins

---@param action function
---@return boolean
function M.is_builtin_action(action)
  return builtin_desc_by_action[action] ~= nil
end

---@param action function
---@return string|nil
function M.get_builtin_desc(action)
  return builtin_desc_by_action[action]
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
