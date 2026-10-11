local M = {}
local _DEFAULT_DELAY = 250

---@param op fun(): nil
---@param delay? integer
local async_delay = function(op, delay)
  delay = delay or _DEFAULT_DELAY
  vim.defer_fn(function()
    op()
  end, delay)
end
--- one_off runs a one_off function with the agent terminal
--- harness in focus
---@param fn fun(): nil
function M.one_off(fn)
  if type(fn) ~= "function" then
    vim.notify("one_off command input `fn` must be a function")
  end
  ---@type codex.Api
  local codex = require("codex")
  local is_focused = codex.session.is_focused()
  if not codex.session.is_running() then
    codex.session.open(true)
    async_delay(function()
      fn()
      async_delay(codex.session.unfocus)
    end, 1050)
  else
    local delay = is_focused and 0 or _DEFAULT_DELAY
    if not is_focused then
      codex.session.focus()
    end
    async_delay(function()
      fn()
      async_delay(function()
        if not is_focused then
          codex.session.unfocus()
        end
      end)
    end, delay)
  end
end

return M
