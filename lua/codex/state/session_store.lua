local M = {}

---@type table<string, codex.Session>
local sessions = {}
---@type string|nil
local active_id = nil
local counter = 0

--- Create a new session from the given spec, store it, and set it as active.
---@param spec codex.SessionSpec
---@return string id
function M.create(spec)
  counter = counter + 1
  local id = "session_" .. counter

  sessions[id] = {
    id = id,
    handle = spec.handle,
    cmd = spec.cmd,
    cwd = spec.cwd,
    provider_name = spec.provider_name,
    alive = true,
  }

  active_id = id
  return id
end

--- Look up a session by its id.
---@param id string
---@return codex.Session|nil
function M.get(id)
  return sessions[id]
end

--- Return the currently active session, or nil if none is active.
---@return codex.Session|nil
function M.get_active()
  if active_id then
    return sessions[active_id]
  end
  return nil
end

--- Set the active session id; pass nil to clear the active session.
---@param id string|nil
---@return nil
function M.set_active(id)
  active_id = id
end

--- Mark a session as no longer alive and clear it from active if it was active.
---@param id string
---@return nil
function M.mark_dead(id)
  if sessions[id] then
    sessions[id].alive = false
  end
  if active_id == id then
    active_id = nil
  end
end

--- Remove a session from the store entirely and clear it from active if needed.
---@param id string
---@return nil
function M.remove(id)
  sessions[id] = nil
  if active_id == id then
    active_id = nil
  end
end

--- Return a list of all stored sessions.
---@return codex.Session[]
function M.list()
  ---@type codex.Session[]
  local result = {}
  for _, session in pairs(sessions) do
    table.insert(result, session)
  end
  return result
end

--- Clear all sessions, the active id, and reset the id counter.
---@return nil
function M.reset()
  sessions = {}
  active_id = nil
  counter = 0
end

return M
