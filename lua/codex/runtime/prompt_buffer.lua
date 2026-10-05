local Builder = {}

---@alias codex.PromptBufferArray string[]

Builder.__index = Builder
Builder._fragments = {}

---@param _fragment string
function Builder:add(_fragment)
  table.insert(self._fragments, _fragment)
end

---@return codex.PromptBufferArray
function Builder:peak()
  return self._fragments
end

---@param buffer codex.PromptBufferArray
function Builder:join(buffer)
  for _, fragment in ipairs(buffer) do
    table.insert(self._fragments, fragment)
  end
end

---@return string
---@return codex.PromptBufferArray
function Builder:take()
  local fragments = self._fragments
  self._fragments = {}
  return table.concat(fragments), fragments
end

---@return nil
function Builder:reset()
  self._fragments = {}
end

---@return boolean
function Builder:is_empty()
  return #self._fragments == 0
end

local M = {}

---@param  buffer codex.PromptBufferArray?
---@return codex.PromptBuffer
function M.new(buffer)
  local _fragments = {}
  if buffer ~= nil and type(buffer) == "table" then
    _fragments = buffer
  end
  return setmetatable({ _fragments = _fragments }, Builder)
end

return M
