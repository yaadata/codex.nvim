local Queue = {}
Queue.__index = Queue

---@class codex.SendQueueOpts
---@field vim table
---@field retry_interval_ms integer
---@field process fun(item: table): "sent"|"retry"|"drop", string|nil

---@class codex.SendQueue
---@field _vim table
---@field _retry_interval_ms integer
---@field _process fun(item: table): "sent"|"retry"|"drop", string|nil
---@field _items table[]
---@field _flush_scheduled boolean
---@field _flush_active boolean

--- Schedule a deferred flush of the queue if one is not already pending.
---@param self codex.SendQueue
---@return nil
local function schedule_flush(self)
  if self._flush_scheduled then
    return
  end

  self._flush_scheduled = true
  local run = function()
    self._flush_scheduled = false
    self:_flush()
  end

  if type(self._vim.defer_fn) == "function" then
    self._vim.defer_fn(run, self._retry_interval_ms)
    return
  end

  self._vim.schedule(run)
end

--- Drain queued items by calling the process callback; stop on retry and reschedule.
---@return nil
function Queue:_flush()
  if self._flush_active then
    return
  end

  self._flush_active = true
  while true do
    local item = self._items[1]
    if not item then
      break
    end

    local outcome = self._process(item)
    if outcome == "retry" then
      break
    end

    table.remove(self._items, 1)
  end

  self._flush_active = false
  if #self._items > 0 then
    schedule_flush(self)
  end
end

--- Attempt to send an item immediately; queue it for retry if the processor requests it.
---@param item table
---@return boolean ok
---@return string|nil err
function Queue:submit(item)
  local outcome, err = self._process(item)
  if outcome == "sent" then
    return true
  end

  if outcome == "drop" then
    return false, err
  end

  table.insert(self._items, item)
  schedule_flush(self)
  return true
end

--- Clear all queued items and reset flush state.
---@return nil
function Queue:reset()
  self._items = {}
  self._flush_scheduled = false
  self._flush_active = false
end

local M = {}

--- Create a new send queue with the given options.
---@param opts codex.SendQueueOpts
---@return codex.SendQueue
function M.new(opts)
  return setmetatable({
    _vim = opts.vim,
    _retry_interval_ms = opts.retry_interval_ms,
    _process = opts.process,
    _items = {},
    _flush_scheduled = false,
    _flush_active = false,
  }, Queue)
end

return M
